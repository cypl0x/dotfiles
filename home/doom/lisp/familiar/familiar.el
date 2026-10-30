;;; familiar.el --- An AI familiar woven into Emacs -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (gptel "0.9.9"))
;; Keywords: tools, convenience, vc
;; URL: https://github.com/cypl0x/familiar.el
;;
;;; Commentary:
;;
;; A familiar is the spirit that sits on your shoulder.  This one speaks LLM,
;; through gptel, but lives in the places you already work instead of in a
;; chat window:
;;
;;   `familiar-commit-message'      write the commit message for the staged diff,
;;                                  in the style of the repository's own history
;;   `familiar-explain'             explain region / defun / symbol, streamed
;;   `familiar-explain-diagnostic'  explain the flymake/flycheck error at point
;;   `familiar-fix'                 propose a fix as smerge conflict markers:
;;                                  keep, reject or edit with stock smerge keys
;;
;; Every request is priced from gptel's model table and the token counts the
;; API returns, appended to `familiar-ledger-file', and checked against
;; `familiar-budget'.  `familiar-mode-line-mode' shows the spend; `familiar-spend'
;; itemizes it.
;;
;; Cheap work goes to a cheap model: each task has a tier (see
;; `familiar-task-tiers'), and a prefix argument escalates one tier.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gptel)

(declare-function flymake-diagnostics "flymake")
(declare-function flymake-diagnostic-text "flymake")
(declare-function flymake-diagnostic-beg "flymake")
(declare-function flycheck-overlay-errors-at "ext:flycheck")
(declare-function flycheck-error-message "ext:flycheck")
(declare-function flycheck-error-line "ext:flycheck")
(declare-function smerge-mode "smerge-mode")
(declare-function gfm-view-mode "ext:markdown-mode")
(declare-function project-root "project")
(defvar flycheck-mode)
(defvar smerge-mode)


;;;; Customization

(defgroup familiar nil
  "An AI familiar woven into Emacs."
  :group 'tools
  :prefix "familiar-")

(defcustom familiar-models
  '((fast . claude-haiku-5-5)
    (smart . claude-sonnet-5-5)
    (deep . claude-opus-5-5))
  "Model for each tier, cheapest first.  A prefix argument escalates one tier."
  :type '(alist :key-type symbol :value-type symbol))

(defcustom familiar-task-tiers
  '((commit . fast) (explain . fast) (diagnostic . fast) (fix . smart))
  "Default tier for each task."
  :type '(alist :key-type symbol :value-type symbol))

(defcustom familiar-backend nil
  "gptel backend to use, or nil for the current `gptel-backend'."
  :type '(choice (const :tag "gptel-backend" nil) (sexp :tag "Backend")))

(defcustom familiar-budget 10.0
  "Spending budget in USD; nil for none."
  :type '(choice (const nil) number))

(defcustom familiar-budget-alerts '(0.5 0.8 0.95)
  "Fractions of `familiar-budget' at which to alert once."
  :type '(repeat number))

(defcustom familiar-ledger-file (locate-user-emacs-file "familiar-ledger.eld")
  "File recording every request: one Lisp list per line."
  :type 'file)

(defcustom familiar-context-lines 40
  "Lines of surrounding code to send when nothing narrower is selected."
  :type 'integer)

(defcustom familiar-commit-style-samples 20
  "Recent commit subjects shown to the model as the house style."
  :type 'integer)

(defcustom familiar-notify-function #'familiar-notify-desktop
  "Function called with TITLE and BODY for alerts (budget, failures)."
  :type 'function)


;;;; Pricing and the ledger

(defun familiar-cost (model tokens)
  "USD cost of TOKENS (gptel's :tokens plist) on MODEL, per gptel's model table.
Cache reads are billed at a tenth of the input price."
  (let ((in (or (get model :input-cost) 0))
        (out (or (get model :output-cost) 0)))
    (/ (+ (* in (or (plist-get tokens :input) 0))
          (* in 0.1 (or (plist-get tokens :cached) 0))
          (* out (or (plist-get tokens :output) 0)))
       1e6)))

(defun familiar--ledger ()
  "All ledger entries: (TIME MODEL TASK INPUT OUTPUT CACHED COST)."
  (when (file-readable-p familiar-ledger-file)
    (with-temp-buffer
      (insert-file-contents familiar-ledger-file)
      (let (entries)
        (condition-case nil
            (while t (push (read (current-buffer)) entries))
          (end-of-file nil))
        (nreverse entries)))))

(defvar familiar--spent nil "Cached total spend, or nil to recompute.")

(defun familiar-spent ()
  "Total USD spent according to the ledger."
  (or familiar--spent
      (setq familiar--spent
            (apply #'+ 0 (mapcar (lambda (e) (nth 6 e)) (familiar--ledger))))))

(defun familiar--record (model task tokens)
  "Append a ledger entry for TASK on MODEL with TOKENS; return its cost."
  (let* ((cost (familiar-cost model tokens))
         (before (familiar-spent))
         (entry (list (format-time-string "%FT%T%z") model task
                      (or (plist-get tokens :input) 0)
                      (or (plist-get tokens :output) 0)
                      (or (plist-get tokens :cached) 0)
                      cost)))
    (make-directory (file-name-directory familiar-ledger-file) t)
    (let ((print-length nil) (print-level nil))
      (write-region (concat (prin1-to-string entry) "\n") nil
                    familiar-ledger-file 'append 'silent))
    (setq familiar--spent (+ before cost))
    (familiar--check-budget before familiar--spent)
    (force-mode-line-update t)
    cost))

(defun familiar--check-budget (before after)
  "Alert for each budget fraction crossed going from BEFORE to AFTER."
  (when familiar-budget
    (dolist (f familiar-budget-alerts)
      (let ((mark (* f familiar-budget)))
        (when (and (< before mark) (>= after mark))
          (funcall familiar-notify-function
                   (format "familiar: %d%% of budget used" (round (* 100 f)))
                   (format "$%.4f of $%.2f spent" after familiar-budget)))))))

(defun familiar-notify-desktop (title body)
  "Show TITLE and BODY as a desktop notification, falling back to `message'."
  (message "%s — %s" title body)
  (when (executable-find "notify-send")
    (call-process "notify-send" nil 0 nil "-a" "Emacs · familiar" title body)))


;;;; Mode line

(defun familiar--mode-line ()
  (when familiar-budget
    (let ((spent (familiar-spent)))
      (propertize (format (if (< spent 1) " ✦$%.3f" " ✦$%.2f") spent)
                  'face (cond ((>= spent (* 0.8 familiar-budget)) 'error)
                              ((>= spent (* 0.5 familiar-budget)) 'warning)
                              (t 'shadow))
                  'help-echo (format "familiar: $%.4f of $%.2f spent — mouse-1: details"
                                     spent familiar-budget)
                  'local-map (make-mode-line-mouse-map 'mouse-1 #'familiar-spend)))))

(defconst familiar--mode-line-construct '(:eval (familiar--mode-line)))

;;;###autoload
(define-minor-mode familiar-mode-line-mode
  "Show familiar's spend in the mode line."
  :global t
  (if familiar-mode-line-mode
      (add-to-list 'global-mode-string familiar--mode-line-construct t)
    (setq global-mode-string
          (delete familiar--mode-line-construct global-mode-string))))

;;;###autoload
(defun familiar-spend ()
  "Show every request familiar made, newest first, with totals."
  (interactive)
  (let ((entries (reverse (familiar--ledger))))
    (with-current-buffer (get-buffer-create "*familiar spend*")
      (tabulated-list-mode)
      (setq tabulated-list-format
            [("When" 20 t) ("Task" 11 t) ("Model" 20 t)
             ("In" 8 t :right-align t) ("Out" 7 t :right-align t)
             ("Cached" 7 t :right-align t) ("USD" 9 t :right-align t)])
      (setq tabulated-list-entries
            (cl-loop for e in entries for i from 0
                     collect (list i (vector (substring (nth 0 e) 0 19)
                                             (format "%s" (nth 2 e))
                                             (format "%s" (nth 1 e))
                                             (number-to-string (nth 3 e))
                                             (number-to-string (nth 4 e))
                                             (number-to-string (nth 5 e))
                                             (format "%.5f" (nth 6 e))))))
      (setq header-line-format
            (format " %d requests · $%.4f spent%s"
                    (length entries) (familiar-spent)
                    (if familiar-budget
                        (format " of $%.2f (%.1f%%)" familiar-budget
                                (* 100 (/ (familiar-spent) familiar-budget)))
                      "")))
      (tabulated-list-init-header)
      (tabulated-list-print)
      (pop-to-buffer (current-buffer)))))


;;;; Requests

(defun familiar--model (task &optional escalate)
  "Model for TASK, one tier up when ESCALATE."
  (let* ((tiers (mapcar #'car familiar-models))
         (tier (or (alist-get task familiar-task-tiers) 'fast))
         (pos (or (cl-position tier tiers) 0)))
    (when escalate (setq pos (min (1+ pos) (1- (length tiers)))))
    (alist-get (nth pos tiers) familiar-models)))

(cl-defun familiar-request (prompt &key task system escalate stream callback)
  "Send PROMPT for TASK with SYSTEM prompt; call CALLBACK like `gptel-request'.
The model comes from TASK's tier (one higher when ESCALATE).  The request is
priced and recorded once it completes.  Returns the model used."
  (let* ((model (familiar--model task escalate))
         (gptel-backend (or familiar-backend gptel-backend))
         (gptel-model model)
         (gptel-use-tools nil)
         (gptel-use-context nil))
    (gptel-request prompt
      :system system
      :stream stream
      :callback
      (lambda (response info)
        (when (or (eq response t) (and (stringp response) (not stream)))
          (when-let* ((tokens (plist-get info :tokens)))
            (familiar--record model task tokens)))
        (when (null response)
          (funcall familiar-notify-function "familiar: request failed"
                   (or (plist-get info :status) "no response")))
        (funcall callback response info)))
    model))


;;;; Context

(defun familiar--project-name ()
  (when-let* ((pr (project-current)))
    (file-name-nondirectory (directory-file-name (project-root pr)))))

(defun familiar--target-bounds ()
  "Region, else the defun at point, else `familiar-context-lines' around point."
  (cond ((use-region-p) (cons (region-beginning) (region-end)))
        ((bounds-of-thing-at-point 'defun))
        (t (save-excursion
             (let ((half (/ familiar-context-lines 2)))
               (cons (progn (forward-line (- half)) (line-beginning-position))
                     (progn (forward-line familiar-context-lines)
                            (line-end-position))))))))

(defun familiar--describe-location (beg)
  (format "%s (%s, line %d%s)"
          (if buffer-file-name (file-name-nondirectory buffer-file-name) (buffer-name))
          (string-remove-suffix "-mode" (symbol-name major-mode))
          (line-number-at-pos beg)
          (if-let* ((p (familiar--project-name))) (format ", project %s" p) "")))

(defun familiar--fenced (text)
  (format "```%s\n%s\n```" (string-remove-suffix "-mode" (symbol-name major-mode)) text))

(defun familiar--unfence (text)
  "Strip a single surrounding Markdown code fence from TEXT, if any."
  (let ((s (string-trim text)))
    (if (string-match "\\````[^\n]*\n\\(\\(?:.\\|\n\\)*?\\)\n?```\\'" s)
        (match-string 1 s)
      s)))

(defun familiar--diagnostics-at-point ()
  "Messages of the flymake or flycheck diagnostics at point."
  (or (and (bound-and-true-p flycheck-mode)
           (mapcar #'flycheck-error-message (flycheck-overlay-errors-at (point))))
      (and (bound-and-true-p flymake-mode)
           (mapcar #'flymake-diagnostic-text (flymake-diagnostics (point))))))


;;;; Output buffer

(defun familiar--output-buffer (title)
  "Fresh read-only buffer for a streamed answer about TITLE."
  (let ((buf (get-buffer-create "*familiar*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (fboundp 'gfm-view-mode) (gfm-view-mode) (special-mode))
        (setq header-line-format (format " ✦ %s" title))))
    (display-buffer buf)
    buf))

(defun familiar--stream-into (buf)
  "Callback streaming a response into BUF."
  (lambda (response info)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (cond ((stringp response)
                 (save-excursion (goto-char (point-max)) (insert response)))
                ((eq response t)
                 (setq header-line-format
                       (concat header-line-format
                               (when-let* ((tk (plist-get info :tokens)))
                                 (format "  ·  %s in / %s out"
                                         (plist-get tk :input) (plist-get tk :output)))))
                 (force-mode-line-update))
                ((null response)
                 (save-excursion
                   (goto-char (point-max))
                   (insert (format "\n\n[request failed: %s]" (plist-get info :status)))))))))))


;;;; Explain

(defconst familiar--explain-system
  "You are an expert pair programmer embedded in the user's editor. Explain \
concisely and concretely: what the code does, why, and anything surprising or \
wrong. Use Markdown. No preamble.")

;;;###autoload
(defun familiar-explain (&optional escalate)
  "Explain the region, the defun at point, or the code around point.
With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
               (where (familiar--describe-location beg))
               (code (buffer-substring-no-properties beg end))
               (buf (familiar--output-buffer (concat "Explain " where))))
    (deactivate-mark)
    (familiar-request (format "Explain this code from %s:\n\n%s" where (familiar--fenced code))
                      :task 'explain :escalate escalate :stream t
                      :system familiar--explain-system
                      :callback (familiar--stream-into buf))))

;;;###autoload
(defun familiar-explain-diagnostic (&optional escalate)
  "Explain the flymake/flycheck diagnostic at point, in context.
With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (let ((diags (or (familiar--diagnostics-at-point)
                   (user-error "No diagnostic at point"))))
    (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
                 (where (familiar--describe-location (point)))
                 (buf (familiar--output-buffer (concat "Diagnostic in " where))))
      (familiar-request
       (format "In %s the checker reports:\n%s\n\nThe code (point is on line %d):\n\n%s\n\n\
Explain the cause and how to fix it."
               where (mapconcat (lambda (d) (concat "- " d)) diags "\n")
               (line-number-at-pos) (familiar--fenced (buffer-substring-no-properties beg end)))
       :task 'diagnostic :escalate escalate :stream t
       :system familiar--explain-system
       :callback (familiar--stream-into buf)))))


;;;; Fix: proposals as smerge conflicts

(defconst familiar--fix-system
  "You rewrite code. Reply with ONLY the complete replacement for the given \
code, no explanation, no Markdown fences. Keep everything that needs no change \
exactly as it is, including indentation and comments.")

(defun familiar--propose (buf beg end replacement)
  "Show REPLACEMENT for BEG..END of BUF as an smerge conflict and enable smerge."
  (with-current-buffer buf
    (let ((original (buffer-substring-no-properties beg end)))
      (if (string= (string-trim original) (string-trim replacement))
          (message "familiar: no change proposed")
        (undo-boundary)
        (save-excursion
          (goto-char beg)
          (delete-region beg end)
          (insert "<<<<<<< current\n" original
                  (if (string-suffix-p "\n" original) "" "\n")
                  "=======\n" replacement
                  (if (string-suffix-p "\n" replacement) "" "\n")
                  ">>>>>>> familiar\n"))
        (undo-boundary)
        (smerge-mode 1)
        (goto-char beg)
        (message "familiar: proposal inserted; keep it with %s, reject with %s"
                 (substitute-command-keys "\\[smerge-keep-lower]")
                 (substitute-command-keys "\\[smerge-keep-upper]"))))))

;;;###autoload
(defun familiar-fix (instruction &optional escalate)
  "Ask for a fix of the region or defun at point, following INSTRUCTION.
The proposal appears inline as smerge conflict markers.  Defaults to fixing
the diagnostics at point.  With prefix arg ESCALATE, use the next model tier."
  (interactive
   (let ((diags (familiar--diagnostics-at-point)))
     (list (read-string "Fix: " (when diags (concat "Fix: " (string-join diags "; "))))
           current-prefix-arg)))
  (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
               (buf (current-buffer))
               (beg (copy-marker beg))
               (end (copy-marker end t))
               (where (familiar--describe-location beg)))
    (deactivate-mark)
    (message "familiar: thinking about %s…" where)
    (familiar-request
     (format "%s\n\nCode from %s:\n\n%s" instruction where
             (familiar--fenced (buffer-substring-no-properties beg end)))
     :task 'fix :escalate escalate :system familiar--fix-system
     :callback (lambda (response _info)
                 (when (stringp response)
                   (familiar--propose buf beg end (familiar--unfence response)))))))


;;;; Commit messages

(defconst familiar--commit-system
  "You write git commit messages. Follow the repository's style exactly as \
shown by its recent subjects (e.g. Conventional Commits, scopes, casing, \
language). Subject at most 72 characters, imperative. Add a body, wrapped at \
72, only when the why is not obvious from the subject. Reply with only the \
message.")

(defun familiar--git (&rest args)
  (with-temp-buffer
    (when (zerop (apply #'process-file "git" nil t nil args))
      (buffer-string))))

;;;###autoload
(defun familiar-commit-message (&optional escalate)
  "Write the commit message for the staged changes into this buffer.
Meant for git-commit buffers (magit's COMMIT_EDITMSG).  With prefix arg
ESCALATE, use the next model tier."
  (interactive "P")
  (let ((diff (familiar--git "diff" "--cached" "--stat" "--patch" "--no-color"
                             "--no-ext-diff"))
        (style (familiar--git "log" "-n" (number-to-string familiar-commit-style-samples)
                              "--format=%s"))
        (buf (current-buffer)))
    (when (string-empty-p (string-trim (or diff "")))
      (user-error "Nothing staged"))
    (message "familiar: writing commit message…")
    (familiar-request
     (format "Recent commit subjects (house style):\n%s\nStaged diff:\n%s"
             (or style "") diff)
     :task 'commit :escalate escalate :system familiar--commit-system
     :callback (lambda (response _info)
                 (when (and (stringp response) (buffer-live-p buf))
                   (with-current-buffer buf
                     (save-excursion
                       (goto-char (point-min))
                       (insert (string-trim (familiar--unfence response)) "\n"))
                     (message "familiar: message written")))))))

(provide 'familiar)
;;; familiar.el ends here
