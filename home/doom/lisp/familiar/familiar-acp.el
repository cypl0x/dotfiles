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
;; Not yet: tools (the client's fs/* and terminal/*), session/load.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'lisp-mnt)

(declare-function familiar-mcp-http-token "familiar-mcp-http" ())
(declare-function gptel-abort "ext:gptel" (buf))

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
about their code and work; be concise.  You can't run tools or edit files \
in this session yet: when a change is needed, show it."
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

;;;; Methods

(defun familiar-acp-dispatch (proc msg)
  "Answer MSG (a JSON-RPC message as an alist) from PROC."
  (let ((id (alist-get 'id msg))
        (params (alist-get 'params msg)))
    (pcase (alist-get 'method msg)
      ("initialize"
       (familiar-acp--result
        proc id
        `((protocolVersion . ,familiar-acp-protocol-version)
          (agentCapabilities . ((loadSession . :false)
                                (promptCapabilities . ((image . :false) (audio . :false)
                                                       (embeddedContext . t)))))
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
               ('t (funcall finish "end_turn"))
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
