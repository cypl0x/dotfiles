;;; familiar-ask.el --- Ask anything, from anywhere in Emacs -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; One key (M-ß by default) from any buffer, including the minibuffer and
;; buffers that visit no file, asks a long-lived conversation.  What you were
;; looking at goes along as context, so you never restate it; tools let the
;; model look around Emacs itself and act in it, the way you would (edits are
;; undoable, nothing is written to disk unless you ask for it).
;;
;;   M-ß              ask, in a fresh conversation (in the minibuffer too:
;;                    "exclude tests" in M-x)
;;   @follow-up        in the prompt: continue the last conversation instead
;;                    (also SPC u M-ß; `familiar-ask-follow-up' flips the default)
;;   @echo             in the prompt: a short answer in the echo area, no window
;;   C-SPC  (prompt)  complete @keywords, @presets and words
;;   C-M-ß            write the prompt in a buffer right away (multi-line)
;;   C-c '  (prompt)  edit the prompt in a buffer; C-c C-c sends, C-c C-k keeps it
;;   @fast/@smart/@deep in the prompt picks the model (gptel presets)
;;   @model[:NAME]    who answers this turn: any gptel model, or a running agent
;;                    (agent-shell, claude-code) that gets the prompt and context
;;   @inline          write the answer into the buffer: at point, after the region,
;;                    or on a new line (evil normal state); one undo takes it back
;;   @replace         write it in place of the region
;;   @transient       after RET, a transient: where the answer goes, which
;;                    conversation, who answers; then send or edit
;;   C-r  (prompt)    pick an earlier prompt
;;   C-c C-c          in the conversation: send the follow-up (from anywhere)
;;   RET / S-RET      at its end: send a follow-up / newline
;;   C-c C-e          copy the conversation as Markdown or Org
;;   C-c ! / C-c $    apply a suggestion from the latest answer (command, keys,
;;                    elisp block, shell command at the prompt) / the first one
;;   familiar-ask-sessions   reopen an earlier conversation
;;
;; Built on gptel's chat buffers: streaming, tool calls shown as folded
;; #+begin_tool blocks, prompt caching, saved and restorable conversations.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gptel)
(require 'familiar)
(require 'org)

(declare-function familiar-history-record "familiar-history" (&rest args))
(declare-function vertico--exhibit "ext:vertico" ())
(declare-function evil-insert-state "ext:evil-states" (&optional arg))
(defvar vertico--candidates)
(defvar vertico-mode)
(defvar evil-state)
(defvar savehist-additional-variables)

;;;; Customization

(defcustom familiar-ask-tier 'smart
  "Tier from `familiar-models' answering `familiar-ask'."
  :type 'symbol :group 'familiar)

(defcustom familiar-ask-directory (locate-user-emacs-file "familiar-ask/")
  "Where conversations are saved, one Org file each."
  :type 'directory :group 'familiar)

(defcustom familiar-ask-auto-scroll nil
  "Whether the conversation window follows the answer as it streams."
  :type 'boolean :group 'familiar)

(defcustom familiar-ask-follow-up nil
  "Whether `familiar-ask' continues the running conversation.
nil: each ask starts a fresh one, so earlier turns and the context they
carried aren't sent (and paid for) again; @follow-up in the prompt, or
the prefix arg, continues it.  t: continue, unless @new or the prefix
arg.  RET at the end of an answer always follows up."
  :type 'boolean :group 'familiar)

(defvar familiar-ask-keywords
  '(("follow-up" . "continue the running conversation")
    ("new" . "start a fresh conversation")
    ("echo" . "short answer in the echo area, no window")
    ("model" . "pick who answers: any gptel model, or a running agent (@model:NAME)")
    ("inline" . "write the answer into the buffer, at point or after the region")
    ("replace" . "write the answer in place of the region")
    ("transient" . "choose where, which conversation and who answers before sending"))
  "Words a prompt may contain as @WORD; taken out before it is sent.
Next to gptel's presets (@fast, @smart, @deep), which gptel applies.")

(defvar familiar-ask-keyword-functions nil
  "Functions returning more keywords, as `familiar-ask-keywords' does.
Called in the buffer asked from (e.g. MCP servers known for its project).")

(defvar familiar-ask-turn-tools-functions nil
  "Functions called with a turn's keywords (symbols) and its origin plist,
each returning gptel tools offered on that turn besides `familiar-ask-tools'.")

(defvar familiar-ask-prompt-capfs nil
  "Completion functions in the prompt, after @keyword completion.")

(defvar familiar-ask-prompt-setup-hook nil
  "Run in the minibuffer reading a prompt (e.g. to turn on corfu).")

(defcustom familiar-ask-confirm-tools 'auto
  "Whether tool calls wait for your approval: t, nil (never), or auto.
auto asks for eval_elisp and replace_in_buffer only.  nil lets the model run
any elisp unasked, so text it reads (a web page, a mail) could steer it."
  :type '(choice (const :tag "Tool decides" auto) (const :tag "Always" t)
                 (const :tag "Never" nil))
  :group 'familiar)

(defcustom familiar-ask-context-functions nil
  "Functions adding context, called without arguments in the buffer asked from.
Each returns nil or a plist (:title STRING :text STRING [:lang MODE] [:primary
BOOL]).  A :primary part replaces the default text around point: use it
where the buffer text isn't what the user sees (a PDF, an image, a terminal).
Say in :title what \"this\" refers to when it's a selection."
  :type 'hook :group 'familiar)

(defcustom familiar-ask-context-lines 30
  "Lines around point sent along when there is no region or defun."
  :type 'natnum :group 'familiar)

(defcustom familiar-ask-system
  "You are familiar, an assistant living inside the user's Emacs (Doom Emacs \
with evil, vertico and orderless; Emacs 32).  Each user message ends with a \
#+begin_context block describing where they were when they asked: buffer, \
modes, point, region, nearby text, minibuffer.  Treat it as the subject of \
the question; the user won't restate it.  When a part is marked as what \
\"this\" refers to (a region, a selection in a PDF), the question is about \
that: explain the thing itself in general terms first, then how the \
surrounding text uses it.  Your tools inspect Emacs and act \
in it; use them instead of guessing.  Prefer the read-only ones (describe, \
buffer_text, list_buffers, apropos): they run at once, while eval_elisp and \
replace_in_buffer wait for the user to approve each call.

Decide from the wording.  A question (\"how do I\", \"what is\", \"explain\", \
\"when to use\") gets an answer: suggest commands, key bindings or elisp, \
several variants when they differ, and change nothing.  An instruction \
(\"do\", \"convert\", \"rename\", \"make this …\", \"exclude …\") gets done \
with the tools: edit buffers in place so it is undoable, never write files \
unless asked, then say in one line what you did.  When the context shows an \
active minibuffer and the user wants its input changed, use \
set_minibuffer.

In a shell or terminal buffer (eshell, shell, a terminal emulator) the text \
above point is the user's latest commands and their output, exit codes \
included when the prompt shows them: \"my last command\" means that.  When \
they want a command, put it at their prompt with insert_at_prompt (never run \
it) and explain it in a line.

Reply in Markdown (gptel converts it to Org for this buffer): `code` inline, \
``` fences with the language for blocks.  Lead with the answer; be brief."
  "System prompt for `familiar-ask'."
  :type 'string :group 'familiar)

;;;; State

(defvar familiar-ask-history nil
  "Prompts given to `familiar-ask', newest first.")

(defvar familiar-ask--origin nil
  "Plist describing where the pending prompt was asked from.")

(defvar familiar-ask--draft nil
  "A prompt edited in a buffer and then kept with C-c C-k.")

(defvar familiar-ask--buffer-name "*familiar-ask*")

(defvar-local familiar-ask--cost 0.0 "Spent in this conversation, in USD.")

;;;; Context

(defun familiar-ask--capture ()
  "Describe the current situation as a plist (taken before prompting)."
  (let* ((mini (minibufferp))
         ;; From the minibuffer, the buffer the user was working in.
         (buf (if mini (window-buffer (minibuffer-selected-window)) (current-buffer))))
    (list :minibuffer (and mini (current-buffer))
          :buffer buf
          ;; Answers open from here, not from the minibuffer window.
          :window (if mini (minibuffer-selected-window) (selected-window))
          :point (with-current-buffer buf (point))
          :region (with-current-buffer buf
                    (and (use-region-p) (cons (region-beginning) (region-end)))))))

(defun familiar-ask--minibuffer-context (mb)
  "Context lines for the active minibuffer MB."
  (with-current-buffer mb
    (concat
     (format "Active minibuffer: prompt %S, input %S, command %s\n"
             (minibuffer-prompt) (minibuffer-contents-no-properties)
             current-minibuffer-command)
     (format "Completion styles: %S\n" completion-styles)
     (when (and (bound-and-true-p vertico-mode) (boundp 'vertico--candidates)
                vertico--candidates)
       (format "First candidates: %s\n"
               (string-join (seq-take vertico--candidates 15) ", "))))))

(defun familiar-ask--context (origin)
  "Org text describing ORIGIN, as captured by `familiar-ask--capture'."
  (let ((buf (plist-get origin :buffer)))
    (with-current-buffer buf
      (save-excursion
        (goto-char (plist-get origin :point))
        (let* ((region (plist-get origin :region))
               (bounds (or region
                           (ignore-errors
                             (and (derived-mode-p 'prog-mode)
                                  (bounds-of-thing-at-point 'defun)))
                           (cons (save-excursion (forward-line (- familiar-ask-context-lines)) (point))
                                 (save-excursion (forward-line familiar-ask-context-lines) (point)))))
               (lang (string-remove-suffix "-mode" (symbol-name major-mode))))
          (concat
           "#+begin_context\n"
           (format "Time: %s\n" (format-time-string "%F %a %R"))
           (format "Buffer: %s%s, %s\n" (buffer-name)
                   (if buffer-file-name (format " (file %s)" (abbreviate-file-name buffer-file-name))
                     " (visits no file)")
                   major-mode)
           (format "Minor modes: %s\n"
                   (string-join (mapcar #'symbol-name
                                        (seq-filter (lambda (m) (and (boundp m) (symbol-value m)))
                                                    (seq-take local-minor-modes 25)))
                                " "))
           (format "Point: line %d, column %d%s%s\n" (line-number-at-pos) (current-column)
                   (if (bound-and-true-p evil-state) (format ", evil %s state" evil-state) "")
                   (if-let* ((thing (thing-at-point 'symbol t))) (format ", on `%s'" thing) ""))
           (when-let* ((proj (familiar--project-name))) (format "Project: %s\n" proj))
           (when (derived-mode-p 'eshell-mode 'comint-mode 'ghostel-mode 'vterm-mode 'eat-mode)
             (format "Asked at a shell prompt (%s, directory %s): put any command at the prompt with insert_at_prompt, don't only show it\n"
                     major-mode (abbreviate-file-name default-directory)))
           (when-let* ((mb (plist-get origin :minibuffer)))
             (and (buffer-live-p mb) (familiar-ask--minibuffer-context mb)))
           (format "Other windows: %s\n"
                   (string-join (delete-dups
                                 (mapcar (lambda (w) (buffer-name (window-buffer w)))
                                         (window-list (selected-frame) 'nomini)))
                                ", "))
           (let ((parts (delq nil (mapcar #'funcall familiar-ask-context-functions))))
             (concat
              (mapconcat #'familiar-ask--context-part parts "")
              ;; A mode's own primary part (a PDF's selection, say) replaces
              ;; the buffer text, which there is only layout.
              (unless (seq-some (lambda (p) (plist-get p :primary)) parts)
                (familiar-ask--context-part
                 (list :title (format "%s, lines %d-%d"
                                      (if region "Region (what \"this\" refers to)" "Around point")
                                      (line-number-at-pos (car bounds))
                                      (line-number-at-pos (cdr bounds)))
                       :lang lang
                       :text (buffer-substring-no-properties (car bounds) (cdr bounds)))))))
           "#+end_context"))))))

(defun familiar-ask--context-part (part)
  "PART, a plist (:title :text [:lang]), as a titled src block."
  (format "%s:\n#+begin_src %s\n%s\n#+end_src\n"
          (plist-get part :title) (or (plist-get part :lang) "text")
          (string-trim-right (org-escape-code-in-string (plist-get part :text)))))

;;;; Tools

(defcustom familiar-ask-tool-result-max 6000
  "Longest tool result sent back to the model, in characters."
  :type 'natnum :group 'familiar)

(defun familiar-ask--cap (text)
  "TEXT, cut to `familiar-ask-tool-result-max' with a note saying so."
  (if (<= (length text) familiar-ask-tool-result-max) text
    (concat (substring text 0 familiar-ask-tool-result-max)
            (format "\n[… %d more characters cut; ask for less]"
                    (- (length text) familiar-ask-tool-result-max)))))

(defun familiar-ask--get-buffer (name)
  (or (get-buffer name) (error "No buffer named %s" name)))

(declare-function ghostel-paste-string "ext:ghostel" (string))
(declare-function comint-delete-input "comint" ())
(defvar eshell-last-output-end)

(defun familiar-ask-insert-at-prompt (text)
  "Put TEXT at the prompt (or point) of the buffer asked from; don't run it."
  (let* ((origin familiar-ask--origin)
         (buf (plist-get origin :buffer)))
    (unless (buffer-live-p buf) (error "The buffer asked from is gone"))
    (with-current-buffer buf
      (cond ((derived-mode-p 'ghostel-mode)
             ;; A bracketed paste: the shell edits it like typed input.
             (ghostel-paste-string text))
            ((derived-mode-p 'eshell-mode)
             (goto-char (point-max))
             (delete-region eshell-last-output-end (point-max))
             (insert text))
            ((derived-mode-p 'comint-mode)
             (goto-char (point-max))
             (comint-delete-input)
             (insert text))
            (t (save-excursion
                 (goto-char (plist-get origin :point))
                 (insert text)))))
    (format "Inserted into %s, not run" (buffer-name buf))))

(defvar familiar-ask-tools
  (list
   (gptel-make-tool
    :name "eval_elisp" :category "familiar"
    :description "Evaluate an Emacs Lisp expression in the user's Emacs and return the printed value. Use for introspection (variables, modes, keymaps, packages) and, when the user asks for an action, to perform it."
    :args '((:name "expression" :type string :description "One elisp form"))
    :function (lambda (expression)
                (let ((print-length 50) (print-level 6))
                  (format "%S" (eval (read expression) t))))
    :confirm t :include t)
   (gptel-make-tool
    :name "buffer_text" :category "familiar"
    :description "Text of an Emacs buffer (any buffer, file-visiting or not), optionally only lines START to END."
    :args '((:name "buffer" :type string :description "Buffer name")
            (:name "start" :type integer :description "First line (optional)" :optional t)
            (:name "end" :type integer :description "Last line (optional)" :optional t))
    :function (lambda (buffer &optional start end)
                (with-current-buffer (familiar-ask--get-buffer buffer)
                  (save-excursion
                    (save-restriction
                      (widen)
                      (let ((beg (if start (progn (goto-char (point-min)) (forward-line (1- start)) (point))
                                   (point-min)))
                            (fin (if end (progn (goto-char (point-min)) (forward-line end) (point))
                                   (point-max))))
                        (buffer-substring-no-properties beg (min fin (+ beg 40000))))))))
    :include t)
   (gptel-make-tool
    :name "list_buffers" :category "familiar"
    :description "All buffers: name, major mode, file, size."
    :args nil
    :function (lambda ()
                (mapconcat (lambda (b)
                             (with-current-buffer b
                               (format "%s\t%s\t%s\t%d" (buffer-name) major-mode
                                       (or buffer-file-name "-") (buffer-size))))
                           (seq-remove (lambda (b) (string-prefix-p " " (buffer-name b)))
                                       (buffer-list))
                           "\n"))
    :include t)
   (gptel-make-tool
    :name "describe" :category "familiar"
    :description "Documentation of an Emacs function, command or variable, its key bindings, and for variables the current value."
    :args '((:name "symbol" :type string :description "Symbol name"))
    :function (lambda (symbol)
                (let ((sym (intern-soft symbol)))
                  (unless sym (error "Unknown symbol %s" symbol))
                  (concat
                   (when (fboundp sym)
                     (format "Function %s%s:\n%s\n" sym
                             (if-let* ((keys (where-is-internal sym)))
                                 (format " (bound to %s)" (mapconcat #'key-description keys ", "))
                               "")
                             (or (documentation sym) "Undocumented")))
                   (when (boundp sym)
                     (let ((print-length 30) (print-level 4))
                       (format "Variable %s = %S\n%s\n" sym (symbol-value sym)
                               (or (documentation-property sym 'variable-documentation) "")))))))
    :include t)
   (gptel-make-tool
    :name "apropos" :category "familiar"
    :description "Commands, functions and variables whose names match a regexp (at most 60)."
    :args '((:name "pattern" :type string :description "Regexp"))
    :function (lambda (pattern)
                (let (out)
                  (mapatoms (lambda (s) (when (and (or (fboundp s) (boundp s))
                                                   (string-match-p pattern (symbol-name s)))
                                          (push (format "%s%s" s (if (commandp s) " (command)" "")) out))))
                  (string-join (seq-take (sort out #'string<) 60) "\n")))
    :include t)
   (gptel-make-tool
    :name "replace_in_buffer" :category "familiar"
    :description "Replace the exact text OLD with NEW in a buffer, as an undoable edit (works in buffers that visit no file). OLD must occur exactly once."
    :args '((:name "buffer" :type string :description "Buffer name")
            (:name "old" :type string :description "Exact text to replace")
            (:name "new" :type string :description "Replacement text"))
    :function (lambda (buffer old new)
                (with-current-buffer (familiar-ask--get-buffer buffer)
                  (save-excursion
                    (goto-char (point-min))
                    (let ((n (how-many (regexp-quote old) (point-min) (point-max))))
                      (unless (= n 1) (error "OLD occurs %d times, need exactly once" n)))
                    (search-forward old)
                    (replace-match new t t)
                    (format "Replaced in %s (undo with u / C-/ there)" buffer))))
    :confirm t)
   (gptel-make-tool
    :name "insert_at_prompt" :category "familiar"
    :description "Put TEXT (usually a shell command) where the user asked from, without running it, like Atuin's insert: at the prompt of a shell or terminal buffer (replacing what is typed there), else at point. Undoable."
    :args '((:name "text" :type string :description "Command or text to insert"))
    :function (lambda (text) (familiar-ask-insert-at-prompt text)))
   (gptel-make-tool
    :name "set_minibuffer" :category "familiar"
    :description "Replace the input of the minibuffer the user asked from (e.g. write orderless syntax into an M-x prompt). Only when the context shows an active minibuffer."
    :args '((:name "text" :type string :description "New minibuffer input"))
    :function (lambda (text)
                (let ((mb (plist-get familiar-ask--origin :minibuffer)))
                  (unless (and mb (buffer-live-p mb) (minibufferp mb))
                    (error "No minibuffer to write into"))
                  ;; It may have closed while the model thought (C-g, or RET).
                  (unless (minibufferp mb t)
                    (error "The minibuffer asked from is closed; nothing changed"))
                  (with-current-buffer mb
                    (delete-minibuffer-contents)
                    (insert text))
                  (when-let* ((win (get-buffer-window mb t)))
                    (with-selected-window win
                      (when (bound-and-true-p vertico-mode) (vertico--exhibit))))
                  (format "Minibuffer input is now %S" text)))))
  "Tools `familiar-ask' offers the model.")

;; Every result goes through `familiar-ask--cap': `describe' on a mode once
;; returned its whole keymap, hundreds of lines of tokens.
(dolist (tool familiar-ask-tools)
  (let ((fn (gptel-tool-function tool)))
    (setf (gptel-tool-function tool)
          (lambda (&rest args)
            (let ((result (apply fn args)))
              (if (stringp result) (familiar-ask--cap result) result))))))

;;;; The conversation buffer

(defvar familiar-ask-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'familiar-ask-ret)
    (define-key map (kbd "C-c C-c") #'familiar-ask-send-follow-up)
    (define-key map (kbd "<S-return>") #'newline)
    (define-key map (kbd "C-c C-k") #'gptel-abort)
    (define-key map (kbd "C-c C-e") #'familiar-ask-export)
    (define-key map (kbd "C-c !") #'familiar-ask-apply)
    (define-key map (kbd "C-c $") #'familiar-ask-apply-first)
    map)
  "Keymap of `familiar-ask-mode'.")

(define-minor-mode familiar-ask-mode
  "A `familiar-ask' conversation: RET at the end sends a follow-up."
  :lighter " ✦ask")

(defun familiar-ask--send-with-model (model)
  "`gptel-send' here, answered by MODEL (BACKEND . MODEL) if non-nil."
  (if model
      (let ((gptel-backend (car model))
            (gptel-model (cdr model)))
        (gptel-send))
    (gptel-send)))

(defun familiar-ask--send-here ()
  "Send the follow-up typed at the end of this conversation.
An @model in it picks who answers, as in the M-ß prompt."
  (let* ((spec (save-excursion
                 (goto-char (point-max))
                 (and (re-search-backward "^\\*\\* " nil t)
                      (re-search-forward "\\(?:^\\|[ \t]\\)@model\\(?::\\(\\S-+\\)\\)?\\(?:[ \t]\\|$\\)" nil t)
                      (prog1 (or (match-string 1) t)
                        (replace-match " ")))))
         (model (and spec (familiar-ask--resolve-model spec))))
    (goto-char (point-max))
    (if (eq (car model) 'agent)
        (let ((text (save-excursion
                      (re-search-backward "^\\*\\* " nil t)
                      (string-trim (buffer-substring-no-properties (+ (point) 3) (point-max))))))
          (familiar-ask--hand-off text (cdr model) familiar-ask--origin))
      (familiar-ask--send-with-model model))))

(defun familiar-ask-send-follow-up ()
  "Send the follow-up typed under the last prompt heading, from anywhere.
RET only sent with point at the very end, and evil's or Org's RET may
win over this mode's map; C-c C-c is free in both."
  (interactive)
  (goto-char (point-max))
  (skip-chars-backward " \t\n")
  (if (looking-back "^\\*+ *" (line-beginning-position))
      (user-error "Type the follow-up after the last ** first")
    (goto-char (point-max))
    (familiar-ask--send-here)))

(defun familiar-ask-ret ()
  "Send a follow-up when point is in the last, unanswered prompt; else newline."
  (interactive)
  (if (and (eobp) (not (looking-back "^\\*+ *\\|\\`\\s-*" (line-beginning-position))))
      (familiar-ask--send-here)
    (newline)))

(defvar-local familiar-ask--last-tokens nil "Tokens of the last answer.")
(defvar-local familiar-ask--last-cost nil "Cost of the last answer.")

(defvar-local familiar-ask--last-model nil
  "The model that answered last (an @preset may differ from `gptel-model').")

(defun familiar-ask--header-line ()
  "Model of the last answer, prompts, cost and start of this conversation."
  (format " ✦ familiar-ask  ·  %s  ·  %s  ·  $%.4f%s"
          (or familiar-ask--last-model gptel-model)
          (let ((n (how-many "^\\*\\* ." (point-min) (point-max))))
            (format "%d prompt%s" n (if (= n 1) "" "s")))
          familiar-ask--cost
          (if buffer-file-name
              (format-time-string "  ·  since %F %R"
                                  (date-to-time (replace-regexp-in-string
                                                 "\\`\\(....\\)\\(..\\)\\(..\\)-\\(..\\)\\(..\\)\\(..\\)\\'"
                                                 "\\1-\\2-\\3 \\4:\\5:\\6"
                                                 (file-name-base buffer-file-name))))
            "")))

(defun familiar-ask--setup (buf)
  "Make BUF a familiar-ask conversation."
  (with-current-buffer buf
    (unless (derived-mode-p 'org-mode) (org-mode))
    ;; The model's prose isn't yours to spell- or style-check.
    (dolist (mode '(jinx-mode flyspell-mode writegood-mode))
      (when (and (boundp mode) (symbol-value mode)) (funcall mode -1)))
    ;; The header line is ours (model, prompts, cost); gptel's status
    ;; ("Waiting…", "Ready") goes to the mode line instead.
    (setq-local gptel-use-header-line nil)
    ;; First: turning it on restores saved state, which would undo the below.
    ;; A fresh conversation has none to restore, and gptel said so on every
    ;; ask ("Could not activate gptel backend \"nil\"!"): skip it there.
    (if (save-excursion (goto-char (point-min)) (re-search-forward "^[ \t]*:GPTEL_" nil t))
        (gptel-mode 1)
      (cl-letf (((symbol-function 'gptel--restore-state) #'ignore))
        (gptel-mode 1)))
    (setq-local gptel-model (alist-get familiar-ask-tier familiar-models)
                gptel-backend (or familiar-backend gptel-backend)
                gptel-system-prompt familiar-ask-system
                gptel-tools familiar-ask-tools
                gptel-use-tools t
                gptel-confirm-tool-calls familiar-ask-confirm-tools
                gptel-cache t
                gptel-include-tool-results 'auto
                ;; Shown, it's mostly empty blocks; the answer is what matters.
                gptel-include-reasoning nil
                ;; Models write Markdown however asked (Haiku did); gptel
                ;; converts it.  Asking for Org *and* converting garbles both.
                gptel-org-convert-response t
                gptel-prompt-prefix-alist '((org-mode . "** "))
                gptel-response-prefix-alist '((org-mode . "")))
    (familiar-ask-mode 1)
    (add-hook 'gptel-post-response-functions #'familiar-ask--after-response nil t)
    ;; Follow the answer as it streams, if wanted.
    (when familiar-ask-auto-scroll
      (add-hook 'gptel-post-stream-hook #'gptel-auto-scroll nil t))
    (setq header-line-format '(:eval (familiar-ask--header-line)))
    buf))

(defun familiar-ask--new-buffer ()
  "A fresh conversation, saved under `familiar-ask-directory'."
  (when-let* ((old (get-buffer familiar-ask--buffer-name)))
    (with-current-buffer old
      ;; Saved and idle (streaming leaves it modified): `familiar-ask-sessions'
      ;; reopens it, so with fresh asks the default they don't pile up.
      (if (and buffer-file-name (not (buffer-modified-p)))
          (kill-buffer old)
        (rename-buffer (generate-new-buffer-name "*familiar-ask (old)*")))))
  (let ((buf (get-buffer-create familiar-ask--buffer-name)))
    (with-current-buffer buf
      (make-directory familiar-ask-directory t)
      ;; Visit the file without renaming the buffer, so the popup rule holds.
      (setq buffer-file-name (expand-file-name (format-time-string "%Y%m%d-%H%M%S.org")
                                               familiar-ask-directory))
      (insert (format "#+title: familiar-ask %s\n\n" (format-time-string "%F %R"))))
    (familiar-ask--setup buf)))

(defconst familiar-ask--echo-instruction
  "(Answer in one to three short lines of plain text, no lists or code blocks: it is shown in the echo area.)"
  "Added to an @echo prompt; not part of what the user asked.")

(defvar-local familiar-ask--echo nil
  "Non-nil when the answer being written goes to the echo area (@echo).")

(defun familiar-ask--after-response (_beg _end)
  "Save the conversation (next tick: after the converter flush below).
gptel itself leaves the next prompt heading (`gptel-prompt-prefix-alist')."
  (let ((buf (current-buffer)))
    (run-at-time 0 nil (lambda ()
                         (when (buffer-live-p buf)
                           (with-current-buffer buf
                             (let ((save-silently t) (inhibit-message t)) (save-buffer))
                             (when (fboundp 'familiar-history-record)
                               (familiar-ask--history))
                             (when familiar-ask--echo
                               (setq familiar-ask--echo nil)
                               (familiar-ask--echo-answer))))))))

(defun familiar-ask--answer-text (bounds)
  "The answer between BOUNDS, without its folded tool blocks."
  (string-trim
   (replace-regexp-in-string
    "^[ \t]*#\\+begin_tool\\(?:.\\|\n\\)*?#\\+end_tool[ \t]*\n?" ""
    (buffer-substring (car bounds) (cdr bounds)))))

(defun familiar-ask--history ()
  "Record the latest turn in the familiar history, linked to this conversation."
  (when-let* ((turn (familiar-ask--last-turn)))
    (let* ((heading (plist-get turn :title))
           (title (replace-regexp-in-string "  \\[[^]]*\\]\\'" "" heading))
           (body (save-excursion
                   (goto-char (plist-get turn :heading))
                   (buffer-substring-no-properties
                    (min (line-beginning-position 2) (plist-get turn :prompt-end))
                    (plist-get turn :prompt-end)))))
      (familiar-history-record
       :prompt (string-trim (string-replace familiar-ask--echo-instruction ""
                                            (concat title "\n" body)))
       :answer (substring-no-properties (familiar-ask--answer-text (plist-get turn :answer)))
       :task 'ask :model familiar-ask--last-model
       :tokens familiar-ask--last-tokens :cost familiar-ask--last-cost
       :link (and buffer-file-name
                  (format "[[file:%s::*%s][conversation]]"
                          (abbreviate-file-name buffer-file-name) heading))))))

(defun familiar-ask--echo-answer ()
  "Show the latest answer in the echo area, as Org shows it."
  (when-let* ((bounds (familiar-ask--last-answer-bounds)))
    (font-lock-ensure (car bounds) (cdr bounds))
    (let ((text (familiar-ask--answer-text bounds))
          (message-truncate-lines nil))
      ;; Faces stay; org-indent's prefixes would indent the echo area.
      (remove-list-of-text-properties 0 (length text) '(line-prefix wrap-prefix) text)
      (message "%s" (if (string-empty-p text) "✦ (no answer)" text)))))


;; gptel's streaming Markdown→Org converter holds back a trailing `*' (or
;; backtick) until more text shows whether it's emphasis or bold, and never
;; flushes it when the answer ends there: "*Magit*" became "/Magit".  Feed
;; it a final newline when the response is done and insert what comes out.
;; Added after the converter's own cleanup, so it runs first (add-hook
;; prepends) while the converter's buffer still exists.
(defun familiar-ask--flush-converter-a (convert start-marker)
  (let ((converter (funcall convert start-marker)) flush)
    (setq flush
          (lambda (beg end)
            (when (and (equal beg (marker-position start-marker))
                       (eq (current-buffer) (marker-buffer start-marker)))
              (remove-hook 'gptel-post-response-functions flush)
              (let ((tail (string-trim-right (or (ignore-errors (funcall converter "\n")) "")
                                             "\n")))
                (unless (string-empty-p tail)
                  (save-excursion (goto-char end) (insert tail)))))))
    (add-hook 'gptel-post-response-functions flush)
    converter))
(advice-add 'gptel--stream-convert-markdown->org :around #'familiar-ask--flush-converter-a)
;; Spend: every turn of an ask conversation lands in familiar's ledger.
(defun familiar-ask--record-a (tokens &optional _tokens-full)
  (when (and tokens (bound-and-true-p familiar-ask-mode))
    ;; The request's model: an @preset in the prompt overrides `gptel-model'.
    (setq familiar-ask--last-model
          (or (and gptel--fsm-last (plist-get (gptel-fsm-info gptel--fsm-last) :model))
              gptel-model))
    (setq familiar-ask--last-tokens tokens
          familiar-ask--last-cost (familiar--record familiar-ask--last-model 'ask tokens))
    (cl-incf familiar-ask--cost familiar-ask--last-cost)))
(advice-add 'gptel--update-token-usage :after #'familiar-ask--record-a)

;;;; Applying a suggestion

(defun familiar-ask--last-turn ()
  "The latest answered turn: plist (:heading POS :title STRING :prompt-end POS
:answer (BEG . END)), or nil.
The answer is what gptel wrote (text property `gptel': response, tool
calls); a follow-up typed in the conversation has no context block, so
\"after the last #+end_context\" took the turn before it.  Without the
property (an older saved conversation), the answer starts after the context."
  (save-excursion
    (goto-char (point-max))
    (let ((end (if (re-search-backward "^\\*\\* *$" nil t) (point) (point-max))))
      (goto-char end)
      (when (re-search-backward "^\\*\\* \\(.*\\)$" nil t)
        (let* ((heading (point))
               (title (match-string-no-properties 1))
               (context (save-excursion
                          (and (re-search-forward "^#\\+begin_context$" end t)
                               (match-beginning 0))))
               (answer (let ((p (next-single-property-change heading 'gptel nil end)))
                         (cond ((and (< p end) (get-text-property p 'gptel)) p)
                               ((get-text-property heading 'gptel) heading)
                               (context (save-excursion
                                          (goto-char context)
                                          (and (re-search-forward "^#\\+end_context$" end t)
                                               (line-beginning-position 2))))))))
          (when answer
            (list :heading heading :title title
                  :prompt-end (min answer (or context answer))
                  :answer (cons answer end))))))))

(defun familiar-ask--last-answer-bounds ()
  "Start and end of the latest answer (see `familiar-ask--last-turn')."
  (plist-get (familiar-ask--last-turn) :answer))

(defun familiar-ask-suggestions ()
  "What the latest answer suggests, in order: a list of (KIND VALUE LABEL).
KIND is `command', `keys', `elisp' or `shell'."
  (when-let* ((bounds (familiar-ask--last-answer-bounds)))
    (let (out)
      (save-excursion
        (goto-char (car bounds))
        (while (re-search-forward
                "^[ \t]*#\\+begin_src[ \t]+\\([^ \t\n]+\\).*\n\\(\\(?:.*\n\\)*?\\)[ \t]*#\\+end_src\\|\\([~=]\\)\\([^~=\n]+\\)\\3"
                (cdr bounds) t)
          (let ((lang (match-string-no-properties 1))
                (body (match-string-no-properties 2))
                ;; ~code~ from the model, =code= from gptel's Markdown conversion.
                (code (match-string-no-properties 4)))
            (cond
             (lang
              (cond ((member lang '("elisp" "emacs-lisp"))
                     (push (list 'elisp body (concat "eval: " (string-trim (car (split-string body "\n"))))) out))
                    ((member lang '("sh" "bash" "shell" "zsh" "eshell"))
                     (push (list 'shell (string-trim body) (concat "at prompt: " (string-trim body))) out))))
             ((and (intern-soft code) (commandp (intern-soft code)))
              (push (list 'command (intern-soft code) (concat "M-x " code)) out))
             ((and (string-match-p "\\`\\(?:\\(?:[CMSsHA]-\\)+\\S-+\\|SPC\\)\\(?: \\S-+\\)*\\'" code)
                   (ignore-errors (key-valid-p code)))
              (push (list 'keys code (concat "keys: " code)) out))))))
      (delete-dups (nreverse out)))))

(defun familiar-ask--apply (suggestion)
  "Carry out SUGGESTION, (KIND VALUE LABEL), where the question was asked."
  (let* ((origin familiar-ask--origin)
         (buf (plist-get origin :buffer))
         (win (and (buffer-live-p buf) (get-buffer-window buf t))))
    (unless (buffer-live-p buf) (user-error "The buffer asked from is gone"))
    (pcase-let ((`(,kind ,value ,label) suggestion))
      (when win (select-window win))
      (with-current-buffer buf
        (pcase kind
          ('command (call-interactively value))
          ('keys (execute-kbd-macro (kbd value)))
          ('elisp (message "%S" (eval (read (format "(progn %s)" value)) t)))
          ('shell (familiar-ask-insert-at-prompt value))))
      (message "Applied: %s" label))))

(defun familiar-ask-apply (&optional first)
  "Apply a suggestion from the latest answer, picked; with FIRST the first one."
  (interactive)
  (let* ((suggestions (or (familiar-ask-suggestions)
                          (user-error "Nothing runnable in the latest answer")))
         (pick (if (or first (null (cdr suggestions)))
                   (car suggestions)
                 (let ((labels (mapcar #'caddr suggestions)))
                   (nth (cl-position (completing-read "Apply: " labels nil t nil nil (car labels))
                                     labels :test #'equal)
                        suggestions)))))
    (familiar-ask--apply pick)))

(defun familiar-ask-apply-first ()
  "Apply the first suggestion of the latest answer."
  (interactive)
  (familiar-ask-apply t))

;;;; Prompting

;; @fast, @smart, @deep anywhere in a prompt pick the model for that turn.
(dolist (tier familiar-models)
  (gptel-make-preset (car tier)
    :description (format "familiar-ask on %s" (cdr tier))
    :model (cdr tier)))


;;;; @model: who answers this turn

(defun familiar-ask--model-choices ()
  "What @model can pick: alist of (LABEL . (BACKEND . MODEL)) for every
model of every gptel backend, and (LABEL . (agent . TARGET)) for each coding
agent running now (`familiar-handoff-targets', clipboard aside)."
  (append
   (cl-loop for (name . backend) in gptel--known-backends
            nconc (cl-loop for model in (gptel-backend-models backend)
                           collect (cons (format "%s:%s" name model) (cons backend model))))
   (cl-loop for (target . props) in familiar-handoff-targets
            unless (eq target 'clipboard)
            when (ignore-errors (funcall (plist-get props :available)))
            collect (cons (format "agent:%s" target) (cons 'agent target)))))

(defun familiar-ask--model-spec (prompt)
  "PROMPT without its @model, and what it asked for: (TEXT . SPEC).
SPEC is nil without @model, t for a bare @model (pick one), else the NAME
of @model:NAME."
  (if (string-match "\\(?:^\\|[ \t]+\\)@model\\(?::\\(\\S-+\\)\\)?\\(?:[ \t]+\\|$\\)" prompt)
      (cons (string-trim (replace-match " " t t prompt))
            (or (match-string 1 prompt) t))
    (cons prompt nil)))

(defun familiar-ask--resolve-model (spec)
  "The (BACKEND . MODEL) or (agent . TARGET) SPEC names, asking for t.
NAME may be a label of `familiar-ask--model-choices' or its part after the
colon: a model name (the current backend's first) or an agent."
  (let ((choices (familiar-ask--model-choices))
        (current (or familiar-backend gptel-backend)))
    (if (eq spec t)
        (cdr (assoc (completing-read "Answer with: " choices nil t) choices))
      (or (cdr (assoc spec choices))
          (let ((matches (seq-filter (lambda (c) (equal (cadr (split-string (car c) ":")) spec))
                                     choices)))
            (cdr (or (seq-find (lambda (c) (eq (cadr c) current)) matches)
                     (car matches))))
          (user-error "@model: no model or agent named %s" spec)))))

(defun familiar-ask--model-capf ()
  "Complete the NAME of @model:NAME in the prompt."
  (when (looking-back "@model:\\(\\S-*\\)" (line-beginning-position))
    (let ((choices (familiar-ask--model-choices)))
      (list (match-beginning 1) (point)
            (delete-dups (mapcar (lambda (c) (cadr (split-string (car c) ":"))) choices))
            :annotation-function
            (lambda (name)
              (when-let* ((c (seq-find (lambda (c) (equal (cadr (split-string (car c) ":")) name))
                                       choices)))
                (concat "  " (car (split-string (car c) ":")))))
            :exclusive 'no))))

(defun familiar-ask--hand-off (prompt target origin)
  "Hand PROMPT and the context at ORIGIN to the running agent TARGET."
  (let ((props (alist-get target familiar-handoff-targets))
        (buf (plist-get origin :buffer)))
    (funcall (plist-get props :send)
             (if (buffer-live-p buf)
                 (concat prompt "\n\n"
                         (with-current-buffer buf
                           (save-excursion
                             (goto-char (or (plist-get origin :point) (point)))
                             (familiar-handoff-context))))
               prompt))
    (message "familiar: asked %s" target)))

;;;; @inline and @replace: the answer goes where you are

(defconst familiar-ask--inline-system
  "You write text that goes straight into an Emacs buffer, where the excerpt \
shows ⟦here⟧ (or, when replacing, in place of the text between ⟦selection⟧ \
and ⟦/selection⟧).  Reply with that text only: no preamble, no explanation, \
no markers, no code fences around it, nothing repeated from around it.  \
Write in the buffer's language and markup (its major mode: Org markup in \
Org, Markdown in Markdown, code in a programming mode, comments as that \
language writes them), and match the indentation, style and natural \
language of the surrounding text."
  "System prompt of @inline and @replace turns.")

(defcustom familiar-ask-inline-excerpt 4000
  "Characters before the place written to that an @inline turn sends along.
Half as many after it."
  :type 'natnum :group 'familiar)

(defun familiar-ask--inline-place (origin replace)
  "Where an answer to ORIGIN goes: (BEG END NEWLINE).
REPLACE: in place of the region, BEG to END.  Else at one place: after the
region; at point in insert state (or without evil); in normal state at the
end of point's line, NEWLINE meaning on a new line after it (point's line
holds text)."
  (let ((region (plist-get origin :region))
        (buf (plist-get origin :buffer)))
    (with-current-buffer buf
      (save-excursion
        (goto-char (plist-get origin :point))
        (cond (replace (if region (list (car region) (cdr region) nil)
                         (user-error "@replace needs a region")))
              (region (list (cdr region) (cdr region) nil))
              ((not (memq (bound-and-true-p evil-state) '(normal motion visual)))
               (list (point) (point) nil))
              (t (let ((blank (string-blank-p (buffer-substring (line-beginning-position)
                                                                 (line-end-position)))))
                   (list (line-end-position) (line-end-position) (not blank)))))))))

(defun familiar-ask--inline-excerpt (origin place replace)
  "Text around PLACE in ORIGIN's buffer, marked where the answer goes."
  (pcase-let ((`(,beg ,end ,newline) place)
              (region (plist-get origin :region)))
    (with-current-buffer (plist-get origin :buffer)
      (let* ((from (max (point-min) (- (if region (car region) beg) familiar-ask-inline-excerpt)))
             (to (min (point-max) (+ end (/ familiar-ask-inline-excerpt 2))))
             (text (lambda (a b) (buffer-substring-no-properties a b))))
        (format "Buffer %s (%s%s)\n\n%s"
                (buffer-name) major-mode
                (if buffer-file-name (format ", file %s" (abbreviate-file-name buffer-file-name)) "")
                (cond (replace
                       (concat (funcall text from beg) "⟦selection⟧" (funcall text beg end)
                               "⟦/selection⟧" (funcall text end to)))
                      (region
                       (concat (funcall text from (car region)) "⟦selection⟧"
                               (funcall text (car region) beg) "⟦/selection⟧⟦here⟧"
                               (funcall text beg to)))
                      (t (concat (funcall text from beg) (if newline "\n⟦here⟧\n" "⟦here⟧")
                                 (funcall text beg to)))))))))

(defun familiar-ask--inline (prompt origin replace model)
  "Write the answer to PROMPT into ORIGIN's buffer as it streams.
Where: `familiar-ask--inline-place'; REPLACE puts it in place of the region.
MODEL (BACKEND . MODEL) answers, else `familiar-ask-tier'.  One undo takes
the whole of it back (and the replaced text with it)."
  (let* ((buf (plist-get origin :buffer))
         (place (familiar-ask--inline-place origin replace))
         (request (concat (familiar-ask--inline-excerpt origin place replace)
                          "\n\nWhat to write: " prompt))
         start end deleted)
    (with-current-buffer buf
      (barf-if-buffer-read-only)
      ;; Chunks go in without undo records; one record of the whole goes in
      ;; at the end, so a single undo removes it (and restores a replaced
      ;; region), however many chunks it came in.
      (let ((buffer-undo-list t))
        (pcase-let ((`(,beg ,end* ,newline) place))
          (when replace
            (setq deleted (buffer-substring beg end*))
            (delete-region beg end*))
          (setq start (copy-marker beg)
                end (copy-marker beg t))
          (when newline (save-excursion (goto-char end) (insert "\n"))))))
    (message "✦ Writing into %s…" (buffer-name buf))
    (familiar-request
     request :task 'ask :system familiar-ask--inline-system :stream t
     :model (or (cdr model) (alist-get familiar-ask-tier familiar-models))
     :backend (car model)
     :callback
     (lambda (response _info)
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (cond ((stringp response)
                  (let ((buffer-undo-list t))
                    (save-excursion (goto-char end) (insert response))))
                 ((memq response '(t nil))
                  (unless (eq buffer-undo-list t)
                    (undo-boundary)
                    (when deleted (push (cons deleted (marker-position start)) buffer-undo-list))
                    (push (cons (marker-position start) (marker-position end)) buffer-undo-list)
                    (undo-boundary))
                  (when response
                    (pulse-momentary-highlight-region start end)
                    (message "✦ Written into %s (undo takes it back)" (buffer-name buf)))))))))))

;;;; @transient: decide how to ask after writing the prompt

(require 'transient)

(defun familiar-ask--transient-value (keywords spec)
  "The transient's starting arguments, from a prompt's KEYWORDS and @model SPEC."
  (delq nil
        (list (cond ((memq 'echo keywords) "--where=echo")
                    ((memq 'inline keywords) "--where=inline")
                    ((memq 'replace keywords) "--where=replace"))
              (and (or (memq 'follow-up keywords)
                       (and familiar-ask-follow-up (not (memq 'new keywords))))
                   "--follow-up")
              (and (stringp spec) (concat "--model=" spec)))))

(defun familiar-ask--transient-prompt (prompt args)
  "PROMPT with the @keywords that ARGS of `familiar-ask-transient' stand for."
  (string-join
   (delq nil (list prompt
                   (when-let* ((where (transient-arg-value "--where=" args)))
                     (concat "@" where))
                   (if (member "--follow-up" args) "@follow-up" "@new")
                   (when-let* ((model (transient-arg-value "--model=" args)))
                     (concat "@model:" model))))
   " "))

(defun familiar-ask--read-model (prompt _initial _history)
  "Read a label of `familiar-ask--model-choices' with PROMPT."
  (completing-read prompt (familiar-ask--model-choices) nil t))

(transient-define-prefix familiar-ask-transient ()
  "How to ask the prompt written (@transient): where the answer goes,
which conversation, who answers."
  [:description
   (lambda () (format "✦ %s" (truncate-string-to-width (car (transient-scope)) 70 nil nil "…")))
   ["Answer goes"
    ("w" "into (unset: the conversation)" "--where=" :choices ("echo" "inline" "replace"))
    ("f" "follow up the running conversation" "--follow-up")]
   ["Answered by"
    ("m" "model or agent" "--model=" :reader familiar-ask--read-model)]
   ["Ask"
    ("RET" "send" familiar-ask-transient-send)
    ("e" "edit the prompt first" familiar-ask-transient-edit)]])

(transient-define-suffix familiar-ask-transient-send (args)
  "Send the prompt as the transient says."
  (interactive (list (transient-args 'familiar-ask-transient)))
  (pcase-let ((`(,prompt ,origin) (transient-scope)))
    (familiar-ask (familiar-ask--transient-prompt prompt args) nil origin)))

(transient-define-suffix familiar-ask-transient-edit (args)
  "Edit the prompt, with the transient's choices as @keywords, in a buffer."
  (interactive (list (transient-args 'familiar-ask-transient)))
  (pcase-let ((`(,prompt ,origin) (transient-scope)))
    (setq familiar-ask--origin origin)
    (familiar-ask--open-editor (familiar-ask--transient-prompt prompt args))))

(defun familiar-ask--transient (prompt origin keywords spec)
  "Open `familiar-ask-transient' for PROMPT (keywords out) asked at ORIGIN."
  (transient-setup 'familiar-ask-transient nil nil
                   :scope (list prompt origin)
                   :value (familiar-ask--transient-value keywords spec)))

(defvar familiar-ask-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c '") #'familiar-ask-edit-prompt)
    (define-key map (kbd "C-r") #'familiar-ask-pick-history)
    ;; Not `set-mark-command': evil's insert-state C-SPC doesn't reach here.
    (define-key map (kbd "C-SPC") #'completion-at-point)
    map)
  "Extra keys while reading a `familiar-ask' prompt.")

(defun familiar-ask--all-keywords ()
  "`familiar-ask-keywords' and those of `familiar-ask-keyword-functions'.
From the minibuffer, for the buffer the prompt is about."
  (with-current-buffer (if (minibufferp) (window-buffer (minibuffer-selected-window))
                         (current-buffer))
    (append familiar-ask-keywords
            (mapcan (lambda (f) (copy-sequence (funcall f))) familiar-ask-keyword-functions))))

(defun familiar-ask--keywords-capf ()
  "Complete @keywords and @presets in the prompt."
  (if (looking-back "@model:\\S-*" (line-beginning-position))
      (familiar-ask--model-capf)
    (when (looking-back "@\\([[:alnum:]-]*\\)" (line-beginning-position))
      (let ((cands (append (familiar-ask--all-keywords)
                           (mapcar (lambda (p)
                                     (cons (symbol-name (car p))
                                           (or (plist-get (cdr p) :description) "")))
                                   gptel--known-presets))))
        (list (match-beginning 1) (point) (mapcar #'car cands)
              :annotation-function
              (lambda (c) (concat "  " (cdr (assoc c cands))))
              :exclusive 'no)))))

(defun familiar-ask--keywords (prompt)
  "PROMPT without its @keywords, and the keywords: (TEXT . SYMBOLS)."
  (let (found)
    (dolist (kw (familiar-ask--all-keywords))
      (let ((re (format "\\(?:^\\|[ \t]+\\)@%s\\b" (regexp-quote (car kw)))))
        (when (string-match-p re prompt)
          (push (intern (car kw)) found)
          (setq prompt (replace-regexp-in-string re "" prompt)))))
    (cons (string-trim prompt) found)))

(defvar-local familiar-ask--prompt-p nil "Non-nil in the minibuffer reading a prompt.")

(defun familiar-ask--keep-prompt-h ()
  "Keep the prompt in `familiar-ask-history' however its minibuffer closes.
Sent prompts were kept anyway; abandoned ones (C-g) were lost.  A prompt
equal to the newest one isn't added again (`add-to-history')."
  (when familiar-ask--prompt-p
    (let ((text (string-trim (minibuffer-contents-no-properties))))
      (unless (string-empty-p text)
        (add-to-history 'familiar-ask-history text)))))
(add-hook 'minibuffer-exit-hook #'familiar-ask--keep-prompt-h)

(defun familiar-ask--read ()
  "Read a prompt, with history and @keyword completion."
  (minibuffer-with-setup-hook
      (lambda ()
        (use-local-map (make-composed-keymap familiar-ask-minibuffer-map (current-local-map)))
        (add-hook 'completion-at-point-functions #'familiar-ask--keywords-capf nil t)
        (dolist (capf (reverse familiar-ask-prompt-capfs))
          (add-hook 'completion-at-point-functions capf 50 t))
        (setq-local familiar-ask--prompt-p t)
        (run-hooks 'familiar-ask-prompt-setup-hook))
    (prog1 (read-string (format "Ask (%s): " (alist-get familiar-ask-tier familiar-models))
                        (prog1 familiar-ask--draft (setq familiar-ask--draft nil))
                        'familiar-ask-history)
      (when (bound-and-true-p savehist-mode)
        (add-to-list 'savehist-additional-variables 'familiar-ask-history)))))

;;;###autoload
(defun familiar-ask (prompt &optional fresh origin)
  "Ask PROMPT about where you are.
FRESH t starts a fresh conversation, `follow-up' continues the running
one, nil does what `familiar-ask-follow-up' says; @new and @follow-up in
PROMPT win over it.  Interactively the prefix arg does the opposite of
the default.  @echo answers in the echo area, without a window.  ORIGIN
is where it was asked from (`familiar-ask--capture'); from Lisp it
defaults to here and now.  It used to fall back to the last interactive
ask's, which could be another buffer minutes ago."
  (interactive
   (let ((origin (familiar-ask--capture)))
     (setq familiar-ask--origin origin)   ; for C-c ' (`familiar-ask-edit-prompt')
     (list (familiar-ask--read)
           (and current-prefix-arg (if familiar-ask-follow-up t 'follow-up))
           origin)))
  (pcase-let* ((`(,prompt . ,spec) (familiar-ask--model-spec prompt))
               (`(,prompt . ,keywords) (familiar-ask--keywords prompt)))
    (when (string-blank-p prompt) (user-error "Empty prompt"))
    (if (memq 'transient keywords)
        (familiar-ask--transient prompt (or origin (familiar-ask--capture)) keywords spec)
      (let* ((follow (cond ((memq 'new keywords) nil)
                           ((memq 'follow-up keywords) t)
                           ((eq fresh t) nil)
                           ((eq fresh 'follow-up) t)
                           (t familiar-ask-follow-up)))
             (echo (memq 'echo keywords))
             (origin (or origin (familiar-ask--capture)))
             (model (and spec (familiar-ask--resolve-model spec))))
        (cond
         ((eq (car model) 'agent)
          (familiar-ask--hand-off prompt (cdr model) origin))
         ((or (memq 'inline keywords) (memq 'replace keywords))
          (familiar-ask--inline prompt origin (memq 'replace keywords) model))
         (t
          (familiar-ask--send
           (if echo (concat prompt "\n\n" familiar-ask--echo-instruction) prompt)
           follow echo origin keywords model)))))))

(defun familiar-ask--show (buf win)
  "Display BUF, from WIN when it's still there, unless BUF is on screen.
From WIN: asked from the minibuffer, the minibuffer window is selected."
  (when (and (buffer-live-p buf) (not (get-buffer-window buf)))
    (if (window-live-p win)
        (with-selected-window win (display-buffer buf))
      (display-buffer buf))))

(defun familiar-ask--send (prompt follow echo origin &optional keywords model)
  "Put PROMPT and ORIGIN's context into the conversation and send it.
FOLLOW continues the running conversation; ECHO shows the answer in the
echo area instead of the conversation's window.  KEYWORDS (symbols) may
add tools for this turn (`familiar-ask-turn-tools-functions'); MODEL
(BACKEND . MODEL) answers it instead of the conversation's model."
  (let* ((context (familiar-ask--context origin))
         (buf (if (and follow (get-buffer familiar-ask--buffer-name))
                  (get-buffer familiar-ask--buffer-name)
                (familiar-ask--new-buffer))))
    (setq familiar-ask--origin origin)
    (with-current-buffer buf
      (goto-char (point-max))
      ;; gptel left an empty "** " (a bare "**" in older files): ask there.
      (skip-chars-backward " \t\n")
      (if (looking-back "^\\*\\*" (line-beginning-position))
          (progn (delete-region (point) (point-max)) (insert " "))
        (delete-region (point) (point-max))
        (insert "\n\n** "))
      (let ((lines (split-string (string-trim prompt) "\n"))
            (turn (point)))
        ;; Heading: the first line, stamped; the rest of the prompt below it.
        (insert (car lines) (format-time-string "  [%F %a %R]") "\n"
                (mapconcat (lambda (l) (concat l "\n")) (cdr lines) "")
                context "\n")
        ;; Blocks folded: the context, a library prompt's instructions
        ;; (familiar-prompts.el); they're for the model, you know them.
        (save-excursion
          (goto-char turn)
          (while (re-search-forward "^#\\+begin_" nil t)
            (org-fold-hide-block-toggle t)
            (re-search-forward "^#\\+end_" nil t))))
      (goto-char (point-max)))
    (with-current-buffer buf (setq familiar-ask--echo echo))
    (if echo
        (message "✦ Asking…")
      (familiar-ask--show buf (plist-get origin :window))
      ;; Leaving a minibuffer undoes the window changes made while it was
      ;; open (`read-minibuffer-restore-windows'): asked from M-x, the answer
      ;; vanished with C-g.  Show it again once that minibuffer is gone.
      (when (plist-get origin :minibuffer)
        (letrec ((again (lambda ()
                          (remove-hook 'minibuffer-exit-hook again)
                          (run-at-time 0 nil #'familiar-ask--show
                                       buf (plist-get origin :window)))))
          (add-hook 'minibuffer-exit-hook again))))
    ;; Doom's popup `display-buffer' can leave another buffer current, and
    ;; `gptel-send' sends whatever buffer is current: send explicitly here.
    (let ((extra (mapcan (lambda (f) (copy-sequence (funcall f keywords origin)))
                         familiar-ask-turn-tools-functions)))
      (with-current-buffer buf
        ;; Per turn: an @server's tools ride along only when asked for.
        (setq-local gptel-tools (append familiar-ask-tools extra))
        (goto-char (point-max))
        (familiar-ask--send-with-model model)))
    buf))

(defun familiar-ask-pick-history ()
  "Replace the prompt with an earlier one, picked with completion."
  (interactive)
  (if (fboundp 'consult-history)
      (consult-history familiar-ask-history)
    (let ((pick (completing-read "Earlier prompt: " familiar-ask-history nil t)))
      (delete-minibuffer-contents)
      (insert pick))))


;;;###autoload
(defun familiar-ask-new (prompt &optional origin)
  "Ask PROMPT in a fresh conversation."
  (interactive
   (let ((origin (familiar-ask--capture)))
     (setq familiar-ask--origin origin)
     (list (familiar-ask--read) origin)))
  (familiar-ask prompt t origin))

;;;###autoload
(defun familiar-ask-continue (prompt &optional origin)
  "Ask PROMPT in the running conversation (like @follow-up)."
  (interactive
   (let ((origin (familiar-ask--capture)))
     (setq familiar-ask--origin origin)
     (list (familiar-ask--read) origin)))
  (familiar-ask prompt 'follow-up origin))

;;;; Editing a prompt in a buffer

(defvar familiar-ask-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'familiar-ask-edit-send)
    (define-key map (kbd "C-c C-k") #'familiar-ask-edit-keep)
    (define-key map (kbd "C-c C-q") #'familiar-ask-edit-discard)
    (define-key map (kbd "M-p") #'familiar-ask-edit-previous)
    (define-key map (kbd "M-n") #'familiar-ask-edit-next)
    map))

(define-minor-mode familiar-ask-edit-mode
  "Writing a `familiar-ask' prompt: C-c C-c sends, C-c C-k keeps it for
later, C-c C-q discards it (into the history), M-p / M-n go through the
history;  and words complete as in the minibuffer."
  :lighter " ✦prompt"
  (when familiar-ask-edit-mode
    (setq header-line-format '(:eval (familiar-ask--edit-header)))))

(defun familiar-ask--edit-header ()
  "Header line of the prompt buffer: where it asks from, and the keys."
  (let* ((origin familiar-ask--origin)
         (buf (plist-get origin :buffer))
         (region (plist-get origin :region)))
    (substitute-command-keys
     (format " ✦ Ask%s%s   \\[familiar-ask-edit-send] send · \\[familiar-ask-edit-keep] keep · \\[familiar-ask-edit-discard] discard · \\[familiar-ask-edit-previous]/\\[familiar-ask-edit-next] history"
             (if (buffer-live-p buf) (format " about %s" (buffer-name buf)) "")
             (if region (format " (region, %d chars)" (- (cdr region) (car region))) "")))))

(defun familiar-ask--open-editor (text)
  "Open the prompt buffer with TEXT, asking about `familiar-ask--origin'."
  (let ((origin-buf (plist-get familiar-ask--origin :buffer)))
    (pop-to-buffer (get-buffer-create "*familiar-ask prompt*"))
    (erase-buffer)
    (org-mode)
    ;; @server keywords and words come from the place asked about.
    (when (buffer-live-p origin-buf)
      (setq default-directory (buffer-local-value 'default-directory origin-buf)))
    (insert (or text ""))
    (familiar-ask-edit-mode 1)
    (add-hook 'completion-at-point-functions #'familiar-ask--keywords-capf nil t)
    (dolist (capf (reverse familiar-ask-prompt-capfs))
      (add-hook 'completion-at-point-functions capf 50 t))
    (setq-local familiar-ask--history-index -1)
    (when (fboundp 'evil-insert-state) (evil-insert-state))))

;;;###autoload
(defun familiar-ask-compose ()
  "Write a prompt in a buffer right away (multi-line), about where you are."
  (interactive)
  (setq familiar-ask--origin (familiar-ask--capture))
  (familiar-ask--open-editor (prog1 familiar-ask--draft (setq familiar-ask--draft nil))))

(defun familiar-ask-edit-prompt ()
  "Move the prompt being typed into a buffer, like `org-edit-special'."
  (interactive)
  (let ((text (minibuffer-contents-no-properties)))
    (setq familiar-ask--draft text)
    (run-at-time 0 nil (lambda ()
                         (familiar-ask--open-editor
                          (prog1 familiar-ask--draft (setq familiar-ask--draft nil)))))
    (abort-recursive-edit)))

(defvar-local familiar-ask--history-index -1
  "Position in `familiar-ask-history' shown in the prompt buffer (-1: own text).")

(defun familiar-ask-edit-previous (n)
  "Replace the prompt with the Nth earlier one from the history."
  (interactive "p")
  (let ((i (+ familiar-ask--history-index n)))
    (cond ((>= i (length familiar-ask-history)) (user-error "No earlier prompt"))
          ((< i -1) (user-error "No later prompt"))
          (t (setq familiar-ask--history-index i)
             (erase-buffer)
             (when (>= i 0) (insert (nth i familiar-ask-history)))))))

(defun familiar-ask-edit-next (n)
  "Replace the prompt with the Nth later one from the history."
  (interactive "p")
  (familiar-ask-edit-previous (- n)))

(defun familiar-ask-edit-discard ()
  "Close the prompt buffer without sending; the text stays in the history."
  (interactive)
  (let ((text (string-trim (buffer-string))))
    (unless (string-empty-p text) (add-to-history 'familiar-ask-history text))
    (setq familiar-ask--draft nil)
    (quit-window t)
    (message "Prompt discarded (it is in the history: M-p)")))

(defun familiar-ask-edit-send ()
  "Send the prompt in this buffer; its major mode goes along."
  (interactive)
  (let ((text (string-trim (buffer-string)))
        (mode major-mode))
    (setq familiar-ask--draft nil)
    (add-to-history 'familiar-ask-history text)
    (quit-window t)
    ;; Where the prompt was started, not this prompt buffer.
    (familiar-ask (format "%s\n\n(Prompt written in %s.)" text mode) nil familiar-ask--origin)))

(defun familiar-ask-edit-keep ()
  "Close the prompt buffer; the next `familiar-ask' starts with its text."
  (interactive)
  (setq familiar-ask--draft (string-trim (buffer-string)))
  (quit-window t)
  (message "Prompt kept; M-ß brings it back"))

;;;; Earlier conversations

;;;###autoload
(defun familiar-ask-sessions ()
  "Reopen an earlier conversation, newest first."
  (interactive)
  (let* ((files (sort (directory-files familiar-ask-directory t "\\.org\\'")
                      (lambda (a b) (string> a b))))
         (cands (mapcar (lambda (f)
                          (cons (format "%s  %s"
                                        (file-name-base f)
                                        (with-temp-buffer
                                          (insert-file-contents f nil 0 2000)
                                          (if (re-search-forward "^\\*\\* \\(.+\\)" nil t)
                                              (match-string 1) "")))
                                f))
                        files))
         (pick (cdr (assoc (completing-read "Conversation: " cands nil t) cands))))
    (with-current-buffer (find-file-noselect pick)
      (familiar-ask--setup (current-buffer))
      (pop-to-buffer (current-buffer)))))

;;;; Export

(defun familiar-ask--transcript ()
  "This conversation as Org, without the context blocks and the title."
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward "^#\\+begin_context\n\\(?:.*\n\\)*?#\\+end_context\n?" nil t)
        (replace-match ""))
      ;; gptel's saved state (a property drawer) and the title, at the top.
      (goto-char (point-min))
      (when (looking-at ":PROPERTIES:\n\\(?:.*\n\\)*?:END:\n+") (replace-match ""))
      (when (looking-at "#\\+title:.*\n+") (replace-match ""))
      (string-trim (buffer-string)))))

;;;###autoload
(defun familiar-ask-export (format)
  "Copy this conversation as FORMAT (org or markdown) to the kill ring."
  (interactive
   (list (intern (completing-read "Copy conversation as: " '("markdown" "org") nil t))))
  (let ((org (familiar-ask--transcript)))
    (kill-new
     (if (eq format 'org)
         org
       (require 'ox-md)
       (with-temp-buffer
         (insert org)
         (org-mode)
         (org-export-as 'md nil nil nil '(:with-toc nil :section-numbers nil)))))
    (message "Conversation copied as %s" format)))

(provide 'familiar-ask)
;;; familiar-ask.el ends here
