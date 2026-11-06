;;; lisp/+where.el --- Where you are, in the header line: project › file › function or heading -*- lexical-binding: t; -*-
;;
;; In code and Org, the window's top line names where point is:
;;
;;   dotfiles › home/doom/lisp/+nav.el › +buffer/reopen-closed
;;   vault › mess.org › Quality of life, round 3 › 7. Where you are
;;
;; The function comes from tree-sitter where the buffer has a parser, else
;; from the mode's own defun finder (add-log); in Org the outline path.
;; Worked out when Emacs is idle, for the window you are in only.
;; SPC t h turns it off and on.
;;
;;; Code:

(require 'subr-x)
(require 'project)

(declare-function org-get-outline-path "org" (&optional with-self use-cache))
(declare-function org-before-first-heading-p "org" ())
(declare-function treesit-add-log-current-defun "treesit" ())
(declare-function treesit-parser-list "treesit.c" (&optional buffer language tag))

(defcustom +where-modes '(prog-mode org-mode conf-mode)
  "Major modes (and those derived from them) with a where-you-are line."
  :type '(repeat symbol) :group 'convenience)

(defvar-local +where--text nil "This buffer's where-you-are line.")

(defun +where--defun ()
  "The name of the definition at point, or nil."
  (ignore-errors
    (if (and (fboundp 'treesit-parser-list) (treesit-parser-list)
             (fboundp 'treesit-add-log-current-defun))
        (or (treesit-add-log-current-defun) (add-log-current-defun))
      (add-log-current-defun))))

(defun +where--inside ()
  "Where in the file point is: Org's heading path, else the definition."
  (if (derived-mode-p 'org-mode)
      (and (not (org-before-first-heading-p))
           ;; Not its cache: it is by position and mixed up two buffers.
           (let ((path (ignore-errors (org-get-outline-path t))))
             (and path (string-join (mapcar #'substring-no-properties path) " › "))))
    (+where--defun)))

(defun +where-line ()
  "This buffer's line: project › file › inside, the last part bold."
  (let* ((file (buffer-file-name (buffer-base-buffer)))
         ;; No project lookup over TRAMP: it can freeze (+perf.el).
         (root (and file (not (file-remote-p file)) (ignore-errors (project-root (project-current)))))
         (project (and root (file-name-nondirectory (directory-file-name root))))
         (rel (and file (if root (file-relative-name file root)
                          ;; Outside a project (a /nix/store source): its last parts.
                          (let ((parts (split-string (abbreviate-file-name file) "/" t)))
                            (string-join (last parts 3) "/")))))
         (inside (+where--inside))
         (parts (delq nil (list (and project (propertize project 'face 'shadow))
                                (and rel (propertize rel 'face (if inside 'shadow 'bold)))
                                (and inside (propertize inside 'face 'bold))))))
    (concat " " (string-join parts (propertize " › " 'face 'shadow)))))

(defun +where--update ()
  "Work out the line for the selected window's buffer."
  (when (and (bound-and-true-p +where-mode) (local-variable-p 'header-line-format)
             (equal header-line-format '(:eval +where--text)))
    (let ((new (+where-line)))
      (unless (equal new +where--text)
        (setq +where--text new)
        (force-mode-line-update)))))

(defvar +where--timer nil)

(define-minor-mode +where-mode
  "Where point is (project › file › function or heading) in the header line."
  :global t :group 'convenience
  (when (timerp +where--timer) (cancel-timer +where--timer))
  (setq +where--timer (and +where-mode (run-with-idle-timer 0.3 t #'+where--update)))
  (dolist (buf (buffer-list))
    (with-current-buffer buf (+where--setup-h))))

(defun +where--setup-h ()
  "This buffer's header line, on or off as `+where-mode' says."
  (if (and +where-mode (apply #'derived-mode-p +where-modes) (buffer-file-name (buffer-base-buffer)))
      (progn (setq-local header-line-format '(:eval +where--text))
             (setq +where--text (ignore-errors (+where-line))))
    (when (equal header-line-format '(:eval +where--text))
      (kill-local-variable 'header-line-format))))

(add-hook 'after-change-major-mode-hook #'+where--setup-h)

(map! :leader :desc "Where you are (header line)" "t h" #'+where-mode)

(+where-mode 1)

(provide '+where)
;;; +where.el ends here
