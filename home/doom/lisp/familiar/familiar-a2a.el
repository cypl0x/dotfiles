;;; familiar-a2a.el --- familiar speaks A2A: agent and client -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; The Agent2Agent protocol (A2A 1.0, a2a-protocol.org; the normative
;; source is its a2a.proto) lets agents hand work to each other.  Both
;; sides, on familiar-mcp-http's server:
;;
;; Agent.  GET /.well-known/agent-card.json describes familiar (public, as
;; discovery documents are); POST /a2a takes JSON-RPC 2.0 with the token:
;;
;;   SendMessage            a Task, its answer as an artifact
;;                          (configuration.returnImmediately: WORKING now,
;;                          the rest via GetTask)
;;   SendStreamingMessage   server-sent: task, artifactUpdate chunks, then a
;;                          final statusUpdate
;;   GetTask, CancelTask, ListTasks
;;
;; A message's contextId carries a conversation on.  Answers come from
;; familiar's model (task a2a: ledger, budget, history).
;;
;; Client.  `familiar-a2a-agents' names remote agents; each is an @NAME
;; keyword in M-ß, offering the model a tool that delegates to that agent
;; for the turn.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url)
(require 'familiar)
(require 'familiar-mcp-http)

(declare-function familiar-ask--cap "familiar-ask" (text))
(declare-function gptel-make-tool "ext:gptel" (&rest slots))
(declare-function gptel-abort "ext:gptel" (buf))
(defvar familiar-ask-keyword-functions)
(defvar familiar-ask-turn-tools-functions)
(defvar url-http-end-of-headers)

(defgroup familiar-a2a nil
  "familiar and the Agent2Agent protocol."
  :group 'familiar)

(defcustom familiar-a2a-tier 'smart
  "Tier answering A2A tasks."
  :type 'symbol)

(defcustom familiar-a2a-agents nil
  "Remote A2A agents: alist NAME → plist (:url BASE-OR-CARD-URL :token TOKEN).
:token may be a string or a function returning one.  Each NAME is an @NAME
keyword in M-ß.  Example: ((\"self\" :url \"http://127.0.0.1:39391\"
:token familiar-mcp-http-token))."
  :type '(alist :key-type string :value-type plist))

(defconst familiar-a2a-version "1.0" "The A2A protocol version spoken.")
(defconst familiar-a2a-card-path "/.well-known/agent-card.json")

(defvar familiar-a2a--tasks (make-hash-table :test #'equal)
  "Task id → plist (:task ALIST :buffer BUF).")
(defvar familiar-a2a--contexts (make-hash-table :test #'equal)
  "Context id → turns (alternating from the user).")

(defun familiar-a2a--json (object)
  (json-serialize object :null-object :null :false-object :false))

(defun familiar-a2a--id (prefix)
  (format "%s-%x%x" prefix (random most-positive-fixnum) (emacs-pid)))

(defun familiar-a2a--now ()
  (format-time-string "%FT%T.%3NZ" nil t))

;;;; The agent card

(defun familiar-a2a-card ()
  "familiar's agent card (an alist, as A2A 1.0's AgentCard)."
  `((name . "familiar")
    (description . "An assistant running inside the user's Emacs, on their key and budget.")
    (supportedInterfaces
     . [((url . ,(replace-regexp-in-string "/mcp\\'" "/a2a" (or (familiar-mcp-http-url) "")))
         (protocolBinding . "JSONRPC")
         (protocolVersion . ,familiar-a2a-version))])
    (version . "0.1.0")
    (capabilities . ((streaming . t) (pushNotifications . :false)))
    (securitySchemes . ((bearer . ((httpAuthSecurityScheme . ((scheme . "Bearer")))))))
    (securityRequirements . [((schemes . ((bearer . ((list . []))))))])
    (defaultInputModes . ["text/plain"])
    (defaultOutputModes . ["text/plain"])
    (skills . [((id . "ask")
                (name . "Ask familiar")
                (description . "Answers questions and drafts text, code and commands.")
                (tags . ["assistant" "emacs"]))])))

;;;; Tasks

(defun familiar-a2a--text (message)
  "The text parts of an A2A MESSAGE, joined."
  (mapconcat (lambda (p) (or (alist-get 'text p) "")) (alist-get 'parts message) "\n"))

(defun familiar-a2a--message (role text context task)
  `((messageId . ,(familiar-a2a--id "msg")) (contextId . ,context) (taskId . ,task)
    (role . ,role) (parts . [((text . ,text))])))

(defun familiar-a2a--task (id)
  (plist-get (gethash id familiar-a2a--tasks) :task))

(defun familiar-a2a--set-state (id state &optional text)
  "Set task ID's STATE (a TASK_STATE_ string); TEXT becomes its artifact."
  (let* ((entry (gethash id familiar-a2a--tasks))
         (task (copy-alist (plist-get entry :task))))
    (setf (alist-get 'status task) `((state . ,state) (timestamp . ,(familiar-a2a--now))))
    (when text
      (setf (alist-get 'artifacts task)
            (vector `((artifactId . ,(concat id "-answer")) (name . "answer")
                      (parts . [((text . ,text))])))))
    (puthash id (plist-put entry :task task) familiar-a2a--tasks)
    task))

(defun familiar-a2a--terminal-p (state)
  (member state '("TASK_STATE_COMPLETED" "TASK_STATE_FAILED" "TASK_STATE_CANCELED"
                  "TASK_STATE_REJECTED")))

(defun familiar-a2a--start (message on-chunk on-end)
  "Start a task for MESSAGE; ON-CHUNK gets streamed text, ON-END the task.
Returns the task (state WORKING)."
  (let* ((context (or (alist-get 'contextId message) (familiar-a2a--id "ctx")))
         (id (familiar-a2a--id "task"))
         (text (familiar-a2a--text message))
         (turns (append (gethash context familiar-a2a--contexts) (list text)))
         (buf (generate-new-buffer " *familiar-a2a*"))
         (answer "")
         (familiar-task-tiers (cons (cons 'a2a familiar-a2a-tier) familiar-task-tiers)))
    (puthash id (list :buffer buf
                      :task `((id . ,id) (contextId . ,context)
                              (status . ((state . "TASK_STATE_WORKING") (timestamp . ,(familiar-a2a--now))))
                              (history . [,(let ((m (familiar-a2a--message "ROLE_USER" text context id)))
                                            ;; Rebuilt: parsed parts are lists, which
                                            ;; would serialize as objects.
                                            (setf (alist-get 'messageId m)
                                                  (or (alist-get 'messageId message) (alist-get 'messageId m)))
                                            m)])))
             familiar-a2a--tasks)
    (with-current-buffer buf
      (familiar-request
       turns :task 'a2a :stream t
       :system "You are familiar, an assistant inside the user's Emacs, answering another agent \
over A2A.  Answer the request itself, concisely and completely; no questions back."
       :callback
       (lambda (response info)
         (progn
           (unless (familiar-a2a--terminal-p (alist-get 'state (alist-get 'status (familiar-a2a--task id))))
             (pcase response
               ((pred stringp) (setq answer (concat answer response))
                (when on-chunk (funcall on-chunk response)))
               ('t (puthash context (append turns (list answer)) familiar-a2a--contexts)
                   (funcall on-end (familiar-a2a--set-state id "TASK_STATE_COMPLETED" answer)))
               ('abort (funcall on-end (familiar-a2a--set-state id "TASK_STATE_CANCELED")))
               ('nil (funcall on-end (familiar-a2a--set-state
                                      id "TASK_STATE_FAILED"
                                      (format "familiar: %s" (or (plist-get info :status) "no answer")))))))
           (when (and (memq response '(t nil abort)) (buffer-live-p buf))
             (run-at-time 0 nil #'kill-buffer buf))))))
    (familiar-a2a--task id)))

;;;; JSON-RPC

(defun familiar-a2a--rpc (id result)
  (familiar-a2a--json `((jsonrpc . "2.0") (id . ,id) (result . ,result))))

(defun familiar-a2a--rpc-error (id code message)
  (familiar-a2a--json `((jsonrpc . "2.0") (id . ,(or id :null)) (error . ((code . ,code) (message . ,message))))))

(defun familiar-a2a-handle (method path headers body)
  "Route handler for /a2a and the agent card (see `familiar-mcp-http-routes')."
  (let ((path (car (split-string path "?")))
        (json '(("Content-Type" . "application/json"))))
    (cond
     ((and (equal method "GET") (equal path familiar-a2a-card-path))
      (list 200 json (familiar-a2a--json (familiar-a2a-card))))
     ((not (and (equal method "POST") (equal path "/a2a")))
      (list 404 nil "Not found"))
     ((let ((v (alist-get "a2a-version" headers nil nil #'equal)))
        (and v (not (string-empty-p v)) (not (member v '("1.0" "1")))))
      (list 200 json (familiar-a2a--rpc-error nil -32009 "Version not supported; this agent speaks 1.0")))
     (t
      (let* ((req (ignore-errors (json-parse-string body :object-type 'alist :array-type 'list
                                                    :null-object nil :false-object nil)))
             (id (alist-get 'id req))
             (params (alist-get 'params req)))
        (if (not (consp req))
            (list 200 json (familiar-a2a--rpc-error nil -32700 "Parse error"))
          (pcase (alist-get 'method req)
            ("SendMessage"
             (let ((message (alist-get 'message params)))
               (if (not message)
                   (list 200 json (familiar-a2a--rpc-error id -32602 "params.message is required"))
                 (if (alist-get 'returnImmediately (alist-get 'configuration params))
                     (list 200 json (familiar-a2a--rpc id `((task . ,(familiar-a2a--start message nil #'ignore)))))
                   (list :async
                         (lambda (respond)
                           (familiar-a2a--start
                            message nil
                            (lambda (task)
                              (funcall respond 200 json (familiar-a2a--rpc id `((task . ,task))))))))))))
            ("SendStreamingMessage"
             (let ((message (alist-get 'message params)))
               (list :sse
                     (lambda (send close)
                       (let* (task-id context
                              (task (familiar-a2a--start
                                     message
                                     (lambda (chunk)
                                       (funcall send (familiar-a2a--rpc
                                                      id `((artifactUpdate
                                                            . ((taskId . ,task-id) (contextId . ,context)
                                                               (append . t) (lastChunk . :false)
                                                               (artifact . ((artifactId . ,(concat task-id "-answer"))
                                                                            (name . "answer")
                                                                            (parts . [((text . ,chunk))])))))))))
                                     (lambda (final)
                                       (funcall send (familiar-a2a--rpc
                                                      id `((statusUpdate
                                                            . ((taskId . ,task-id) (contextId . ,context)
                                                               (status . ,(alist-get 'status final)))))))
                                       (funcall close)))))
                         (setq task-id (alist-get 'id task) context (alist-get 'contextId task))
                         (funcall send (familiar-a2a--rpc id `((task . ,task)))))))))
            ("GetTask"
             (if-let* ((task (familiar-a2a--task (alist-get 'id params))))
                 (list 200 json (familiar-a2a--rpc id task))
               (list 200 json (familiar-a2a--rpc-error id -32001 "Task not found"))))
            ("CancelTask"
             (let* ((tid (alist-get 'id params))
                    (entry (gethash tid familiar-a2a--tasks)))
               (cond ((not entry) (list 200 json (familiar-a2a--rpc-error id -32001 "Task not found")))
                     ((familiar-a2a--terminal-p (alist-get 'state (alist-get 'status (plist-get entry :task))))
                      (list 200 json (familiar-a2a--rpc-error id -32002 "Task is no longer cancelable")))
                     (t (when (buffer-live-p (plist-get entry :buffer))
                          (ignore-errors (gptel-abort (plist-get entry :buffer))))
                        (list 200 json (familiar-a2a--rpc id (familiar-a2a--set-state tid "TASK_STATE_CANCELED")))))))
            ("ListTasks"
             (let (tasks)
               (maphash (lambda (_ e) (push (plist-get e :task) tasks)) familiar-a2a--tasks)
               (list 200 json (familiar-a2a--rpc id `((tasks . ,(vconcat tasks)) (nextPageToken . "")
                                                      (pageSize . ,(length tasks)) (totalSize . ,(length tasks)))))))
            (_ (list 200 json (familiar-a2a--rpc-error
                               id -32004 (format "Unsupported operation: %s" (alist-get 'method req))))))))))))

(setf (alist-get "/a2a" familiar-mcp-http-routes nil nil #'equal) #'familiar-a2a-handle)
(setf (alist-get familiar-a2a-card-path familiar-mcp-http-routes nil nil #'equal) #'familiar-a2a-handle)
(add-to-list 'familiar-mcp-http-public-paths familiar-a2a-card-path)

;;;; Client

(defun familiar-a2a--token (spec)
  (let ((token (plist-get spec :token)))
    (if (functionp token) (funcall token) token)))

(defun familiar-a2a--http (url method body token callback)
  "Request URL with METHOD (and JSON BODY), bearer TOKEN; CALLBACK gets the
parsed JSON or (:error MESSAGE)."
  (let ((url-request-method method)
        (url-request-extra-headers
         (append '(("Content-Type" . "application/json") ("A2A-Version" . "1.0"))
                 (and token `(("Authorization" . ,(concat "Bearer " token))))))
        (url-request-data (and body (encode-coding-string body 'utf-8))))
    (url-retrieve
     url
     (lambda (status)
       (let ((result
              (if-let* ((err (plist-get status :error)))
                  (list :error (format "%S" err))
                (goto-char url-http-end-of-headers)
                (or (ignore-errors (json-parse-buffer :object-type 'alist :array-type 'list
                                                      :null-object nil :false-object nil))
                    (list :error "unreadable answer")))))
         (kill-buffer (current-buffer))
         (funcall callback result)))
     nil t t)))

(defun familiar-a2a-send (name text callback)
  "Send TEXT to the remote agent NAME (`familiar-a2a-agents'); CALLBACK gets
its answer as text."
  (let* ((spec (or (cdr (assoc name familiar-a2a-agents)) (user-error "No A2A agent %s" name)))
         (base (string-remove-suffix "/" (plist-get spec :url)))
         (card-url (if (string-suffix-p ".json" base) base (concat base familiar-a2a-card-path)))
         (token (familiar-a2a--token spec)))
    (familiar-a2a--http
     card-url "GET" nil nil
     (lambda (card)
       (let ((endpoint (alist-get 'url (seq-find (lambda (i) (equal (alist-get 'protocolBinding i) "JSONRPC"))
                                                 (alist-get 'supportedInterfaces card)))))
         (if (or (eq (car-safe card) :error) (not endpoint))
             (funcall callback (format "Error: no JSON-RPC interface on %s's card" name))
           (familiar-a2a--http
            endpoint "POST"
            (familiar-a2a--json
             `((jsonrpc . "2.0") (id . 1) (method . "SendMessage")
               (params . ((message . ((messageId . ,(familiar-a2a--id "msg")) (role . "ROLE_USER")
                                      (parts . [((text . ,text))])))))))
            token
            (lambda (resp)
              (funcall callback
                       (cond ((eq (car-safe resp) :error) (format "Error: %s" (cadr resp)))
                             ((alist-get 'error resp)
                              (format "Error: %s" (alist-get 'message (alist-get 'error resp))))
                             (t (let* ((result (alist-get 'result resp))
                                       (task (alist-get 'task result))
                                       (message (alist-get 'message result)))
                                  (cond (message (familiar-a2a--text message))
                                        (task (mapconcat (lambda (a) (familiar-a2a--text a))
                                                         (alist-get 'artifacts task) "\n"))
                                        (t "(no answer)"))))))))))))))

(defun familiar-a2a-keywords ()
  "@NAME keywords for `familiar-a2a-agents'."
  (mapcar (lambda (a) (cons (car a) (format "delegate to the %s A2A agent" (car a))))
          familiar-a2a-agents))

(defun familiar-a2a-turn-tools (keywords _origin)
  "A delegating tool per remote agent named in KEYWORDS."
  (cl-loop for (name . _) in familiar-a2a-agents
           when (memq (intern name) keywords)
           collect (let ((name name))
                     (gptel-make-tool
                      :name (format "ask_agent_%s" (replace-regexp-in-string "[^[:alnum:]_]" "_" name))
                      :category "a2a" :async t
                      :description (format "Hand a request to the %s agent (A2A) and get its answer." name)
                      :args '((:name "request" :type string :description "What the agent should do or answer"))
                      :function (lambda (callback request)
                                  (familiar-a2a-send name request
                                                     (lambda (answer) (funcall callback answer))))))))

;; Both hooks default to nil: adding before familiar-ask loads is safe.
(defvar familiar-ask-keyword-functions)
(defvar familiar-ask-turn-tools-functions)
(add-hook 'familiar-ask-keyword-functions #'familiar-a2a-keywords)
(add-hook 'familiar-ask-turn-tools-functions #'familiar-a2a-turn-tools)

(provide 'familiar-a2a)
;;; familiar-a2a.el ends here
