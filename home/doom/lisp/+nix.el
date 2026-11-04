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

(defvar +nix-dotfiles (expand-file-name "~/dotfiles/") "The system flake.")

(defun +nix--inputs ()
  "The flake's direct inputs with their locked dates: alist (LABEL . NAME)."
  (let* ((default-directory +nix-dotfiles)
         (meta (with-temp-buffer
                 (call-process "nix" nil (list t nil) nil "flake" "metadata" "--json")
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'alist)))
         (nodes (alist-get 'nodes (alist-get 'locks meta))))
    (mapcar (lambda (entry)
              ;; entry: (INPUT . NODE-KEY); a string key for a direct input.
              (let* ((node (and (stringp (cdr entry)) (alist-get (intern (cdr entry)) nodes)))
                     (time (alist-get 'lastModified (alist-get 'locked node))))
                (cons (format "%-20s locked %s" (car entry)
                              (if time (format-time-string "%F" time) "?"))
                      (symbol-name (car entry)))))
            (alist-get 'inputs (alist-get 'root nodes)))))

(defun +nix/flake-update (input)
  "Update one INPUT of the system flake (never all: on this metered link a
full update fetched ~35 GB).  Check `datapass' after."
  (interactive
   (let ((inputs (+nix--inputs)))
     (list (cdr (assoc (completing-read "Update input: " inputs nil t) inputs)))))
  (let ((default-directory +nix-dotfiles))
    (compile (format "nix flake update %s" (shell-quote-argument input)))))

(defun +nix/flake-check ()
  "Run `nix flake check' in the dotfiles directory."
  (interactive)
  (let ((default-directory +nix-dotfiles))
    (compile "nix flake check")))

(defvar +nix--rebuild-from nil "The system generation a rebuild started from.")

(defun +nix--rebuild-finished (buf status)
  "After a successful rebuild: what changed, package by package."
  (with-current-buffer buf
    (remove-hook 'compilation-finish-functions #'+nix--rebuild-finished t))
  (when (and (string-prefix-p "finished" status) +nix--rebuild-from)
    (let ((to (file-truename "/run/current-system")))
      (if (equal to +nix--rebuild-from)
          (message "Rebuilt: the system didn't change")
        (with-current-buffer (get-buffer-create "*nix rebuild diff*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (format "%s\n→ %s\n\n" +nix--rebuild-from to))
            (call-process "nix" nil (list t nil) nil "store" "diff-closures" +nix--rebuild-from to)
            (ansi-color-apply-on-region (point-min) (point-max)))
          (goto-char (point-min))
          (special-mode))
        (display-buffer "*nix rebuild diff*")))))

(defun +nix/rebuild (&optional boot)
  "`nrs' in Emacs: statix, then nixos-rebuild switch (BOOT: boot) for this
host, in a compilation buffer; on success, the package diff against the
previous generation."
  (interactive "P")
  (let ((default-directory +nix-dotfiles))
    (setq +nix--rebuild-from (file-truename "/run/current-system"))
    (with-current-buffer
        (compile (format "statix check %s && sudo nixos-rebuild %s --flake %s#%s"
                         (shell-quote-argument +nix-dotfiles) (if boot "boot" "switch")
                         (shell-quote-argument (directory-file-name +nix-dotfiles))
                         (system-name)))
      (add-hook 'compilation-finish-functions #'+nix--rebuild-finished nil t))))

(defun +nix/doom-sync ()
  "Run doom sync."
  (interactive)
  (compile "~/.config/emacs/bin/doom sync"))

;;;; Transient — NixOS dispatch ──────────────────────────────────────────────

(transient-define-prefix +nix/transient ()
    "NixOS operations."
    ["Info"
     ("i" "System info"      +nix/system-info)
     ("r" "Nix REPL"         +nix/repl)
     ("d" "Dev shell into Emacs" +nix/develop)]
    ["Flake"
     ("u" "Update one input" +nix/flake-update)
     ("c" "Flake check"      +nix/flake-check)]
    ["Build"
     ("b" "Rebuild (nrs)"    +nix/rebuild)
     ("s" "Doom sync"        +nix/doom-sync)])

;;;; Keybindings ─────────────────────────────────────────────────────────────

;;;; nix develop, in Emacs ───────────────────────────────────────────────────

;; `nix develop' was the second most run command here (482 times); 32 of 36
;; flakes under ~/dev have a dev shell but no .envrc, so envrc left Emacs
;; without their tools (compilers, LSP servers).  SPC N d loads the project's
;; dev shell into Emacs, no .envrc needed: `nix print-dev-env --json', run
;; in the background, applied through envrc's own `envrc--apply' to every
;; buffer of the project, and to its buffers opened later (eshell, compile,
;; eglot all see it).  C-u SPC N d drops it again.

(declare-function envrc--apply "ext:envrc" (buf result))
(declare-function envrc--get-current-env-or-run-direnv "ext:envrc" (&optional force))
(declare-function envrc--find-env-dir "ext:envrc" ())
(defvar envrc-mode)

(defvar +nix-develop--envs (make-hash-table :test #'equal)
  "Project root -> its dev shell's environment, as envrc pairs.")

(defconst +nix-develop-ignored-variables
  '("HOME" "PWD" "OLDPWD" "SHELL" "SHLVL" "TERM" "TMP" "TMPDIR" "TEMP" "TEMPDIR"
    "NIX_BUILD_TOP" "NIX_BUILD_CORES" "NIX_LOG_FD" "NIX_STORE" "out" "outputs"
    "builder" "system" "name" "shellHook" "stdenv" "dontAddDisableDepTrack")
  "Dev shell variables that belong to the build sandbox, not to Emacs.")

(defun +nix-develop--pairs (json)
  "Exported variables of `nix print-dev-env --json' output JSON, as
\(NAME . VALUE); PATH goes in front of the current one."
  (let (pairs)
    (maphash
     (lambda (name var)
       (when (and (equal (gethash "type" var) "exported")
                  (stringp (gethash "value" var))
                  (not (member name +nix-develop-ignored-variables)))
         (push (cons name
                     (if (equal name "PATH")
                         (concat (gethash "value" var) ":" (getenv "PATH"))
                       (gethash "value" var)))
               pairs)))
     (gethash "variables" (json-parse-string json)))
    pairs))

(defun +nix-develop--root (&optional dir)
  (when-let* ((root (locate-dominating-file (or dir default-directory) "flake.nix")))
    (expand-file-name root)))

(defun +nix-develop--for (dir)
  "The loaded dev shell environment covering DIR, or nil."
  (when-let* ((root (+nix-develop--root dir)))
    (gethash root +nix-develop--envs)))

(defun +nix-develop--envrc-a (fn &rest args)
  "Around envrc's lookup: no .envrc, but a dev shell loaded for the project
\(`+nix/develop'): apply that."
  (let ((env (and (not (envrc--find-env-dir)) (+nix-develop--for default-directory))))
    (if env
        (envrc--apply (current-buffer) env)
      (apply fn args))))

(defun +nix-develop--refresh (root)
  "Re-apply the environment in ROOT's envrc buffers."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and (bound-and-true-p envrc-mode)
                 (string-prefix-p root (expand-file-name default-directory)))
        (envrc--get-current-env-or-run-direnv)))))

;;;###autoload
(defun +nix/develop (&optional drop)
  "Load this project's flake dev shell into Emacs (`nix develop', no
.envrc needed).  With prefix arg DROP, unload it."
  (interactive "P")
  (let ((root (or (+nix-develop--root) (user-error "No flake.nix above %s" default-directory))))
    (require 'envrc)
    (advice-add 'envrc--get-current-env-or-run-direnv :around #'+nix-develop--envrc-a)
    (if drop
        (progn (remhash root +nix-develop--envs)
               (+nix-develop--refresh root)
               (message "Dev shell of %s unloaded" (abbreviate-file-name root)))
      (message "Loading the dev shell of %s…" (abbreviate-file-name root))
      (let ((buf (generate-new-buffer " *nix print-dev-env*"))
            (default-directory root))
        (make-process
         :name "nix-print-dev-env" :buffer buf :noquery t
         :command '("nix" "print-dev-env" "--json")
         :stderr (get-buffer-create "*nix develop*")
         :sentinel
         (lambda (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (unwind-protect
                 (if (zerop (process-exit-status proc))
                     (let ((pairs (+nix-develop--pairs
                                   (with-current-buffer buf (buffer-string)))))
                       (puthash root pairs +nix-develop--envs)
                       (+nix-develop--refresh root)
                       (message "Dev shell of %s loaded: %d variables, its tools on PATH"
                                (abbreviate-file-name root) (length pairs)))
                   (message "nix print-dev-env failed in %s; see *nix develop*"
                            (abbreviate-file-name root)))
               (kill-buffer buf)))))))))

(map! :leader
      (:prefix ("N" . "nix")
       :desc "NixOS menu"     "N" #'+nix/transient
       :desc "System info"    "i" #'+nix/system-info
       :desc "Nix REPL"       "r" #'+nix/repl
       :desc "Dev shell into Emacs" "d" #'+nix/develop
       :desc "Update one input" "u" #'+nix/flake-update
       :desc "Rebuild (nrs)"  "b" #'+nix/rebuild
       :desc "Doom sync"      "s" #'+nix/doom-sync))

(provide '+nix)
;;; +nix.el ends here
