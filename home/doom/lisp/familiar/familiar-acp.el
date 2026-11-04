;;; familiar-acp.el --- familiar as an ACP agent, served by Emacs -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; The Agent Client Protocol lets editors (Zed, agent-shell, ...) drive an
;; agent.  This makes familiar one: an editor runs the `familiar-acp'
;; command as its agent; that connects to this Emacs, which answers.  The
;; conversation runs on familiar's model, priced in the ledger and kept in
;; the history, from wherever the editor is.
;;
;;   M-x familiar-acp-start   listen on 127.0.0.1:`familiar-acp-port'
;;   M-x familiar-acp-stop
;;
;; The wire is ACP's own (protocol version 1): JSON-RPC 2.0, one message
;; per line.  A connection's first line is "AUTH <token>" with the token of
;; familiar-mcp-http (`familiar-mcp-http-token-file'); the command sends it.
;;
;; Implemented: initialize, authenticate, session/new, session/prompt
;; (streamed as agent_message_chunk updates; stopReason end_turn or
;; cancelled), session/cancel.  Text and embedded resources in prompts.
;; Tools, when the client offers them: read_file (fs/read_text_file) and
;; write_file (fs/write_text_file, after session/request_permission), shown
;; as tool_call updates.  Not yet: terminal/*, session/load.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'lisp-mnt)

(declare-function familiar-mcp-http-token "familiar-mcp-http" ())
(declare-function gptel-abort "ext:gptel" (buf))
(declare-function gptel-make-tool "ext:gptel" (&rest slots))

(defgroup familiar-acp nil
  "familiar as an ACP agent."
  :group 'familiar)

(defcustom familiar-acp-port 39392
  "Port on 127.0.0.1 the `familiar-acp' command connects to."
  :type 'natnum)

(defcustom familiar-acp-tier 'smart
  "Tier answering ACP sessions."
  :type 'symbol)

(defvar familiar-acp-system
  "You are familiar, an assistant running inside the user's Emacs, reached \
from their editor over the Agent Client Protocol.  Answer what they ask \
about their code and work; be concise.  When the editor offers them, read_file reads its \
files (unsaved changes included) and write_file changes one, after the \
user agrees there; otherwise show changes instead of claiming them."
  "System prompt; the session's working directory is appended.")

(defconst familiar-acp-protocol-version 1)

(defvar familiar-acp--server nil "The listening process.")
(defvar familiar-acp--sessions (make-hash-table :test #'equal)
  "Session id → plist (:cwd DIR :turns LIST :buffer BUF :pending ID :process P).")

;;;; Wire

(defun familiar-acp--send (proc object)
  "Send OBJECT (an alist) to PROC as one line of JSON."
  (when (process-live-p proc)
    (process-send-string
     proc (concat (encode-coding-string
                   (json-serialize object :null-object :null :false-object :false)
                   'utf-8)
                  "\n"))))

(defun familiar-acp--result (proc id result)
  (familiar-acp--send proc `((jsonrpc . "2.0") (id . ,id) (result . ,result))))

(defun familiar-acp--error (proc id code message)
  (familiar-acp--send proc `((jsonrpc . "2.0") (id . ,id)
                             (error . ((code . ,code) (message . ,message))))))

(defun familiar-acp--notify (proc method params)
  (familiar-acp--send proc `((jsonrpc . "2.0") (method . ,method) (params . ,params))))

(defun familiar-acp--filter (proc chunk)
  (let ((pending (concat (or (process-get proc :pending) "") chunk))
        line)
    (while (string-match "\n" pending)
      (setq line (decode-coding-string (substring pending 0 (match-beginning 0)) 'utf-8)
            pending (substring pending (match-end 0)))
      (unless (string-blank-p line)
        (familiar-acp--line proc line)))
    (process-put proc :pending pending)))

(defun familiar-acp--line (proc line)
  "Handle one LINE from PROC: the AUTH greeting first, then JSON-RPC."
  (cond
   ((not (process-get proc :authed))
    (if (and (string-match "\\`AUTH \\(\\S-+\\)\\'" line)
             (equal (secure-hash 'sha256 (match-string 1 line))
                    (secure-hash 'sha256 (familiar-mcp-http-token))))
        (process-put proc :authed t)
      (delete-process proc)))
   (t
    (let ((msg (ignore-errors (json-parse-string line :object-type 'alist :array-type 'list
                                                 :null-object nil :false-object nil))))
      (if (not (consp msg))
          (familiar-acp--error proc :null -32700 "Parse error")
        (condition-case err
            (familiar-acp-dispatch proc msg)
          (error (when (alist-get 'id msg)
                   (familiar-acp--error proc (alist-get 'id msg) -32603
                                        (error-message-string err))))))))))

(defun familiar-acp--request (proc method params callback)
  "Send METHOD with PARAMS to the client on PROC; CALLBACK gets (RESULT ERROR)."
  (let* ((n (1+ (or (process-get proc :next-id) 0)))
         (id (format "familiar-%d" n)))
    (process-put proc :next-id n)
    (process-put proc :waiting (cons (cons id callback) (process-get proc :waiting)))
    (familiar-acp--send proc `((jsonrpc . "2.0") (id . ,id) (method . ,method) (params . ,params)))))

;;;; Tools: the client's files, through the client

(defun familiar-acp--tool-update (proc sid call-id fields)
  "Send a tool_call (FIELDS with :title) or tool_call_update for CALL-ID."
  (familiar-acp--notify
   proc "session/update"
   `((sessionId . ,sid)
     (update . ((sessionUpdate . ,(if (assq 'title fields) "tool_call" "tool_call_update"))
                (toolCallId . ,call-id) ,@fields)))))

(defun familiar-acp--tools (proc sid cwd)
  "gptel tools for session SID on PROC: what its client can do with files.
Reads go straight to the client; writes ask the user there first."
  (let* ((caps (alist-get 'fs (process-get proc :caps)))
         (absolute (lambda (path) (expand-file-name path (or cwd default-directory))))
         (calls 0)
         (call-id (lambda () (format "familiar_call_%d" (cl-incf calls))))
         tools)
    (when (alist-get 'readTextFile caps)
      (push (gptel-make-tool
             :name "read_file" :category "acp" :async t
             :description "Read a text file from the user's editor (unsaved changes included)."
             :args '((:name "path" :type string :description "File path, absolute or relative to the working directory")
                     (:name "line" :type integer :description "First line, 1-based" :optional t)
                     (:name "limit" :type integer :description "Number of lines" :optional t))
             :function
             (lambda (callback path &optional line limit)
               (let ((id (funcall call-id)) (path (funcall absolute path)))
                 (familiar-acp--tool-update proc sid id `((title . ,(format "Read %s" path)) (kind . "read")
                                                          (status . "in_progress")
                                                          (locations . [((path . ,path))])))
                 (familiar-acp--request
                  proc "fs/read_text_file"
                  `((sessionId . ,sid) (path . ,path)
                    ,@(and line `((line . ,line))) ,@(and limit `((limit . ,limit))))
                  (lambda (result err)
                    (familiar-acp--tool-update proc sid id `((status . ,(if err "failed" "completed"))))
                    (funcall callback (if err (format "Error: %s" (alist-get 'message err))
                                        (familiar-acp--cap (or (alist-get 'content result) "")))))))))
            tools))
    (when (alist-get 'writeTextFile caps)
      (push (gptel-make-tool
             :name "write_file" :category "acp" :async t
             :description "Write a text file in the user's editor (they are asked first). Give the whole new content."
             :args '((:name "path" :type string :description "File path, absolute or relative to the working directory")
                     (:name "content" :type string :description "The complete new file content"))
             :function
             (lambda (callback path content)
               (let ((id (funcall call-id)) (path (funcall absolute path)))
                 (familiar-acp--tool-update proc sid id `((title . ,(format "Write %s" path)) (kind . "edit")
                                                          (status . "pending")
                                                          (locations . [((path . ,path))])))
                 (familiar-acp--request
                  proc "session/request_permission"
                  `((sessionId . ,sid)
                    (toolCall . ((toolCallId . ,id) (title . ,(format "Write %s" path)) (kind . "edit")))
                    (options . [((optionId . "allow") (name . "Write it") (kind . "allow_once"))
                                ((optionId . "reject") (name . "Don't") (kind . "reject_once"))]))
                  (lambda (result _err)
                    (let ((outcome (alist-get 'outcome result)))
                      (if (not (and (equal (alist-get 'outcome outcome) "selected")
                                    (equal (alist-get 'optionId outcome) "allow")))
                          (progn (familiar-acp--tool-update proc sid id '((status . "failed")))
                                 (funcall callback "The user declined; nothing was written."))
                        (familiar-acp--tool-update proc sid id '((status . "in_progress")))
                        (familiar-acp--request
                         proc "fs/write_text_file"
                         `((sessionId . ,sid) (path . ,path) (content . ,content))
                         (lambda (_ err)
                           (familiar-acp--tool-update proc sid id `((status . ,(if err "failed" "completed"))))
                           (funcall callback (if err (format "Error: %s" (alist-get 'message err))
                                               (format "Wrote %s" path))))))))))))
            tools))
    (nreverse tools)))

(defun familiar-acp--cap (text)
  "TEXT, cut to 20000 characters for the model."
  (if (> (length text) 20000)
      (concat (substring text 0 20000) (format "\n[… %d more characters]" (- (length text) 20000)))
    text))

;;;; Methods

(defun familiar-acp-dispatch (proc msg)
  "Answer MSG (a JSON-RPC message as an alist) from PROC."
  (let ((id (alist-get 'id msg))
        (params (alist-get 'params msg)))
    (pcase (alist-get 'method msg)
      ;; A response to a request of ours (fs/*, session/request_permission).
      ('nil
       (when-let* ((waiting (assoc id (process-get proc :waiting))))
         (process-put proc :waiting (delq waiting (process-get proc :waiting)))
         (funcall (cdr waiting) (alist-get 'result msg) (alist-get 'error msg))))
      ("initialize"
       (process-put proc :caps (alist-get 'clientCapabilities params))
       (familiar-acp--result
        proc id
        `((protocolVersion . ,familiar-acp-protocol-version)
          ;; Only what's supported: the spec reads an omitted capability as
          ;; unsupported, and agent-shell listed false ones as available.
          (agentCapabilities . ((promptCapabilities . ((embeddedContext . t)))))
          (agentInfo . ((name . "familiar") (title . "familiar (Emacs)")
                        (version . ,(or (ignore-errors
                                          (with-temp-buffer
                                            (insert-file-contents (locate-library "familiar.el" t))
                                            (lm-version)))
                                        "0.1.0"))))
          (authMethods . []))))
      ("authenticate" (familiar-acp--result proc id (make-hash-table)))
      ("session/new"
       (let ((sid (format "sess_%x%x" (random most-positive-fixnum) (emacs-pid))))
         (puthash sid (list :cwd (alist-get 'cwd params) :turns nil :process proc)
                  familiar-acp--sessions)
         (familiar-acp--result proc id `((sessionId . ,sid)))))
      ("session/prompt" (familiar-acp--prompt proc id params))
      ("session/cancel" (familiar-acp--cancel (alist-get 'sessionId params)))
      ((and method (guard id))
       (familiar-acp--error proc id -32601 (format "Method not found: %s" method)))
      (_ nil))))                        ; other notifications, responses

(defun familiar-acp-prompt-text (blocks)
  "ACP prompt content BLOCKS as one text for the model."
  (mapconcat
   (lambda (b)
     (pcase (alist-get 'type b)
       ("text" (alist-get 'text b))
       ("resource"
        (let ((r (alist-get 'resource b)))
          (format "File %s:\n```\n%s\n```" (alist-get 'uri r) (or (alist-get 'text r) ""))))
       ("resource_link" (format "(See %s.)" (alist-get 'uri b)))
       (_ "")))
   blocks "\n\n"))

(defun familiar-acp--prompt (proc id params)
  (let* ((sid (alist-get 'sessionId params))
         (session (gethash sid familiar-acp--sessions)))
    (if (not session)
        (familiar-acp--error proc id -32602 (format "No session %s" sid))
      (let* ((text (familiar-acp-prompt-text (alist-get 'prompt params)))
             (turns (append (plist-get session :turns) (list text)))
             (buf (generate-new-buffer " *familiar-acp*"))
             (answer "")
             (finish
              (lambda (reason)
                (when (equal (plist-get (gethash sid familiar-acp--sessions) :pending) id)
                  (let ((s (gethash sid familiar-acp--sessions)))
                    (puthash sid (plist-put (plist-put s :pending nil) :turns
                                            (if (equal reason "end_turn")
                                                (append turns (list answer))
                                              (plist-get s :turns)))
                             familiar-acp--sessions))
                  (familiar-acp--result proc id `((stopReason . ,reason))))
                (run-at-time 0 nil (lambda () (when (buffer-live-p buf) (kill-buffer buf))))))
             (familiar-task-tiers (cons (cons 'acp familiar-acp-tier) familiar-task-tiers)))
        (setq session (plist-put (plist-put session :pending id) :buffer buf))
        (puthash sid session familiar-acp--sessions)
        (with-current-buffer buf
          (familiar-request
           turns :task 'acp :stream t
           :tools (familiar-acp--tools proc sid (plist-get session :cwd))
           :system (concat familiar-acp-system
                           (when-let* ((cwd (plist-get session :cwd)))
                             (format "\n\nThe user's working directory: %s" cwd)))
           :callback
           (lambda (response info)
             (pcase response
               ((pred stringp)
                (setq answer (concat answer response))
                (familiar-acp--notify
                 proc "session/update"
                 `((sessionId . ,sid)
                   (update . ((sessionUpdate . "agent_message_chunk")
                              (content . ((type . "text") (text . ,response))))))))
               ;; A segment ended; with a tool call pending, gptel runs it and
               ;; goes on: the turn isn't over.
               ('t (unless (or (plist-get info :tool-use)
                              (equal (plist-get info :stop-reason) "tool_use"))
                    (funcall finish "end_turn")))
               ('abort (funcall finish "cancelled"))
               ('nil
                (when (equal (plist-get (gethash sid familiar-acp--sessions) :pending) id)
                  (puthash sid (plist-put (gethash sid familiar-acp--sessions) :pending nil)
                           familiar-acp--sessions)
                  (familiar-acp--error proc id -32603
                                       (format "familiar: %s" (or (plist-get info :status) "no answer")))))))))))))

(defun familiar-acp--cancel (sid)
  "Stop session SID's turn; its prompt is answered with stopReason cancelled."
  (when-let* ((session (gethash sid familiar-acp--sessions))
              (buf (plist-get session :buffer))
              ((buffer-live-p buf)))
    (gptel-abort buf)))

(defun familiar-acp--sentinel (proc _event)
  "When an editor's connection PROC closes: drop its sessions, stop their turns."
  (unless (process-live-p proc)
    (maphash (lambda (sid session)
               (when (eq (plist-get session :process) proc)
                 (familiar-acp--cancel sid)
                 (remhash sid familiar-acp--sessions)))
             familiar-acp--sessions)))

;;;; Commands

;;;###autoload
(defun familiar-acp-start (&optional port)
  "Serve familiar as an ACP agent on 127.0.0.1:PORT."
  (interactive)
  (require 'familiar-mcp-http)
  (familiar-acp-stop)
  (familiar-mcp-http-token)                 ; make sure there is one
  (setq familiar-acp--server
        (make-network-process :name "familiar-acp" :server t
                              :host "127.0.0.1" :service (or port familiar-acp-port)
                              :family 'ipv4 :coding 'binary :noquery t
                              :filter #'familiar-acp--filter
                              :sentinel #'familiar-acp--sentinel))
  (let ((port (process-contact familiar-acp--server :service)))
    (when (called-interactively-p 'interactive)
      (message "familiar ACP agent on 127.0.0.1:%d" port))
    port))

;;;###autoload
(defun familiar-acp-stop ()
  "Stop serving ACP."
  (interactive)
  (when (process-live-p familiar-acp--server)
    (delete-process familiar-acp--server))
  (setq familiar-acp--server nil))

(provide 'familiar-acp)
;;; familiar-acp.el ends here
