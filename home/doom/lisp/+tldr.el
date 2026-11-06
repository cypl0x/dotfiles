;;; lisp/+tldr.el --- What is this command and how do I use it, in Emacs -*- lexical-binding: t; -*-
;;
;; Built from atuin evidence (2026-10-30, all 1,993 commands on the thinkpad):
;;   tldr <cmd>                        78×
;;   man <cmd> (GROFF_NO_SGR=1 man …)  58×
;;   which -a <cmd>                    56×
;; all three are the same question.  SPC h X answers it in one buffer: which
;; executables the name resolves to (through /run/current-system and the
;; store), the tldr examples, and a button for the man page.
;;
;; The pages are read from tealdeer's own cache (the `tldr' you already run),
;; so this needs no package, no network and no subprocess.  The cache is
;; never updated from here: the connection is metered; `tldr --update' is
;; yours to run.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'button)

(defvar +tldr-pages-dir
  (expand-file-name "tealdeer/tldr-pages/pages.en/"
                    (or (getenv "XDG_CACHE_HOME") (expand-file-name "~/.cache")))
  "tealdeer's English pages: one directory per platform, one .md per command.")

(defvar +tldr-platforms '("linux" "common")
  "Platform directories searched, in order of preference.")

(defun +tldr-page-file (command)
  "The cached tldr page for COMMAND, or nil."
  (cl-loop for platform in +tldr-platforms
           for file = (expand-file-name (concat platform "/" command ".md")
                                        +tldr-pages-dir)
           when (file-readable-p file) return file))

(defun +tldr-commands ()
  "Names of all cached pages for `+tldr-platforms'."
  (delete-dups
   (cl-loop for platform in +tldr-platforms
            for dir = (expand-file-name platform +tldr-pages-dir)
            when (file-directory-p dir)
            append (mapcar #'file-name-base (directory-files dir nil "\\.md\\'")))))

(defun +tldr-which (command)
  "Every executable named COMMAND on `exec-path', like `which -a'.
Each element is (PATH . TRUENAME); TRUENAME differs when PATH is a link,
e.g. into the store."
  (let (seen)
    (dolist (dir exec-path)
      (let ((file (and dir (expand-file-name command dir))))
        (when (and file (file-executable-p file) (not (file-directory-p file))
                   (not (assoc file seen)))
          (push (cons file (file-truename file)) seen))))
    (nreverse seen)))

(defun +tldr--command-at-point ()
  "A command name at point: the symbol, else the first word of the line."
  (let ((pages (+tldr-commands)))
    (cl-find-if (lambda (s) (and s (member s pages)))
                (list (thing-at-point 'symbol t)
                      (save-excursion
                        (goto-char (line-beginning-position))
                        ;; Skip a shell prompt such as "$ " or "❯ ".
                        (skip-chars-forward "^[:alnum:]")
                        (thing-at-point 'symbol t))))))

(defun +tldr-example-at-point ()
  "The example command on the current line of a tldr page, without backticks."
  (save-excursion
    (goto-char (line-beginning-position))
    (when (looking-at "^`\\(.+\\)`$")
      (match-string-no-properties 1))))

(defun +tldr/copy-example ()
  "Copy the example command on this line, {{placeholders}} and all."
  (interactive)
  (if-let* ((cmd (+tldr-example-at-point)))
      (progn (kill-new cmd) (message "Copied: %s" cmd))
    (user-error "No example command on this line")))

(defvar-keymap +tldr-mode-map
  :parent special-mode-map
  "RET" #'+tldr/copy-example
  "y" #'+tldr/copy-example
  "K" #'+tldr/man
  "e" #'+tldr/explain)

;; Evil's normal state would shadow these with yank and lookup; same
;; meanings here, for the example line and the command.
(map! :map +tldr-mode-map
      :n "y" #'+tldr/copy-example
      :n "RET" #'+tldr/copy-example
      :n "K" #'+tldr/man
      :n "e" #'+tldr/explain)

(define-derived-mode +tldr-mode special-mode "tldr"
  "Major mode for a command's executables, tldr examples and man page."
  (setq-local font-lock-defaults
              '((("^# .*" . 'outline-1)
                 ("^> .*" . 'font-lock-doc-face)
                 ("^- .*" . 'font-lock-comment-face)
                 ("{{[^}]*}}" 0 'font-lock-variable-name-face prepend)
                 ("^`.*`$" . 'font-lock-string-face))
                t)))

(defvar-local +tldr--command nil)
(defvar-local +tldr--line nil "The command line SPC h X was asked from.")

(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin))

(defun +tldr/explain ()
  "Ask the assistant to explain this buffer's command line, part by part."
  (interactive)
  (familiar-ask
   (format "Explain this shell command part by part (each flag, each pipe), briefly, then say whether anything in it is risky:\n%s"
           (or +tldr--line (user-error "No command line here: SPC h X from a line with one")))
   t))

(defun +tldr/man ()
  "Open the man page of this buffer's command."
  (interactive)
  (man +tldr--command))

;;;###autoload
(defun +tldr--line-at-point ()
  "The shell command line at point (the region, else the line without its
prompt), or nil when it is no more than one word."
  (let ((line (string-trim
               (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (save-excursion
                   (goto-char (line-beginning-position))
                   (skip-chars-forward "^[:alnum:]/.~")
                   (buffer-substring-no-properties (point) (line-end-position)))))))
    (and (string-match-p "[ \t]" line) line)))

(defun +tldr/lookup (command &optional line)
  "Show COMMAND's executables (`which -a'), its tldr examples and its man page.
LINE, the whole command line it was asked from, shows at the top: e asks
the assistant to explain it part by part.
In the buffer: y or RET copies the example on the line, K opens the man page."
  (interactive
   (let ((default (+tldr--command-at-point))
         (line (+tldr--line-at-point)))
     (list (completing-read (format-prompt "Command" default)
                            (+tldr-commands) nil nil nil nil default)
           line)))
  (when (string-empty-p command) (user-error "No command"))
  (let ((buf (get-buffer-create (format "*tldr: %s*" command)))
        (page (+tldr-page-file command))
        (bins (+tldr-which command)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (+tldr-mode)
        (setq +tldr--command command
              +tldr--line line)
        (if bins
            (dolist (b bins)
              (insert "which: " (car b))
              (unless (equal (car b) (cdr b)) (insert "\n    → " (cdr b)))
              (insert "\n"))
          (insert "which: not on PATH (try SPC h X in a `nix shell')\n"))
        (insert-text-button "[man page]" 'action (lambda (_) (+tldr/man)) 'follow-link t)
        (insert "  y/RET: copy example · K: man · q: quit\n")
        (when line
          (insert "Your line: " (propertize line 'face 'font-lock-string-face) "  ")
          (insert-text-button "[explain it]" 'action (lambda (_) (+tldr/explain)) 'follow-link t)
          (insert " (e)\n"))
        (insert "\n")
        (if page
            (insert-file-contents page)
          (insert (format "No tldr page for %s in %s.\n\
The cache may be old: run `tldr --update' when you're not on the metered link.\n"
                          command +tldr-pages-dir)))
        (goto-char (point-min))
        (when page (re-search-forward "^`" nil t) (goto-char (line-beginning-position)))))
    (pop-to-buffer buf)))

(map! :leader :desc "Command examples (tldr)" "h X" #'+tldr/lookup)

(provide '+tldr)
;;; +tldr.el ends here
