;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; ---------------------------------------------------------------------------
;; Identity
;; ---------------------------------------------------------------------------

(setq user-full-name "Wolfhard Prell"
      user-mail-address "mail@wolfhard.net")

;; ---------------------------------------------------------------------------
;; UI
;; ---------------------------------------------------------------------------

(setq doom-font (font-spec :family "Cascadia Code NF" :size 14))
(setq doom-theme 'doom-vibrant)
(setq display-line-numbers-type t)

;; Date/time in modeline
(setq display-time-format "%Y-%m-%d %H:%M"
      display-time-24hr-format t)
(display-time-mode 1)

;; ---------------------------------------------------------------------------
;; Org
;; ---------------------------------------------------------------------------

;; Must be set before org loads.
(setq org-directory "~/notes/")

;; ---------------------------------------------------------------------------
;; Keep the folding state
;; ---------------------------------------------------------------------------

(use-package! savefold
  :init
  (setq savefold-backends '(outline org markdown))
  (setq savefold-directory (locate-user-emacs-file "savefold"))  ;; default

  :config
  (savefold-mode 1))

;; ---------------------------------------------------------------------------
;; Editor
;; ---------------------------------------------------------------------------

;; Unbounded kill ring — never discard yanked text.
(setq kill-ring-max most-positive-fixnum)

;; Persist kill ring across restarts.
(after! savehist
  ;; Persist a very large kill-ring history across restarts.
  (setq savehist-length most-positive-fixnum)
  (add-to-list 'savehist-additional-variables 'kill-ring)
  (savehist-mode 1))

;; Kill-ring / clipboard UX
(setq save-interprogram-paste-before-kill t
      yank-pop-change-selection t
      kill-do-not-save-duplicates t)

(after! consult
  (map! "M-y" #'consult-yank-pop
        :leader
        "y" #'consult-yank-pop))

(after! vertico
  (map! :map vertico-map
        "C-j" #'vertico-next
        "C-k" #'vertico-previous
        "C-h" #'vertico-directory-up
        "C-l" #'vertico-insert))

(defun +vertico-preview-candidate ()
  "Show the current Vertico candidate in a read-only buffer."
  (interactive)
  (let* ((cand (when (fboundp 'vertico--candidate)
                 (vertico--candidate)))
         (text (if (stringp cand) (substring-no-properties cand) "")))
    (with-current-buffer (get-buffer-create "*Kill Ring Preview*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min))
        (view-mode 1))
      (display-buffer (current-buffer)))))

(after! vertico
  (map! :map vertico-map
        "C-c C-o" #'+vertico-preview-candidate))

;; Wrap long candidates in the minibuffer (useful for consult-yank-pop).
(add-hook 'minibuffer-setup-hook
          (lambda ()
            (setq truncate-lines nil
                  word-wrap t)))

;; Buffer cycling on German keyboard layout (ö/ä instead of [/]).
(map! "M-ö" #'previous-buffer
      "M-ä" #'next-buffer)

;; ---------------------------------------------------------------------------
;; Packages
;; ---------------------------------------------------------------------------

(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package! magit-delta
  :hook (magit-mode . magit-delta-mode)
  :config
  ;; --disable turns off line numbers inside delta hunks to avoid layout issues.
  (setq magit-delta-default-options '("--line-numbers" "--disable")))

(use-package! claude-code
  :config
  (global-set-key (kbd "C-c c") #'claude-code-transient)
  ;; Fall back to default-directory when not inside a Projectile project.
  (advice-add 'claude-code-run :around
    (lambda (orig-fn &rest args)
      (unless (projectile-project-root)
        (setq-local projectile-project-root default-directory))
      (apply orig-fn args))))

;; eat — terminal emulator in Eshell.
;; Provided by Nix (emacsPackages.eat); no package! declaration needed.
(after! eat
  (add-hook 'eshell-mode-hook #'eat-eshell-mode)
  (setq eat-term-name "xterm-256color"))

(with-eval-after-load 'eshell
  (load! "eshell/functions"))

;; ---------------------------------------------------------------------------
;; Language Server (LSP)
;; ---------------------------------------------------------------------------

(use-package! eglot-ltex
  :ensure t
  :hook (text-mode . (lambda ()
                       (require 'eglot-ltex)
                       (eglot-ensure)))
  :init
  ;; (setq eglot-ltex-server-path "path/to/ltex-ls-XX.X.X/"
  ;;       eglot-ltex-communication-channel 'stdio))
                                        ; 'stdio or 'tcp
)
;; ---------------------------------------------------------------------------
;; Universal app launcher (local lisp file)
;; ---------------------------------------------------------------------------

(load! "lisp/app-launcher")

;; ---------------------------------------------------------------------------
;; EXWM — only loaded when running as the window manager
;; SDDM sets DESKTOP_SESSION=exwm when the EXWM session is selected at login.
;; ---------------------------------------------------------------------------

(when (or (string= (getenv "DESKTOP_SESSION") "exwm")
          (string= (getenv "XDG_CURRENT_DESKTOP") "EXWM"))
  (load! "exwm"))

;; ---------------------------------------------------------------------------
;; Private config path override
;; SPC f p opens the dotfiles source instead of the read-only Nix store symlink.
;; ~/.config/doom/ is managed by home-manager; edits belong in ~/dotfiles/home/doom/.
;; ---------------------------------------------------------------------------

(defun doom/find-file-in-private-config ()
  "Browse the Doom config source in the dotfiles repository."
  (interactive)
  (doom-project-find-file (expand-file-name "~/dotfiles/home/doom/")))
