;;; familiar-openai.el --- An OpenAI-compatible endpoint, answered by familiar -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; Anything that speaks the OpenAI chat API (llm, aichat, shell tools,
;; editors) can use Emacs as its model provider:
;;
;;   OPENAI_BASE_URL=http://127.0.0.1:39391/v1
;;   OPENAI_API_KEY=$(cat ~/.local/state/emacs/familiar-mcp-http-token)
;;
;; Requests go through familiar: its backend and key, the tier's model,
;; priced into the ledger and counted against the budget like everything
;; else (task `openai').  Served by familiar-mcp-http's server: localhost
;; only, same token.
;;
;; Models (GET /v1/models):
;;   fast, smart, deep              familiar's tiers (`familiar-models')
;;   emacs-fast, emacs-smart, …     the same, told where you are in Emacs:
;;                                  buffer, mode, point, region, the text
;;                                  around it (familiar-ask's context)
;;   a model id of a tier           that model (e.g. claude-haiku-5-5)
;;
;; POST /v1/chat/completions answers with one object, or with "stream":
;; true as server-sent chunks ending in [DONE].
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'familiar-mcp-http)

(declare-function familiar-ask--capture "familiar-ask" ())
(declare-function familiar-ask--context "familiar-ask" (origin))

(defvar familiar-openai-default-tier 'fast
  "Tier for a request naming no known model.")

(defun familiar-openai--json (object)
  "OBJECT (an alist) as a JSON string."
  (json-serialize object :null-object :null :false-object :false))

(defun familiar-openai--error (status message &optional type)
  "An OpenAI-style error response with STATUS, MESSAGE and error TYPE."
  (list status '(("Content-Type" . "application/json"))
        (familiar-openai--json `((error . ((message . ,message)
                                           (type . ,(or type "invalid_request_error"))))))))

(defun familiar-openai-models ()
  "Model ids served: tiers, the same with Emacs context, the tiers' models."
  (append (mapcar (lambda (tier) (symbol-name (car tier))) familiar-models)
          (mapcar (lambda (tier) (format "emacs-%s" (car tier))) familiar-models)
          (mapcar (lambda (tier) (format "%s" (cdr tier))) familiar-models)))

(defun familiar-openai--resolve (model)
  "MODEL (a string) as (TIER . WITH-CONTEXT)."
  (let* ((context (and model (string-prefix-p "emacs-" model)))
         (name (if context (string-remove-prefix "emacs-" model) model))
         (tier (or (car (seq-find (lambda (tier) (equal name (symbol-name (car tier)))) familiar-models))
                   (car (seq-find (lambda (tier) (equal name (format "%s" (cdr tier)))) familiar-models))
                   familiar-openai-default-tier)))
    (cons tier context)))

(defun familiar-openai--content (content)
  "A message's CONTENT as text: a string, or the text parts of a list."
  (cond ((stringp content) content)
        ((listp content)
         (mapconcat (lambda (part) (or (alist-get 'text part) "")) content "\n"))
        (t "")))

(defun familiar-openai-conversation (messages)
  "Split OpenAI MESSAGES into a system prompt and a list prompt.
The result is (SYSTEM . TURNS).  TURNS alternate from the user, as
`gptel-request' takes a list prompt; consecutive turns of one role merge."
  (let (system turns last)
    (dolist (m messages)
      (let ((role (alist-get 'role m))
            (text (familiar-openai--content (alist-get 'content m))))
        (pcase role
          ((or "system" "developer") (push text system))
          (_ (let ((side (if (equal role "assistant") 'llm 'user)))
               (cond ((and (null turns) (eq side 'llm)) (push "" turns) (push text turns))
                     ((eq side last) (setcar turns (concat (car turns) "\n\n" text)))
                     (t (push text turns)))
               (setq last side))))))
    (cons (and system (string-join (nreverse system) "\n\n"))
          (nreverse turns))))

(defun familiar-openai--emacs-context ()
  "Where the user is in Emacs, as familiar-ask would tell a model."
  (require 'familiar-ask)
  (with-selected-window (frame-selected-window (selected-frame))
    (familiar-ask--context (familiar-ask--capture))))

(defun familiar-openai--chunk (id model created delta &optional finish)
  "A streamed chunk of completion ID: DELTA, and FINISH as its finish reason.
MODEL and CREATED are the completion's."
  (familiar-openai--json
   `((id . ,id) (object . "chat.completion.chunk") (created . ,created) (model . ,model)
     (choices . [((index . 0) (delta . ,delta) (finish_reason . ,(or finish :null)))]))))

(defun familiar-openai--completion (id model created text tokens)
  "Completion ID of TEXT by MODEL, made at CREATED, its usage from TOKENS."
  (let ((in (or (plist-get tokens :input) 0)) (out (or (plist-get tokens :output) 0)))
    (familiar-openai--json
     `((id . ,id) (object . "chat.completion") (created . ,created) (model . ,model)
       (choices . [((index . 0) (message . ((role . "assistant") (content . ,text)))
                    (finish_reason . "stop"))])
       (usage . ((prompt_tokens . ,in) (completion_tokens . ,out) (total_tokens . ,(+ in out))))))))

(defun familiar-openai-handle (method path _headers body)
  "Route handler for /v1/ (see `familiar-mcp-http-routes').
METHOD, PATH and BODY are the request's."
  (pcase (cons method (car (split-string path "?")))
    (`("GET" . "/v1/models")
     (list 200 '(("Content-Type" . "application/json"))
           (familiar-openai--json
            `((object . "list")
              (data . ,(vconcat (mapcar (lambda (id) `((id . ,id) (object . "model") (created . 0)
                                                     (owned_by . "familiar")))
                                        (familiar-openai-models))))))))
    (`("POST" . "/v1/chat/completions")
     (let ((req (ignore-errors (json-parse-string body :object-type 'alist :array-type 'list
                                                  :null-object nil :false-object nil))))
       (if (not (and req (alist-get 'messages req)))
           (familiar-openai--error 400 "Expected a JSON body with messages")
         (familiar-openai--chat req))))
    (_ (familiar-openai--error 404 (format "No %s %s here" method path) "not_found"))))

(defun familiar-openai--chat (req)
  "Answer chat completion request REQ, streamed if it asks."
  (pcase-let* ((`(,tier . ,context) (familiar-openai--resolve (alist-get 'model req)))
               (`(,system . ,turns) (familiar-openai-conversation (alist-get 'messages req)))
               (system (string-join (delq nil (list system
                                                    (and context
                                                         (concat "Where the user is in Emacs right now:\n"
                                                                 (familiar-openai--emacs-context)))))
                                    "\n\n"))
               (tiers (cons (cons 'openai tier) familiar-task-tiers))
               (model (format "%s" (let ((familiar-task-tiers tiers)) (familiar--model 'openai))))
               (id (format "chatcmpl-%x" (random most-positive-fixnum)))
               (created (truncate (float-time))))
    (if (alist-get 'stream req)
        (list :sse
              (lambda (send close)
                (funcall send (familiar-openai--chunk id model created '((role . "assistant"))))
                (let ((familiar-task-tiers tiers)) (familiar-request turns :task 'openai :system (unless (string-empty-p system) system)
                                  :stream t
                                  :callback
                                  (lambda (response _info)
                                    (cond ((stringp response)
                                           (funcall send (familiar-openai--chunk id model created
                                                                                 `((content . ,response)))))
                                          (t
                                           (funcall send (familiar-openai--chunk id model created
                                                                                 (make-hash-table) "stop"))
                                           (funcall send "[DONE]")
                                           (funcall close))))))))
      (list :async
            (lambda (respond)
              (let ((familiar-task-tiers tiers)) (familiar-request turns :task 'openai :system (unless (string-empty-p system) system)
                                :callback
                                (lambda (response info)
                                  (if (stringp response)
                                      (funcall respond 200 '(("Content-Type" . "application/json"))
                                               (familiar-openai--completion id model created response
                                                                            (plist-get info :tokens)))
                                    (apply respond (familiar-openai--error
                                                    502 (format "The model gave no answer: %s"
                                                                (or (plist-get info :status) "unknown"))
                                                    "api_error")))))))))))

(setf (alist-get "/v1/" familiar-mcp-http-routes nil nil #'equal) #'familiar-openai-handle)

(provide 'familiar-openai)
;;; familiar-openai.el ends here
