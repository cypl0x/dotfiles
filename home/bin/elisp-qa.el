;;; elisp-qa.el --- Elisp format/lint helpers for dotfiles  -*- lexical-binding: t; -*-

(defconst dotfiles-elisp-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun dotfiles-elisp--default-files ()
  (let ((root (expand-file-name "home/doom/lisp" dotfiles-elisp-root)))
    (if (file-directory-p root)
        (directory-files-recursively root "\\.el\\'")
      nil)))

(defun dotfiles-elisp--format-buffer ()
  (untabify (point-min) (point-max))
  (delete-trailing-whitespace)
  (goto-char (point-max))
  (unless (bolp)
    (insert "\n")))

(defun dotfiles-elisp--format-file (file write)
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (let ((orig (buffer-string)))
      (dotfiles-elisp--format-buffer)
      (cond
       (write
        (unless (string= orig (buffer-string))
          (write-region (point-min) (point-max) file)))
       (t
        (not (string= orig (buffer-string))))))))

(defun dotfiles-elisp-format (files &optional write)
  (let (changed)
    (dolist (file files)
      (when (dotfiles-elisp--format-file file write)
        (push file changed)))
    (when (and (not write) changed)
      (princ "Elisp formatting needed in:\n")
      (dolist (file (nreverse changed))
        (princ (concat "  " file "\n")))
      (kill-emacs 1))))

(defun dotfiles-elisp--check-parens (file)
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (condition-case _err
        (progn
          (check-parens)
          nil)
      (error t))))

(defun dotfiles-elisp-lint (files)
  (let (failed)
    (dolist (file files)
      (when (dotfiles-elisp--check-parens file)
        (push file failed)))
    (when failed
      (princ "Elisp lint failed (unbalanced parens):\n")
      (dolist (file (nreverse failed))
        (princ (concat "  " file "\n")))
      (kill-emacs 1))))

(defconst dotfiles-elisp-lambda-deny-list
  '(add-hook add-hook! advice-add run-at-time run-with-timer run-with-idle-timer))

(defconst dotfiles-elisp-lambda-deny-list-strict
  '(define-key global-set-key local-set-key))

(defun dotfiles-elisp--lambda-form-p (form)
  (and (consp form) (eq (car form) 'lambda)))

(defun dotfiles-elisp--forms-with-lambda (form)
  (let (hits)
    (dolist (arg (cdr form))
      (when (dotfiles-elisp--lambda-form-p arg)
        (push arg hits)))
    hits))

(defun dotfiles-elisp--check-no-anon (file deny-list)
  (let (violations)
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (condition-case _err
          (while t
            (let ((start (point))
                  (form (read (current-buffer))))
              (when (and (consp form)
                         (symbolp (car form))
                         (memq (car form) deny-list)
                         (dotfiles-elisp--forms-with-lambda form))
                (push (list (line-number-at-pos start) (car form)) violations))))
        (end-of-file nil)))
    violations))

(defun dotfiles-elisp-lint-no-anon (files &optional strict)
  "Lint for anonymous lambdas in sensitive forms.

Use STRICT to also flag anonymous lambdas in keybindings
(define-key/global-set-key/local-set-key)."
  (let* ((deny-list (append dotfiles-elisp-lambda-deny-list
                            (when strict dotfiles-elisp-lambda-deny-list-strict)))
         (failed nil))
    (dolist (file files)
      (let ((violations (dotfiles-elisp--check-no-anon file deny-list)))
        (when violations
          (push (cons file violations) failed))))
    (when failed
      (princ "Elisp lint failed (anonymous lambdas in sensitive forms):\n")
      (dolist (entry (nreverse failed))
        (let ((file (car entry))
              (violations (cdr entry)))
          (dolist (violation (nreverse violations))
            (princ (format "  %s:%d (%s)\n" file (nth 0 violation) (nth 1 violation))))))
      (kill-emacs 1))))

(defun dotfiles-elisp--main ()
  (let* ((args command-line-args-left)
         (args (if (and args (string= (car args) "--")) (cdr args) args))
         (command (car args))
         (files (or (cdr args) (dotfiles-elisp--default-files))))
    (pcase command
      ("format" (dotfiles-elisp-format files t))
      ("format-check" (dotfiles-elisp-format files nil))
      ("lint" (dotfiles-elisp-lint files))
      ("lint-no-anon" (dotfiles-elisp-lint-no-anon files nil))
      ("lint-no-anon-strict" (dotfiles-elisp-lint-no-anon files t))
      (_
       (princ "Usage: emacs --batch -Q -l home/bin/elisp-qa.el -- <format|format-check|lint|lint-no-anon|lint-no-anon-strict> [files...]\n")
       (kill-emacs 2)))))

(dotfiles-elisp--main)
