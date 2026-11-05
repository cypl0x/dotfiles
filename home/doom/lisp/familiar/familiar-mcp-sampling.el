;;; familiar-mcp-sampling.el --- MCP servers ask, familiar answers (sampling) -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; MCP's sampling: a server (an agent, a summarizer) asks its client for a
;; model's completion, `sampling/createMessage', instead of holding an API
;; key itself.  With this, the servers familiar starts (familiar-mcp-client,
;; @name in M-ß) get one from familiar: on familiar's models, within its
;; budget, priced in its ledger (task `mcp-sampling'), and asking you first.
;;
;; The blocker was mcp.el, through jsonrpc.el: a server's request is
;; answered with whatever the dispatcher returns, from inside the process
;; filter, so a completion (seconds, and a question to you) would have
;; frozen Emacs.  Here the reply is deferred instead:
;;
;;   1. while a request is dispatched, its id is known (an advice on
;;      `jsonrpc-connection-receive' binds it);
;;   2. for sampling, the dispatcher marks (connection . id) deferred and
;;      returns at once; jsonrpc's automatic reply for a marked id is
;;      dropped (an advice on `jsonrpc--reply');
;;   3. outside the filter (a timer) familiar asks you, runs the request
;;      asynchronously, and sends the reply under that id itself.
;;
;; The client says it can sample (capabilities: sampling) when it starts
;; a server.  The model follows the server's preferences: a hint naming a
;; model family (haiku, sonnet, opus) picks that tier, else intelligence
;; over speed picks smart, else fast.
;;
;;   `familiar-mcp-sampling'  ask (default), always, or never
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function familiar-request "familiar" (prompt &rest args))
(declare-function jsonrpc--reply "jsonrpc" (connection id method &rest args))
(defvar familiar-models)
(defvar gptel-max-tokens)
(defvar mcp-server-connections)

(defgroup familiar-mcp-sampling nil
  "Completions for MCP servers that ask for them."
  :group 'familiar)

(defcustom familiar-mcp-sampling 'ask
  "Whether MCP servers get completions.
`ask' each time (a server can be allowed for the session), `always', or
`never'."
  :type '(choice (const ask) (const always) (const never)))

(defcustom familiar-mcp-sampling-max-tokens 2000
  "The most output tokens a server's request may have, whatever it asks."
  :type 'natnum)

(defvar familiar-mcp-sampling--allowed nil "Servers allowed for this session.")
(defvar familiar-mcp-sampling--deferred nil "(CONNECTION . ID) whose reply comes later.")
(defvar familiar-mcp-sampling--incoming nil "The id of the server request being dispatched.")

;;;; Deferring jsonrpc's reply

(defun familiar-mcp-sampling--receive-a (fn conn message)
  "Around `jsonrpc-connection-receive': the request's id, for the dispatcher.
FN receives MESSAGE on CONN with the id bound."
  (let ((familiar-mcp-sampling--incoming (plist-get message :id)))
    (funcall fn conn message)))

(defun familiar-mcp-sampling--reply-a (fn conn id &rest args)
  "Around `jsonrpc--reply': drop the automatic reply of a deferred request.
FN replies to request ID on CONN with ARGS, unless that is deferred."
  (unless (member (cons conn id) familiar-mcp-sampling--deferred)
    (apply fn conn id args)))

(defun familiar-mcp-sampling--send (conn id &rest result-or-error)
  "Reply to CONN's request ID now.
RESULT-OR-ERROR is :result R or :error E."
  (setq familiar-mcp-sampling--deferred (delete (cons conn id) familiar-mcp-sampling--deferred))
  (apply #'jsonrpc--reply conn id "sampling/createMessage" result-or-error))

;;;; The request

(defun familiar-mcp-sampling--text (content)
  "The text of an MCP CONTENT object (non-text parts named, not sent)."
  (pcase (plist-get content :type)
    ("text" (plist-get content :text))
    (type (format "[%s content not shown]" type))))

(defun familiar-mcp-sampling--prompt (messages)
  "MESSAGES (MCP's) as gptel's conversation.
Alternating user and assistant strings, starting with the user's
\(consecutive turns of one role joined)."
  (let (turns role)
    (seq-doseq (m messages)
      (let ((r (plist-get m :role)) (text (familiar-mcp-sampling--text (plist-get m :content))))
        (if (and turns (equal r role))
            (setcar turns (concat (car turns) "\n\n" text))
          (when (and (null turns) (equal r "assistant")) (push "" turns))
          (push text turns)
          (setq role r))))
    (let ((out (nreverse turns)))
      (if (cdr out) out (car out)))))

(defun familiar-mcp-sampling--model (prefs)
  "A model of `familiar-models' for MCP's modelPreferences PREFS."
  (let* ((hints (mapcar (lambda (h) (downcase (or (plist-get h :name) ""))) (plist-get prefs :hints)))
         (by-hint (cl-some (lambda (h)
                             (cl-some (lambda (tm) (and (string-match-p (regexp-quote h) (symbol-name (cdr tm)))
                                                        (cdr tm)))
                                      familiar-models))
                           (seq-remove #'string-empty-p hints)))
         (smart (> (or (plist-get prefs :intelligencePriority) 0)
                   (max 0.6 (or (plist-get prefs :speedPriority) 0)))))
    (or by-hint (alist-get (if smart 'smart 'fast) familiar-models) (cdar familiar-models))))

(defun familiar-mcp-sampling--allowed-p (server params)
  "Whether SERVER may have the completion PARAMS asks for (may ask you)."
  (pcase familiar-mcp-sampling
    ('never nil)
    ('always t)
    (_ (or (member server familiar-mcp-sampling--allowed)
           (let* ((first (familiar-mcp-sampling--text
                          (plist-get (aref (vconcat (plist-get params :messages)) 0) :content)))
                  (answer (read-char-choice
                           (format "MCP server %s asks for a completion: %s\n  y yes, a always for %s this session, n no: "
                                   server (truncate-string-to-width (replace-regexp-in-string "\n" " " first) 70 nil nil "…")
                                   server)
                           '(?y ?a ?n))))
             (when (eq answer ?a) (push server familiar-mcp-sampling--allowed))
             (memq answer '(?y ?a)))))))

(defun familiar-mcp-sampling--answer (server conn id params)
  "Answer SERVER's sampling request ID on CONN: ask, request, reply."
  (condition-case err
      (if (not (familiar-mcp-sampling--allowed-p server params))
          (familiar-mcp-sampling--send conn id :error '(:code -1 :message "User rejected sampling request"))
        (let ((model (familiar-mcp-sampling--model (plist-get params :modelPreferences)))
              (gptel-max-tokens (min familiar-mcp-sampling-max-tokens
                                     (or (plist-get params :maxTokens) familiar-mcp-sampling-max-tokens))))
          (familiar-request
           (familiar-mcp-sampling--prompt (plist-get params :messages))
           :task 'mcp-sampling :model model :silent t
           :system (plist-get params :systemPrompt)
           :callback
           (lambda (response info)
             (cond ((stringp response)
                    (familiar-mcp-sampling--send
                     conn id :result
                     (list :role "assistant" :content (list :type "text" :text response)
                           :model (format "%s" model)
                           :stopReason (pcase (plist-get info :stop-reason)
                                         ((or "max_tokens" "length") "maxTokens")
                                         (_ "endTurn")))))
                   ((null response)
                    (familiar-mcp-sampling--send
                     conn id :error (list :code -32603
                                          :message (format "familiar: %s" (or (plist-get info :status) "no answer"))))))))))
    (error (familiar-mcp-sampling--send conn id :error
                                        (list :code -32603 :message (error-message-string err))))))

(defun familiar-mcp-sampling--dispatch-a (fn name method params)
  "Around `mcp-request-dispatcher': sampling is answered later, by familiar.
FN handles METHOD with PARAMS from server NAME otherwise."
  (if (and (eq method 'sampling/createMessage) familiar-mcp-sampling--incoming)
      (let ((conn (gethash name mcp-server-connections)) (id familiar-mcp-sampling--incoming))
        (push (cons conn id) familiar-mcp-sampling--deferred)
        ;; Out of the process filter: the question and the request.
        (run-at-time 0 nil #'familiar-mcp-sampling--answer name conn id params)
        nil)
    (funcall fn name method params)))

;;;; Saying we can

(defun familiar-mcp-sampling--initialize-a (args)
  "Filter jsonrpc's request ARGS: mcp.el's initialize also announces sampling."
  (pcase args
    (`(,conn :initialize ,params . ,rest)
     (let ((caps (plist-get params :capabilities)))
       (if (or (plist-member caps :sampling) (eq familiar-mcp-sampling 'never))
           args
         `(,conn :initialize
                 ,(plist-put (copy-sequence params) :capabilities
                             (append caps (list :sampling (make-hash-table))))
                 ,@rest))))
    (_ args)))

;;;###autoload
(define-minor-mode familiar-mcp-sampling-mode
  "Answer MCP servers' sampling requests through familiar (see the file)."
  :global t
  (let ((pairs '((jsonrpc-connection-receive :around familiar-mcp-sampling--receive-a)
                 (jsonrpc--reply :around familiar-mcp-sampling--reply-a)
                 (mcp-request-dispatcher :around familiar-mcp-sampling--dispatch-a)
                 (jsonrpc-async-request :filter-args familiar-mcp-sampling--initialize-a)
                 (jsonrpc-request :filter-args familiar-mcp-sampling--initialize-a))))
    (pcase-dolist (`(,fn ,how ,advice) pairs)
      (if familiar-mcp-sampling-mode
          (advice-add fn how advice)
        (advice-remove fn advice)))))

(provide 'familiar-mcp-sampling)
;;; familiar-mcp-sampling.el ends here
