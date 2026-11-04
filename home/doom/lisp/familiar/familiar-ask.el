;;; familiar-ask.el --- Ask anything, from anywhere in Emacs -*- lexical-binding: t; -*-
;;
;; One key (M-ß by default) from any buffer, including the minibuffer and
;; buffers that visit no file, asks a long-lived conversation.  What you were
;; looking at goes along as context, so you never restate it; tools let the
;; model look around Emacs itself and act in it, the way you would (edits are
;; undoable, nothing is written to disk unless you ask for it).
;;
;;   M-ß              ask (in the minibuffer too: "exclude tests" in M-x)
;;   SPC u M-ß        ask in a fresh conversation (C-u in insert state; in normal
;;                    state C-u scrolls), or familiar-ask-new (SPC A N)
;;   C-c '  (prompt)  edit the prompt in a buffer; C-c C-c sends, C-c C-k keeps it
;;   @fast/@smart/@deep in the prompt picks the model (gptel presets)
;;   C-r  (prompt)    pick an earlier prompt
;;   RET / S-RET      in the conversation: send a follow-up / newline
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

(defun familiar-ask-ret ()
  "Send a follow-up when point is in the last, unanswered prompt; else newline."
  (interactive)
  (if (and (eobp) (not (looking-back "^\\*+ *\\|\\`\\s-*" (line-beginning-position))))
      (gptel-send)
    (newline)))

(defun familiar-ask--header-line ()
  "Model, prompts, cost and start of this conversation."
  (format " ✦ familiar-ask  ·  %s  ·  %s  ·  $%.4f%s"
          gptel-model
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
    (gptel-mode 1)
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
    ;; Follow the answer as it streams.
    (add-hook 'gptel-post-stream-hook #'gptel-auto-scroll nil t)
    (setq header-line-format '(:eval (familiar-ask--header-line)))
    buf))

(defun familiar-ask--new-buffer ()
  "A fresh conversation, saved under `familiar-ask-directory'."
  (when-let* ((old (get-buffer familiar-ask--buffer-name)))
    (with-current-buffer old (rename-buffer (generate-new-buffer-name "*familiar-ask (old)*"))))
  (let ((buf (get-buffer-create familiar-ask--buffer-name)))
    (with-current-buffer buf
      (make-directory familiar-ask-directory t)
      ;; Visit the file without renaming the buffer, so the popup rule holds.
      (setq buffer-file-name (expand-file-name (format-time-string "%Y%m%d-%H%M%S.org")
                                               familiar-ask-directory))
      (insert (format "#+title: familiar-ask %s\n\n" (format-time-string "%F %R"))))
    (familiar-ask--setup buf)))

(defun familiar-ask--after-response (_beg _end)
  "Save the conversation (next tick: after the converter flush below).
gptel itself leaves the next prompt heading (`gptel-prompt-prefix-alist')."
  (let ((buf (current-buffer)))
    (run-at-time 0 nil (lambda ()
                         (when (buffer-live-p buf)
                           (with-current-buffer buf
                             (let ((save-silently t) (inhibit-message t)) (save-buffer))))))))


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
    (cl-incf familiar-ask--cost
             (familiar--record (or (and gptel--fsm-last
                               (plist-get (gptel-fsm-info gptel--fsm-last) :model))
                          gptel-model)
                      'ask tokens))))
(advice-add 'gptel--update-token-usage :after #'familiar-ask--record-a)

;;;; Applying a suggestion

(defun familiar-ask--last-answer-bounds ()
  "Start and end of the latest answer: after the last context block."
  (save-excursion
    (goto-char (point-max))
    (when (re-search-backward "^#\\+end_context$" nil t)
      (cons (line-beginning-position 2)
            (progn (goto-char (point-max))
                   (if (re-search-backward "^\\*\\* *$" nil t) (point) (point-max)))))))

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

(defvar familiar-ask-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c '") #'familiar-ask-edit-prompt)
    (define-key map (kbd "C-r") #'familiar-ask-pick-history)
    map)
  "Extra keys while reading a `familiar-ask' prompt.")

(defun familiar-ask--presets-capf ()
  "Complete @preset cookies in the prompt."
  (when (looking-back "@\\([[:alnum:]-]*\\)" (line-beginning-position))
    (list (match-beginning 1) (point)
          (mapcar (lambda (p) (symbol-name (car p))) gptel--known-presets))))

(defun familiar-ask--read ()
  "Read a prompt, with history and @preset completion."
  (minibuffer-with-setup-hook
      (lambda ()
        (use-local-map (make-composed-keymap familiar-ask-minibuffer-map (current-local-map)))
        (add-hook 'completion-at-point-functions #'familiar-ask--presets-capf nil t))
    (prog1 (read-string (format "Ask (%s): " (alist-get familiar-ask-tier familiar-models))
                        (prog1 familiar-ask--draft (setq familiar-ask--draft nil))
                        'familiar-ask-history)
      (when (bound-and-true-p savehist-mode)
        (add-to-list 'savehist-additional-variables 'familiar-ask-history)))))

;;;###autoload
(defun familiar-ask (prompt &optional new origin)
  "Ask PROMPT about where you are, in the running conversation.
With prefix arg NEW, start a fresh conversation.  ORIGIN is where it was
asked from (`familiar-ask--capture'); from Lisp it defaults to here and now.
It used to fall back to the last interactive ask's, which could be another
buffer minutes ago."
  (interactive
   (let ((origin (familiar-ask--capture)))
     (setq familiar-ask--origin origin)   ; for C-c ' (`familiar-ask-edit-prompt')
     (list (familiar-ask--read) current-prefix-arg origin)))
  (when (string-blank-p prompt) (user-error "Empty prompt"))
  (let* ((origin (or origin (familiar-ask--capture)))
         (context (familiar-ask--context origin))
         (buf (if (or new (not (get-buffer familiar-ask--buffer-name)))
                  (familiar-ask--new-buffer)
                (get-buffer familiar-ask--buffer-name))))
    (setq familiar-ask--origin origin)
    (with-current-buffer buf
      (goto-char (point-max))
      ;; gptel left an empty "** " (a bare "**" in older files): ask there.
      (skip-chars-backward " \t\n")
      (if (looking-back "^\\*\\*" (line-beginning-position))
          (progn (delete-region (point) (point-max)) (insert " "))
        (delete-region (point) (point-max))
        (insert "\n\n** "))
      (let ((lines (split-string (string-trim prompt) "\n")))
        ;; Heading: the first line, stamped; the rest of the prompt below it.
        (insert (car lines) (format-time-string "  [%F %a %R]") "\n"
                (mapconcat (lambda (l) (concat l "\n")) (cdr lines) "")
                context "\n"))
      ;; Context folded: it's for the model, you saw it already.
      (save-excursion
        (when (re-search-backward "^#\\+begin_context" nil t)
          (org-fold-hide-block-toggle t)))
      (goto-char (point-max)))
    ;; Doom's popup `display-buffer' can leave another buffer current, and
    ;; `gptel-send' sends whatever buffer is current: send explicitly here.
    (display-buffer buf)
    (with-current-buffer buf
      (goto-char (point-max))
      (gptel-send))
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

;;;; Editing a prompt in a buffer

(defvar familiar-ask-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'familiar-ask-edit-send)
    (define-key map (kbd "C-c C-k") #'familiar-ask-edit-keep)
    map))

(define-minor-mode familiar-ask-edit-mode
  "Editing a `familiar-ask' prompt.  C-c C-c sends, C-c C-k keeps it for later."
  :lighter " ✦prompt"
  (when familiar-ask-edit-mode
    (setq header-line-format
          (substitute-command-keys
           " ✦ Prompt for familiar-ask.  \\[familiar-ask-edit-send] send · \\[familiar-ask-edit-keep] keep for later"))))

(defun familiar-ask-edit-prompt ()
  "Move the prompt being typed into a buffer, like `org-edit-special'."
  (interactive)
  (let ((text (minibuffer-contents-no-properties)))
    (setq familiar-ask--draft text)
    (run-at-time 0 nil
                 (lambda ()
                   (pop-to-buffer (get-buffer-create "*familiar-ask prompt*"))
                   (erase-buffer)
                   (org-mode)
                   (insert (or familiar-ask--draft ""))
                   (familiar-ask-edit-mode 1)
                   (when (fboundp 'evil-insert-state) (evil-insert-state))))
    (abort-recursive-edit)))

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
