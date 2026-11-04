;;; familiar-ask.el --- Ask anything, from anywhere in Emacs -*- lexical-binding: t; -*-
;;
;; One key (C-M-? by default) from any buffer, including the minibuffer and
;; buffers that visit no file, asks a long-lived conversation.  What you were
;; looking at goes along as context, so you never restate it; tools let the
;; model look around Emacs itself and act in it, the way you would (edits are
;; undoable, nothing is written to disk unless you ask for it).
;;
;;   C-M-?            ask (in the minibuffer too: "exclude tests" in M-x)
;;   C-u C-M-?        ask in a fresh conversation
;;   C-c '  (prompt)  edit the prompt in a buffer; C-c C-c sends, C-c C-k keeps it
;;   @fast/@smart/@deep in the prompt picks the model (gptel presets)
;;   C-r  (prompt)    pick an earlier prompt
;;   RET / S-RET      in the conversation: send a follow-up / newline
;;   C-c C-e          copy the conversation as Markdown or Org
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

(defcustom familiar-ask-context-lines 30
  "Lines around point sent along when there is no region or defun."
  :type 'natnum :group 'familiar)

(defcustom familiar-ask-system
  "You are familiar, an assistant living inside the user's Emacs (Doom Emacs \
with evil, vertico and orderless; Emacs 32).  Each user message ends with a \
#+begin_context block describing where they were when they asked: buffer, \
modes, point, region, nearby text, minibuffer.  Treat it as the subject of \
the question; the user won't restate it.  Your tools inspect Emacs and act \
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

Reply in Org markup (this conversation is an Org buffer): ~code~ inline, \
#+begin_src blocks with the language.  Lead with the answer; be brief."
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
           (when-let* ((mb (plist-get origin :minibuffer)))
             (and (buffer-live-p mb) (familiar-ask--minibuffer-context mb)))
           (format "Other windows: %s\n"
                   (string-join (delete-dups
                                 (mapcar (lambda (w) (buffer-name (window-buffer w)))
                                         (window-list (selected-frame) 'nomini)))
                                ", "))
           (format "%s, lines %d-%d:\n"
                   (if region "Region" "Around point")
                   (line-number-at-pos (car bounds)) (line-number-at-pos (cdr bounds)))
           (format "#+begin_src %s\n%s\n#+end_src\n" lang
                   (string-trim-right
                    (org-escape-code-in-string
                     (buffer-substring-no-properties (car bounds) (cdr bounds)))))
           "#+end_context"))))))

;;;; Tools

(defun familiar-ask--get-buffer (name)
  (or (get-buffer name) (error "No buffer named %s" name)))

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
    :name "set_minibuffer" :category "familiar"
    :description "Replace the input of the minibuffer the user asked from (e.g. write orderless syntax into an M-x prompt). Only when the context shows an active minibuffer."
    :args '((:name "text" :type string :description "New minibuffer input"))
    :function (lambda (text)
                (let ((mb (plist-get familiar-ask--origin :minibuffer)))
                  (unless (and mb (buffer-live-p mb) (minibufferp mb))
                    (error "No minibuffer to write into"))
                  (with-current-buffer mb
                    (delete-minibuffer-contents)
                    (insert text))
                  (when-let* ((win (get-buffer-window mb t)))
                    (with-selected-window win
                      (when (bound-and-true-p vertico-mode) (vertico--exhibit))))
                  (format "Minibuffer input is now %S" text)))))
  "Tools `familiar-ask' offers the model.")

;;;; The conversation buffer

(defvar familiar-ask-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'familiar-ask-ret)
    (define-key map (kbd "<S-return>") #'newline)
    (define-key map (kbd "C-c C-k") #'gptel-abort)
    (define-key map (kbd "C-c C-e") #'familiar-ask-export)
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
  (format " ✦ familiar-ask  ·  %s  ·  %d prompts  ·  $%.4f%s"
          gptel-model
          (how-many "^\\*\\* ." (point-min) (point-max))
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
    ;; First: turning it on restores saved state, which would undo the below.
    (gptel-mode 1)
    (setq-local gptel-model (alist-get familiar-ask-tier familiar-models)
                gptel-backend (or familiar-backend gptel-backend)
                gptel-system-prompt familiar-ask-system
                gptel-tools familiar-ask-tools
                gptel-use-tools t
                gptel-cache t
                gptel-include-tool-results 'auto
                ;; Shown, it's mostly empty blocks; the answer is what matters.
                gptel-include-reasoning nil
                gptel-prompt-prefix-alist '((org-mode . "** "))
                gptel-response-prefix-alist '((org-mode . "")))
    (familiar-ask-mode 1)
    (add-hook 'gptel-post-response-functions #'familiar-ask--after-response nil t)
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
  "Save the conversation and leave a fresh prompt heading."
  ;; Runs after every turn, tool turns included: one prompt heading only.
  (save-excursion
    (goto-char (point-max))
    (unless (re-search-backward "^\\*\\* *\\=" (line-beginning-position 0) t)
      (skip-chars-backward " \t\n")
      (delete-region (point) (point-max))
      (insert "\n\n** ")))
  (let ((save-silently t) (inhibit-message t)) (save-buffer)))

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
(defun familiar-ask (prompt &optional new)
  "Ask PROMPT about where you are, in the running conversation.
With prefix arg NEW, start a fresh conversation."
  (interactive
   (progn (setq familiar-ask--origin (familiar-ask--capture))
          (list (familiar-ask--read) current-prefix-arg)))
  (when (string-blank-p prompt) (user-error "Empty prompt"))
  (let* ((origin (or familiar-ask--origin (familiar-ask--capture)))
         (context (familiar-ask--context origin))
         (buf (if (or new (not (get-buffer familiar-ask--buffer-name)))
                  (familiar-ask--new-buffer)
                (get-buffer familiar-ask--buffer-name))))
    (setq familiar-ask--origin origin)
    (with-current-buffer buf
      (goto-char (point-max))
      (unless (looking-back "^\\*\\* " (line-beginning-position))
        (unless (bolp) (insert "\n"))
        (insert "\n** "))
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
    (familiar-ask (format "%s\n\n(Prompt written in %s.)" text mode))))

(defun familiar-ask-edit-keep ()
  "Close the prompt buffer; the next `familiar-ask' starts with its text."
  (interactive)
  (setq familiar-ask--draft (string-trim (buffer-string)))
  (quit-window t)
  (message "Prompt kept; C-M-? brings it back"))

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
      (goto-char (point-min))
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
