;;; eshell/functions.el --- Eshell helper functions -*- lexical-binding: t; -*-
;;
;; Vanilla Elisp — no Doom dependencies.
;; Functions prefixed with eshell/ are automatically available as eshell commands.
;;
;; Load from config.el:
;;   (with-eval-after-load 'eshell (load! "eshell/functions"))   ;; Doom
;;   (with-eval-after-load 'eshell (load (expand-file-name "eshell/functions" doom-user-dir))) ;; vanilla

;; ---------------------------------------------------------------------------
;; Navigation
;; ---------------------------------------------------------------------------

(defun eshell/mkcd (dir)
  "Create DIR and cd into it."
  (eshell/mkdir "-p" dir)
  (eshell/cd dir))

;; ---------------------------------------------------------------------------
;; NixOS rebuilds
;; ---------------------------------------------------------------------------

(defvar +eshell-dotfiles-dir (expand-file-name "~/dotfiles")
  "Path to the NixOS dotfiles repository.")

(defun +eshell--nixos-rebuild (&rest args)
  "Run nixos-rebuild with statix check first."
  (let* ((dotfiles (expand-file-name +eshell-dotfiles-dir))
         (host (system-name))
         (flake (concat dotfiles "#" host))
         (cmd (concat "statix check " dotfiles
                      " && sudo nixos-rebuild "
                      (mapconcat #'identity args " ")
                      " --flake " flake)))
    (compile cmd)))

(defun eshell/nrs (&rest _)
  "nixos-rebuild switch."
  (+eshell--nixos-rebuild "switch"))

(defun eshell/nrsl (&rest _)
  "nixos-rebuild switch, local-only (no distributed builders)."
  (+eshell--nixos-rebuild "switch" "--option builders \"\""))

(defun eshell/nrb (&rest _)
  "nixos-rebuild boot."
  (+eshell--nixos-rebuild "boot"))

(defun eshell/nrt (&rest _)
  "nixos-rebuild test."
  (+eshell--nixos-rebuild "test"))

(defun eshell/nrsv (&rest _)
  "nixos-rebuild switch with --show-trace."
  (+eshell--nixos-rebuild "switch" "--show-trace"))

(defun eshell/nrsi (&rest _)
  "nixos-rebuild switch to inari (remote build + deploy)."
  (eshell-command
   (concat "nixos-rebuild switch"
           " --flake " +eshell-dotfiles-dir "\#inari"
           " --build-host root@65.109.108.233"
           " --target-host root@65.109.108.233")))

(defun eshell/nixup (&rest _)
  "Update flake inputs and rebuild."
  (eshell-command
   (concat "cd " +eshell-dotfiles-dir
           " && nix flake update"
           " && sudo nixos-rebuild switch --flake .#" (system-name))))

(defun eshell/nixcheck (&rest _)
  "Run flake check and statix."
  (eshell-command
   (concat "cd " +eshell-dotfiles-dir
           " && nix flake check && statix check")))

;; ---------------------------------------------------------------------------
;; Archives
;; ---------------------------------------------------------------------------

(defun eshell/extract (file)
  "Extract FILE based on its extension."
  (let ((cmd (cond
              ((string-match-p "\\.tar\\.bz2$" file) (concat "tar xjf " file))
              ((string-match-p "\\.tar\\.gz$"  file) (concat "tar xzf " file))
              ((string-match-p "\\.tar\\.xz$"  file) (concat "tar xJf " file))
              ((string-match-p "\\.tar$"       file) (concat "tar xf "  file))
              ((string-match-p "\\.bz2$"       file) (concat "bunzip2 " file))
              ((string-match-p "\\.gz$"        file) (concat "gunzip "  file))
              ((string-match-p "\\.zip$"       file) (concat "unzip "   file))
              ((string-match-p "\\.7z$"        file) (concat "7z x "    file))
              ((string-match-p "\\.rar$"       file) (concat "unrar x " file))
              (t (error "Don't know how to extract '%s'" file)))))
    (eshell-command cmd)))

(defun eshell/targz (path)
  "Create a tar.gz from PATH."
  (eshell-command (concat "tar -czf " (string-trim-right path "/") ".tar.gz " path)))

(defun eshell/zipf (path)
  "Create a zip from PATH."
  (eshell-command (concat "zip -r " (string-trim-right path "/") ".zip " path)))

(defun eshell/backup (file)
  "Create a timestamped backup of FILE."
  (let ((dest (concat file ".backup-" (format-time-string "%Y%m%d-%H%M%S"))))
    (copy-file file dest)
    (message "Backed up to %s" dest)))

;; ---------------------------------------------------------------------------
;; System info
;; ---------------------------------------------------------------------------

(defun eshell/sysinfo (&rest _)
  "Show basic system information."
  (insert
   (concat "Hostname : " (system-name) "\n"
           "Emacs    : " emacs-version "\n"
           "OS       : " (symbol-name system-type) "\n"
           "User     : " (user-login-name) "\n"
           "Dir      : " (eshell/pwd) "\n")))

(defun eshell/dusort (&rest args)
  "du -h sorted by size. Optional path as first argument."
  (eshell-command (concat "du -h --max-depth=1 "
                          (or (car args) ".")
                          " | sort -hr")))

(defun eshell/countfiles (&rest args)
  "Count files in directory (default: current)."
  (eshell-command (concat "find " (or (car args) ".") " -type f | wc -l")))

(defun eshell/psgrep (name)
  "Show processes matching NAME."
  (eshell-command (concat "ps aux | grep -v grep | grep -i " name)))

;; ---------------------------------------------------------------------------
;; Network
;; ---------------------------------------------------------------------------

(defun eshell/weather (&optional location)
  "Show weather for LOCATION (default: auto-detect)."
  (eshell-command (concat "curl -s 'wttr.in/" (or location "") "?format=3'")))

(defun eshell/weatherfull (&optional location)
  "Show full weather for LOCATION."
  (eshell-command (concat "curl -s 'wttr.in/" (or location "") "'")))

;; ---------------------------------------------------------------------------
;; Development
;; ---------------------------------------------------------------------------

(defun eshell/serve (&optional port)
  "Start a simple HTTP server in current directory on PORT (default: 8000)."
  (eshell-command (concat "python3 -m http.server " (number-to-string (or port 8000)))))

(defun eshell/genpass (&optional length)
  "Generate a random password of LENGTH characters (default: 20)."
  (eshell-command
   (concat "LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "
           (number-to-string (or length 20)) "; echo")))

(defun eshell/json (&optional input)
  "Pretty-print JSON. Pass a string or pipe input."
  (eshell-command
   (if input
       (concat "echo " (shell-quote-argument input) " | python3 -m json.tool | bat -l json")
     "python3 -m json.tool | bat -l json")))

(defun eshell/path (&rest _)
  "Show PATH entries one per line."
  (mapconcat #'identity (split-string (getenv "PATH") ":") "\n"))

(defun eshell/filecount (&optional dir)
  "Count files by extension in DIR (default: current)."
  (eshell-command
   (concat "find " (or dir ".") " -type f | sed -n 's/..*\\.//p' | sort | uniq -c | sort -rn")))

(provide 'eshell/functions)
;;; eshell/functions.el ends here
