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

(defun dotfiles-elisp--main ()
  (let* ((args command-line-args-left)
         (args (if (and args (string= (car args) "--")) (cdr args) args))
         (command (car args))
         (files (or (cdr args) (dotfiles-elisp--default-files))))
    (pcase command
      ("format" (dotfiles-elisp-format files t))
      ("format-check" (dotfiles-elisp-format files nil))
      ("lint" (dotfiles-elisp-lint files))
      (_
       (princ "Usage: emacs --batch -Q -l scripts/elisp-qa.el -- <format|format-check|lint> [files...]\n")
       (kill-emacs 2)))))

(dotfiles-elisp--main)
