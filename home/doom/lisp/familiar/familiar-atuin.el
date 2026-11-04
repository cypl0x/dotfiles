;;; familiar-atuin.el --- Atuin AI's server, answered by familiar -*- lexical-binding: t; -*-
;;
;; Atuin's AI (the ? in your shell) talks to a server: Atuin Hub by
;; default, or any "OSS" server at `ai.endpoint'.  This is one, inside
;; Emacs: POST /api/cli/chat on familiar-mcp-http's server, answered by
;; familiar (your key, the ledger, the budget; task `atuin').
;;
;;   ATUIN_AI__ENDPOINT=http://127.0.0.1:39391
;;   ATUIN_AI__ENDPOINT_PROTOCOL=oss
;;   ATUIN_AI__API_TOKEN=$(cat ~/.local/state/emacs/familiar-mcp-http-token)
;;
;; (Environment, not config.toml: that one is in the Nix store, readable
;; by everyone on the machine.)
;;
;; The protocol, from atuin-ai's stream.rs (18.18): the request carries
;; Claude-style messages, a context object (shell, os, cwd, last command)
;; and config; the answer is server-sent events: `text' {content},
;; `tool_call' {id, name, input}, `done' {session_id}, `error' {message}.
;; A command is a `suggest_command' tool call {command, danger}, which ends
;; the turn; Enter runs it, Tab puts it on the prompt.  Atuin's own client
;; tools (read_file, execute_shell_command, ...) aren't offered yet.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'familiar-mcp-http)

(defvar familiar-atuin-tier 'fast
  "Tier answering Atuin: shell commands want speed.")

(defvar familiar-atuin-system
  "You are the assistant behind the ? key in the user's shell (Atuin).  \
When they want something done, call suggest_command with one command for \
their shell and os, and its danger: low (only reads), medium (changes files \
or state, easy to undo), high (destructive or hard to undo: rm -r, force \
pushes, dd, chmod -R ...).  Don't explain a command they asked for unless \
asked.  When they ask a question, answer in a few plain lines.  Never \
pretend to have run anything."
  "System prompt; the shell context from Atuin is appended.")

(defvar familiar-atuin--suggest-tool nil)

(defun familiar-atuin--suggest-tool ()
  (or familiar-atuin--suggest-tool
      (setq familiar-atuin--suggest-tool
            (gptel-make-tool
             :name "suggest_command" :category "atuin"
             :description "Suggest one shell command; the user runs it (Enter) or puts it on the prompt (Tab)."
             :args '((:name "command" :type string :description "The command, for the user's shell")
                     (:name "danger" :type string :enum ["low" "medium" "high"]
                            :description "low: only reads; medium: changes, easy to undo; high: destructive"))
             :function (lambda (&rest _) "Shown to the user.")))))

(defun familiar-atuin--block-text (block)
  "One Claude content BLOCK as text for a plain conversation."
  (pcase (alist-get 'type block)
    ("text" (alist-get 'text block))
    ("tool_use" (format "(%s: %s)" (alist-get 'name block)
                        (or (alist-get 'command (alist-get 'input block))
                            (json-serialize (or (alist-get 'input block) (make-hash-table))))))
    ("tool_result" (let ((c (alist-get 'content block)))
                     (format "(result: %s)" (if (stringp c) c (json-serialize c)))))
    (_ "")))

(defun familiar-atuin-conversation (messages)
  "Atuin's Claude-style MESSAGES as turns alternating from the user."
  (let (turns last)
    (dolist (m messages)
      (let* ((side (if (equal (alist-get 'role m) "assistant") 'llm 'user))
             (content (alist-get 'content m))
             (text (string-trim (if (stringp content) content
                                  (mapconcat #'familiar-atuin--block-text content "\n")))))
        (cond ((string-empty-p text))
              ((and (null turns) (eq side 'llm)) (push "" turns) (push text turns) (setq last side))
              ((eq side last) (setcar turns (concat (car turns) "\n\n" text)))
              (t (push text turns) (setq last side)))))
    (nreverse turns)))

(defun familiar-atuin-handle (method path _headers body)
  "Route handler for /api/cli/ (see `familiar-mcp-http-routes')."
  (let ((req (and (equal method "POST") (equal (car (split-string path "?")) "/api/cli/chat")
                  (ignore-errors (json-parse-string body :object-type 'alist :array-type 'list
                                                    :null-object nil :false-object nil)))))
    (if (not (and req (alist-get 'messages req)))
        (list 400 nil "Expected POST /api/cli/chat with messages")
      (list :sse (lambda (send close) (familiar-atuin--answer req send close))))))

(defun familiar-atuin--answer (req send close)
  (let* ((turns (familiar-atuin-conversation (alist-get 'messages req)))
         (context (alist-get 'context req))
         (system (concat familiar-atuin-system
                         (when context
                           (concat "\n\nShell context from Atuin: " (json-serialize context)))))
         (familiar-task-tiers (cons (cons 'atuin familiar-atuin-tier) familiar-task-tiers))
         ;; Its own request buffer: ending the turn aborts what gptel would
         ;; do next, and `gptel-abort' stops every request of a buffer.
         (buf (generate-new-buffer " *familiar-atuin*"))
         (event (lambda (name object) (funcall send (json-serialize object) name)))
         (finish (lambda ()
                   (funcall event "done" '((session_id . "")))
                   (funcall close)
                   (run-at-time 0 nil (lambda ()
                                        (when (buffer-live-p buf)
                                          (ignore-errors (gptel-abort buf))
                                          (kill-buffer buf)))))))
    (with-current-buffer buf
      (familiar-request
       turns :task 'atuin :system system :stream t
       :tools (list (familiar-atuin--suggest-tool))
       :callback
       (lambda (response info)
         (pcase response
           ((pred stringp) (funcall event "text" `((content . ,response))))
           ;; A segment ended.  With tool calls pending, those are the
           ;; suggestion and the turn ends here: gptel would run the tool
           ;; and ask the model again, for text nobody sees.
           ('t
            (dolist (call (plist-get info :tool-use))
              (let ((args (plist-get call :args)))
                (funcall event "tool_call"
                         `((id . ,(or (plist-get call :id) ""))
                           (name . ,(plist-get call :name))
                           (input . ((command . ,(or (plist-get args :command) ""))
                                     (danger . ,(or (plist-get args :danger) "low"))))))))
            (funcall finish))
           ((or 'nil 'abort)
            (unless (eq response 'abort)
              (funcall event "error" `((message . ,(format "familiar: %s"
                                                           (or (plist-get info :status) "no answer")))))
              (funcall close)))
           (_ nil)))))))

(setf (alist-get "/api/cli/" familiar-mcp-http-routes nil nil #'equal) #'familiar-atuin-handle)

(provide 'familiar-atuin)
;;; familiar-atuin.el ends here
