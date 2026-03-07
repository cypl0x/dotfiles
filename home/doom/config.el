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
;; Editor
;; ---------------------------------------------------------------------------

;; Unbounded kill ring — never discard yanked text.
(setq kill-ring-max most-positive-fixnum)

;; Persist kill ring across restarts.
(after! savehist
  (add-to-list 'savehist-additional-variables 'kill-ring))

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
