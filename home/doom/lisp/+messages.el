;;; lisp/+messages.el --- *Messages* that read like a log -*- lexical-binding: t; -*-
;;
;; The echo area's history (*Messages*, SPC h e) was plain text.  Now:
;;   - every line carries the time it arrived, shown in the margin of the
;;     line (a line prefix: the text itself is unchanged, so copying it,
;;     searching it and code reading it see what was said);
;;   - colors: [eglot]/[jsonrpc]-style source tags, errors and warnings,
;;     quoted Lisp names as functions or variables when they are ones (a
;;     small semantic pass: the name is looked up), keys (C-c C-c, SPC f r),
;;     numbers;
;;   - Org and Markdown inline markup rendered: ~code~ =verbatim= `code`
;;     *bold* /italic/ (the markers dimmed);
;;   - files and URLs are buttons (RET or click);
;;   - in the buffer: f shows only errors and warnings (occur), t toggles
;;     the times.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup +messages nil "*Messages* as a log." :group 'convenience)

(defcustom +messages-timestamp-format "%H:%M:%S "
  "How the time of a message shows (`format-time-string')."
  :type 'string)

(defface +messages-time '((t :inherit shadow))
  "The time before each message.")
(defface +messages-tag '((t :inherit font-lock-type-face :weight bold))
  "[source] tags at the start of a message.")
(defface +messages-marker '((t :inherit shadow))
  "Markup characters of rendered Org/Markdown.")

(defvar-local +messages-show-times t)

(defun +messages--stamp (beg end _len)
  "Give each new line between BEG and END its arrival time."
  (when (and +messages-show-times (> end beg))
    (let ((inhibit-read-only t)
          (prefix (propertize (format-time-string +messages-timestamp-format) 'face '+messages-time)))
      (with-silent-modifications
      (save-excursion
        (goto-char beg)
        (unless (bolp) (forward-line 1))
        (while (< (point) end)
          (let ((eol (min end (1+ (line-end-position)))))
            ;; A repeat ("[2 times]") rewrites the line: keep its first time.
            (unless (get-text-property (point) '+messages-time)
              (put-text-property (point) eol 'line-prefix prefix)
              (put-text-property (point) eol 'wrap-prefix (make-string (length prefix) ?\s))
              (put-text-property (point) eol '+messages-time t)))
          (forward-line 1)))))))

(defvar +messages--stamped nil "Marker: *Messages* is stamped up to here.")

(defvar +messages--stamping nil "Non-nil while stamping (no recursion through `message').")

(defun +messages--stamp-new (&rest _)
  "Give each line of *Messages* written since the last call its time.
Emacs writes there with modification hooks off, so this runs after each
`message' and, for what C code logs directly, once a second."
  ;; It runs inside `message': it must never signal (an error here is
  ;; reported with `message', which comes back here: it hung Emacs once).
  (unless +messages--stamping
    (let ((+messages--stamping t))
      (ignore-errors (+messages--stamp-new-1)))))

(defun +messages--stamp-new-1 ()
  (when-let* ((buf (get-buffer "*Messages*")))
    (with-current-buffer buf
      (unless (and (markerp +messages--stamped) (eq (marker-buffer +messages--stamped) buf))
        ;; From the line just logged (older lines keep no time: it would be wrong).
        (setq +messages--stamped (copy-marker (save-excursion (goto-char (point-max))
                                                             (skip-chars-backward "\n")
                                                             (line-beginning-position)))))
      (when (and +messages-show-times (< +messages--stamped (point-max)))
        (+messages--stamp (save-excursion (goto-char +messages--stamped) (line-beginning-position))
                          (point-max) 0))
      (set-marker +messages--stamped (point-max)))))

(defun +messages--lisp-name (limit)
  "Font-lock matcher: a quoted Lisp name (‘foo’ or `foo') that is defined."
  (let (found)
    (while (and (not found) (re-search-forward "[‘`]\\([^’'` \n]+\\)[’']" limit t))
      (when-let* ((sym (intern-soft (match-string 1))))
        (when (or (fboundp sym) (boundp sym) (facep sym))
          (setq found t))))
    found))

(defun +messages--lisp-face ()
  (let ((sym (intern-soft (match-string 1))))
    (cond ((and sym (fboundp sym)) 'font-lock-function-name-face)
          ((and sym (facep sym)) 'font-lock-type-face)
          (t 'font-lock-variable-name-face))))

(defconst +messages-keywords
  `(;; [eglot] Foo: source tags
    ("^\\(\\[[[:alnum:]-]+\\]\\)\\(?: (\\(warning\\|error\\))\\)?"
     (1 '+messages-tag) (2 (if (equal (match-string 2) "error") 'error 'warning) nil t))
    ("^\\(?:Error\\|error\\)[^\n]*\\|\\<\\(?:failed\\|Failed\\)\\>\\|^Debugger entered[^\n]*"
     0 'error t)
    ("^\\(?:Warning\\|warning\\)[^\n]*\\|\\<Wrong type argument\\>" 0 'warning t)
    ("\\[[0-9]+ times\\]" 0 'shadow t)
    (+messages--lisp-name 1 (+messages--lisp-face) t)
    ;; Keys: C-c C-c, M-x, SPC f r, <f5>
    ("\\(?:^\\|[ (“\"]\\)\\(\\(?:\\(?:[CMSsHA]-\\)+[^ \n,.)”\"]+\\|SPC\\(?: [[:alnum:]]\\)\\{1,3\\}\\|<[[:alnum:]-]+>\\)\\)" 1 'help-key-binding t)
    ;; Org ~code~ =verbatim=, Markdown `code`
    ("\\(?:^\\|[ (\"]\\)\\([~=`]\\)\\([^ ~=`\n][^~=`\n]*?\\)\\(\\1\\)"
     (1 '+messages-marker t) (2 (if (facep 'org-code) 'org-code 'font-lock-constant-face) t) (3 '+messages-marker t))
    ;; *bold* /italic/
    ("\\(?:^\\|[ (\"]\\)\\(\\*\\)\\([^ *\n][^*\n]*?\\)\\(\\*\\)" (1 '+messages-marker t) (2 'bold t) (3 '+messages-marker t))
    ("\\(?:^\\|[ (\"]\\)\\(/\\)\\([^ /\n][^/\n]*?\\)\\(/\\)[ .,;:!?)\"\n]" (1 '+messages-marker t) (2 'italic t) (3 '+messages-marker t))
    ("\\<[0-9]+\\(?:\\.[0-9]+\\)?\\(?: ?\\(?:ms\\|s\\|%\\|KiB\\|MiB\\|GiB\\|kB\\|MB\\|GB\\)\\)?\\>" 0 'font-lock-constant-face))
  "What *Messages* highlights.")

(defun +messages-errors ()
  "Only the errors and warnings of *Messages* (occur)."
  (interactive)
  (with-current-buffer (messages-buffer)
    (occur "^\\(?:\\[[[:alnum:]-]+\\] (\\(?:warning\\|error\\))\\|Error\\|error\\|Warning\\|warning\\|Debugger entered\\)\\|\\<failed\\>\\|\\<Wrong type argument\\>")))

(defun +messages-toggle-times ()
  "Show or hide the times."
  (interactive)
  (setq +messages-show-times (not +messages-show-times))
  (let ((inhibit-read-only t))
    (with-silent-modifications
      (if +messages-show-times
          (message "Times show for new messages")
        (remove-text-properties (point-min) (point-max) '(line-prefix nil wrap-prefix nil +messages-time nil))))))

(defun +messages-setup-h ()
  "Times, colors, buttons and keys in *Messages*."
  (font-lock-add-keywords nil +messages-keywords 'append)
  (setq-local font-lock-keywords-case-fold-search nil
              ;; A message with an odd " made everything after it a "string".
              font-lock-keywords-only t)
  (font-lock-mode 1)
  (goto-address-mode 1)
  ;; A keymap of its own: the mode's is shared by every buffer in it.
  (use-local-map (make-composed-keymap nil (current-local-map)))
  (local-set-key "f" #'+messages-errors)
  (local-set-key "t" #'+messages-toggle-times))

;; In evil's normal state too (where f and t are motions otherwise).
(map! :after evil :map messages-buffer-mode-map :n "f" #'+messages-errors :n "t" #'+messages-toggle-times)

(add-hook 'messages-buffer-mode-hook #'+messages-setup-h)
(advice-add 'message :after #'+messages--stamp-new)
(defvar +messages--timer (run-with-timer 1 1 #'+messages--stamp-new))
;; *Messages* exists before this file loads.
(when-let* ((buf (get-buffer "*Messages*")))
  (with-current-buffer buf
    (unless (memq 'goto-address-mode local-minor-modes)
      (+messages-setup-h))))

(provide '+messages)
;;; +messages.el ends here
