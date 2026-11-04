;;; lisp/+lsp-fallback.el --- LSP when the server exists, the rest when not -*- lexical-binding: t; -*-
;;
;; Doom's `lsp!' runs `eglot-ensure' for every buffer of a `+lsp' language.
;; When the language server isn't installed (no haskell-language-server here,
;; no Lean outside its `nix develop'), eglot still tries to launch it on the
;; first command in each such buffer and reports "[eglot] … Searching for
;; program: No such file or directory" every time.
;;
;; This makes the automatic start fall back instead: the server program is
;; looked up at connect time, after envrc has set the buffer's environment
;; (so per-project servers from `use flake' are found), and if it's missing
;; the buffer simply stays on tree-sitter, flycheck and friends.  One notice
;; per mode and program per session says so.  An explicit M-x eglot (or a
;; reconnect) is never intercepted and shows eglot's own error.
;;
;; Verified 2026-10-30 against eglot 1.24: `eglot-ensure' defers to
;; `post-command-hook', then calls (eglot--connect MODES PROJECT CLASS
;; CONTACT LANGUAGE-IDS) with CONTACT from `eglot--guess-contact'.
;;
;;; Code:

(defvar +lsp-fallback-explicit-commands '(eglot eglot-reconnect)
  "Commands that start a server on purpose; their attempts are never skipped.")

(defvar +lsp-fallback--noticed nil
  "(MODE . PROGRAM) pairs already reported this session.")

(defun +lsp-fallback-missing-program (contact)
  "The server program CONTACT would launch locally, if it can't be found.
CONTACT is eglot's (PROGRAM ARGS...) form; TCP (HOST PORT) contacts and
anything else return nil, as do remote directories (left to eglot)."
  (let ((program (car-safe contact)))
    (and (stringp program)
         (not (integerp (car-safe (cdr-safe contact)))) ; (HOST PORT)
         (not (file-remote-p default-directory))
         (not (executable-find program))
         program)))

(defun +lsp-fallback-connect-a (fn managed-modes project class contact language-ids)
  "Around `eglot--connect' (FN): skip automatic starts of missing servers.
MANAGED-MODES, PROJECT, CLASS, CONTACT and LANGUAGE-IDS as for FN."
  (let ((missing (and (not (memq this-command +lsp-fallback-explicit-commands))
                      (+lsp-fallback-missing-program contact))))
    (if (not missing)
        (funcall fn managed-modes project class contact language-ids)
      (let ((key (cons major-mode missing)))
        (unless (member key +lsp-fallback--noticed)
          (push key +lsp-fallback--noticed)
          (message "LSP off for %s: `%s' not found; tree-sitter, checkers and \
completion still work.  Install it (or enter its nix shell) and M-x eglot."
                   major-mode missing)))
      nil)))

(with-eval-after-load 'eglot
  (advice-add 'eglot--connect :around #'+lsp-fallback-connect-a))


;;;; Semantic tokens: the modifiers servers add beyond the standard
;;
;; eglot paints LSP semantic tokens (on wherever the server offers them:
;; here zls, rust-analyzer, nil), one face per token type and standard
;; modifier.  Servers add their own modifiers, and eglot ignores those it
;; has no face for: rust-analyzer's `mutable' (a binding that can change)
;; and `unsafe' (an unsafe operation) are the ones worth seeing at a glance,
;; as rust-analyzer's own VS Code client shows them.
(defface eglot-semantic-mutable '((t (:underline t)))
  "LSP semantic modifier `mutable': a binding that can change."
  :group 'eglot-semantic-faces)

(defface eglot-semantic-unsafe '((t (:inherit warning)))
  "LSP semantic modifier `unsafe': an unsafe operation."
  :group 'eglot-semantic-faces)

(defvar eglot-semantic-token-modifiers)
(with-eval-after-load 'eglot
  (dolist (modifier '("mutable" "unsafe"))
    (add-to-list 'eglot-semantic-token-modifiers modifier t)))

(provide '+lsp-fallback)
;;; +lsp-fallback.el ends here
