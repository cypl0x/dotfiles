;;; functions.el --- Eshell helper functions for NixOS workflow -*- lexical-binding: t; -*-

(defvar +eshell-dotfiles-dir (expand-file-name "~/dotfiles")
  "Location of the NixOS flake configuration.")

(defvar +eshell-sudo-program "/run/wrappers/bin/sudo"
  "Path to the real sudo binary on NixOS.")

(setq +eshell-sudo-askpass-program
      (or (executable-find "sudo-askpass")
          (error "sudo-askpass not found in PATH")))

(defun +eshell--insert-at-end (string)
  "Insert STRING at end of current Eshell buffer."
  (when (and string (not (string-empty-p string)))
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (point-max))
        (insert string)))))

(defun +eshell--call-sync (program &rest args)
  "Run PROGRAM synchronously with ARGS.
Return a cons cell (EXIT-CODE . OUTPUT), where OUTPUT contains combined
stdout/stderr."
  (with-temp-buffer
    (let ((status (apply #'call-process
                         program
                         nil
                         '(t t)
                         nil
                         args)))
      (cons status (buffer-string)))))

(defun +eshell--statix-check ()
  "Run `statix check' synchronously and insert its output into Eshell.
Signal an error if statix fails."
  (pcase-let ((`(,status . ,output)
               (+eshell--call-sync "statix" "check" +eshell-dotfiles-dir)))
    (+eshell--insert-at-end output)
    (unless (= status 0)
      (error "statix check failed with exit code %s" status))
    t))

(defun +eshell--sudo-command-with-askpass (args)
  "Run sudo with ARGS through Eshell using SUDO_ASKPASS."
  (let ((process-environment
         (append
          (list (format "SUDO_ASKPASS=%s" +eshell-sudo-askpass-program))
          process-environment)))
    (eshell-external-command
     +eshell-sudo-program
     (append (list "-A") args))))

(defun +eshell--nixos-rebuild (action &rest extra-args)
  "Run `nixos-rebuild ACTION' after a successful statix check."
  (let* ((dotfiles +eshell-dotfiles-dir)
         (host (system-name))
         (flake (format "%s#%s" dotfiles host))
         (argv (append (list "nixos-rebuild" action)
                       extra-args
                       (list "--flake" flake))))
    (+eshell--statix-check)
    (+eshell--sudo-command-with-askpass argv)))

(defun eshell/nrs (&rest _)
  "Run `nixos-rebuild switch'."
  (+eshell--nixos-rebuild "switch"))

(defun eshell/nrsl (&rest _)
  "Run `nixos-rebuild switch --option builders \"\"'."
  (+eshell--nixos-rebuild "switch" "--option" "builders" ""))

(defun eshell/nrt (&rest _)
  "Run `nixos-rebuild test'."
  (+eshell--nixos-rebuild "test"))

(defun eshell/nrb (&rest _)
  "Run `nixos-rebuild boot'."
  (+eshell--nixos-rebuild "boot"))

(defun eshell/nrsi (&rest _)
  "Run remote nixos-rebuild switch for host inari."
  (+eshell--statix-check)
  (+eshell--sudo-command-with-askpass
   (list "nixos-rebuild"
         "switch"
         "--flake" (format "%s#inari" +eshell-dotfiles-dir)
         "--build-host" "root@65.109.108.233"
         "--target-host" "root@65.109.108.233")))

(defun eshell/nr-check (&rest _)
  "Run only `statix check'."
  (+eshell--statix-check)
  nil)

(provide 'functions)
;;; functions.el ends here
