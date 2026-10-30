;;; lisp/+nix.el --- NixOS integration -*- lexical-binding: t; -*-
;;
;; nixd LSP configuration, NixOS option browser, system info,
;; and nix-specific workflow tools.
;;
;;; Code:

;;;; nixd as default Nix LSP ─────────────────────────────────────────────────

;; nixd provides NixOS/home-manager option completion which nil lacks.
;; Only switch if nixd is available on PATH.
(after! eglot
  (when (executable-find "nixd")
    (setf (alist-get '(nix-mode nix-ts-mode) eglot-server-programs
                     nil nil #'equal)
          '("nixd"))))

;;;; Nix REPL ────────────────────────────────────────────────────────────────

(defun +nix/repl ()
  "Open a nix repl in a vterm buffer."
  (interactive)
  (let ((buf-name "*nix-repl*"))
    (unless (get-buffer buf-name)
      (vterm buf-name)
      (vterm-send-string "nix repl\n"))
    (pop-to-buffer buf-name)))

;;;; Nix system info ─────────────────────────────────────────────────────────

(defun +nix/system-info ()
  "Show NixOS system information in a popup buffer."
  (interactive)
  (let ((buf (get-buffer-create "*NixOS Info*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "NixOS System Information\n\n"
                            'face '(:height 1.3 :weight bold)))
        ;; System version
        (insert (propertize "System\n" 'face '(:weight bold)))
        (insert (format "  NixOS: %s\n"
                        (string-trim
                         (shell-command-to-string
                          "nixos-version 2>/dev/null || echo 'not NixOS'"))))
        (insert (format "  Nix:   %s\n"
                        (string-trim
                         (shell-command-to-string "nix --version 2>/dev/null"))))
        (insert (format "  Flake: %s\n\n"
                        (if (file-exists-p "~/dotfiles/flake.nix")
                            "~/dotfiles/flake.nix" "not found")))
        ;; Emacs info
        (insert (propertize "Emacs\n" 'face '(:weight bold)))
        (insert (format "  Version: %s\n" emacs-version))
        (insert (format "  Build:   %s\n" system-configuration))
        (insert (format "  pgtk:    %s\n" (featurep 'pgtk)))
        (insert (format "  Native:  %s\n\n"
                        (and (fboundp 'native-comp-available-p)
                             (native-comp-available-p))))
        ;; Doom
        (insert (propertize "Doom Emacs\n" 'face '(:weight bold)))
        (insert (format "  Version: %s\n" doom-version))
        (insert (format "  Dir:     %s\n" doom-user-dir))
        (insert (format "  Modules: %d loaded\n\n"
                        (length (doom-module-list))))
        ;; Packages count
        (insert (propertize "Packages\n" 'face '(:weight bold)))
        (insert (format "  Straight: %d\n"
                        (hash-table-count straight--recipe-cache))))
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

;;;; Nix flake operations ────────────────────────────────────────────────────

(defun +nix/flake-update ()
  "Run `nix flake update' in the dotfiles directory."
  (interactive)
  (let ((default-directory (expand-file-name "~/dotfiles/")))
    (compile "nix flake update")))

(defun +nix/flake-check ()
  "Run `nix flake check' in the dotfiles directory."
  (interactive)
  (let ((default-directory (expand-file-name "~/dotfiles/")))
    (compile "nix flake check")))

(defun +nix/home-switch ()
  "Run home-manager switch."
  (interactive)
  (compile "home-manager switch --flake ~/dotfiles"))

(defun +nix/doom-sync ()
  "Run doom sync."
  (interactive)
  (compile "~/.config/emacs/bin/doom sync"))

;;;; Transient — NixOS dispatch ──────────────────────────────────────────────

(transient-define-prefix +nix/transient ()
    "NixOS operations."
    ["Info"
     ("i" "System info"      +nix/system-info)
     ("r" "Nix REPL"         +nix/repl)]
    ["Flake"
     ("u" "Flake update"     +nix/flake-update)
     ("c" "Flake check"      +nix/flake-check)]
    ["Build"
     ("h" "Home switch"      +nix/home-switch)
     ("s" "Doom sync"        +nix/doom-sync)])

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      (:prefix ("N" . "nix")
       :desc "NixOS menu"     "N" #'+nix/transient
       :desc "System info"    "i" #'+nix/system-info
       :desc "Nix REPL"       "r" #'+nix/repl
       :desc "Flake update"   "u" #'+nix/flake-update
       :desc "Doom sync"      "s" #'+nix/doom-sync))

(provide '+nix)
;;; +nix.el ends here
