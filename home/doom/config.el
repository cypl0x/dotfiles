;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

(setq user-full-name "Wolfhard Prell"
      user-mail-address "mail@wolfhard.net")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))

(setq doom-font (font-spec :family "Cascadia Code NF" :size 14))
;; (setq doom-font (font-spec :size 20))

;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-solarized-light)
(setq doom-theme 'doom-vibrant)
;; (setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/notes/")

(setq kill-ring-max most-positive-fixnum) ;; set kill ring max size to 2305843009213693951 (2^61 - 1)

(setq display-time-format "%Y-%m-%d %H:%M")
(setq display-time-24hr-format t)
(display-time-mode 1)

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; faster buffer switching alternative to [ ] for german keyboards (ö,ä)
(map! "M-ö" #'previous-buffer)
(map! "M-ä" #'next-buffer)

;; persistent kill ring
(after! savehist
  (add-to-list 'savehist-additional-variables 'kill-ring))

;; rainbow-delimiters

(use-package! rainbow-delimiters
  :init)

;; (use-package! kdeconnect
;;   :init)

;; (use-package! mcp
  ;; :init)

(use-package! mcp-server-lib
  :init)

(use-package! org-mcp
  :init)

(use-package! elisp-dev-mcp
  :init)

;; (use-package! claude-code
  ;; :init)

(use-package! claude-code
  :config
  (global-set-key (kbd "C-c c") 'claude-code-transient))

(use-package! agent-shell
  :init)

(use-package! ollama-buddy
  :init)

;; TODO: datapass for doom-modeline

;; Load EXWM configuration only when Emacs is running as the window manager.
;; SDDM sets DESKTOP_SESSION=exwm when the EXWM session is selected at login.
;; Plasma sessions are unaffected — this block never runs under KDE.
(when (or (string= (getenv "DESKTOP_SESSION") "exwm")
          (string= (getenv "XDG_CURRENT_DESKTOP") "EXWM"))
  (load! "exwm"))

(after! claude-code
  (advice-add 'claude-code-run :around
    (lambda (orig-fn &rest args)
      (unless (projectile-project-root)
        (setq-local projectile-project-root default-directory))
      (apply orig-fn args))))

(after! codex-cli
  :init
  :config)

(after! chatgpt-shell
  :init
  :config)

(after! copilot
  :init
  :config)

(after! chatgpt-shell
  :init
  :config)

(after! monet
  :init
  :config)

(after! frameshot
  :init
  :config)

(after! leo
  :init
  :config)

(after! magit-delta
  (use-package! magit-delta
    :hook (magit-mode . magit-delta-mode)
    :config
    ;; Disable line numbers for magit-delta to avoid breaking hunks
    (setq magit-delta-default-options '("--line-numbers" "--disable"))))

(after! blamer
  :init
  :config)

(after! gh
  :init
  :config)

(after! git-lens
  :init
  :config)

(after! gh
  :init
  :config)

(after! gh-notify
  :init
  :config)

(after! exwm-mff
  :init
  :config)

;; TODO fix me
;; ⛔ Warning (initialization): An error occurred while booting Doom Emacs:
;, Error caused by user's config or system: doom/config.el, (file-missing Cannot open load file No such file or directory multi-vterm)
;,
;, To ensure normal operation, you should investigate and remove the
;, cause of the error in your Doom config files. Start Emacs with
;, the '--debug-init' option to view a complete error backtrace.
;; (use-package! multi-vterm
;;   :config
;;   (map! :leader
;;         (:prefix ("t" . terminal)
;;          :desc "New terminal"   "t" #'multi-vterm
;;          :desc "Next terminal"  "n" #'multi-vterm-next
;;          :desc "Prev Terminal"  "p" #'multi-vterm-prev
;;          :desc "Named terminal" "s" #'multi-vterm-project)))

;; (use-package! eat
;;   :hook (eshell-mode . eat-shell-mode))

;; eat is provided by Nix (emacsPackages.eat) — no recipe needed.
;; eat.el auto-sets eat-term-terminfo-directory to its bundled terminfo in the
;; Nix store, so TERMINFO does not need to be overridden here.
(after! eat
  (add-hook 'eshell-mode-hook #'eat-eshell-mode)
  (setq eat-term-name "xterm-256color"))

;; Universal launcher
(load! "lisp/app-launcher")

;; SPC f p opens the dotfiles source instead of the read-only Nix store symlink.
;; ~/.config/doom/ files are managed by home-manager; edits must happen in the
;; dotfiles repo at ~/dotfiles/home/doom/.
(defun doom/find-file-in-private-config ()
  "Browse the Doom config source in the dotfiles repository."
  (interactive)
  (doom-project-find-file (expand-file-name "~/dotfiles/home/doom/")))
