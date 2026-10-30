;;; test/shims.el --- Minimal Doom stand-ins for testing lisp/ in `emacs -Q' -*- lexical-binding: t; -*-
;;
;; Private modules use a handful of Doom macros at top level. Under Doom the
;; real ones are already defined, so every shim here is a no-op there.
;;
;;; Code:

(defvar doom-emacs-dir (expand-file-name "~/.config/emacs/"))
(defvar org-directory (make-temp-file "doom-test-org" t))

(unless (fboundp 'map!)
  (defmacro map! (&rest _) "Ignore keybindings in tests." nil))
(unless (fboundp 'after!)
  (defmacro after! (package &rest body)
    "Run BODY once PACKAGE (a symbol) is loaded."
    `(with-eval-after-load ',package ,@body)))
(unless (fboundp 'doom-session-file)
  (defun doom-session-file (&optional name)
    (expand-file-name (or name "autosave") temporary-file-directory)))
(unless (fboundp 'doom-save-session)
  (defun doom-save-session (&optional _file) nil))

;; Let tests use real third-party packages from Doom's build when present.
(let ((build (car (file-expand-wildcards
                   (expand-file-name (concat ".local/straight/build-" emacs-version)
                                     doom-emacs-dir)))))
  (when build
    (dolist (pkg '("gptel" "transient" "compat" "cond-let" "llama"))
      (let ((dir (expand-file-name pkg build)))
        (when (file-directory-p dir) (add-to-list 'load-path dir))))))

(provide 'shims)
;;; shims.el ends here
