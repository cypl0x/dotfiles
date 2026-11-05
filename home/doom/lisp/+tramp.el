;;; lisp/+tramp.el --- TRAMP remote editing performance -*- lexical-binding: t; -*-
;;
;; SSH method, connection sharing, eglot guard, VC disable on remote,
;; and connection diagnostics.
;;
;;; Code:

;;;; Core TRAMP tuning ───────────────────────────────────────────────────────

(after! tramp
  ;; Use persistent shell connection, not per-file scp copies.
  (setq tramp-default-method "ssh")

  ;; Let ~/.ssh/config handle ControlMaster (we set it globally there).
  (setq tramp-use-connection-share nil)

  ;; Reduce logging overhead (1 = errors only, default 3).
  (setq tramp-verbose 1)

  ;; Cache remote file attributes for 10 min (default 10 s).
  (setq remote-file-name-inhibit-cache 600)

  ;; No lock files on remote hosts.
  (setq remote-file-name-inhibit-locks t)

  ;; Lower connection timeout — SSH connects instantly.
  (setq tramp-connection-timeout 10)

  ;; Disable VC on remote files — prevents git probes on every file open.
  (setq vc-ignore-dir-regexp
        (format "%s\\|%s"
                vc-ignore-dir-regexp
                tramp-file-name-regexp)))

;;;; Eglot guard — prevent LSP on remote ─────────────────────────────────────

;; A language server started for a remote buffer runs over TRAMP and blocks
;; the UI while it starts (eglot-ltex did, for every text file).
(after! eglot
  (defadvice! +tramp/eglot-ensure-no-remote (fn)
    "Skip `eglot-ensure' for remote TRAMP buffers."
    :around #'eglot-ensure
    (unless (file-remote-p default-directory)
      (funcall fn))))

;;;; Recent files: remote ones too ──────────────────────────────────────────

;; SPC f r lists remote files and directories again (/ssh:…, /sshfs:…), for
;; going back to a project on inari in one step.  They were excluded here
;; (`recentf-exclude' had TRAMP's regexp) for fear of slow cleanups, but
;; recentf's own check doesn't connect: an unconnected remote file is kept
;; as it is (`recentf-keep-default-predicate').  The remote paths still in
;; the minibuffer history come back, at the end of the list.
(after! recentf
  (setq recentf-exclude (delete tramp-file-name-regexp recentf-exclude))
  (dolist (file (reverse file-name-history))
    (when (and (stringp file) (file-remote-p file))
      (add-to-list 'recentf-list file t))))

;;;; Connection diagnostics ──────────────────────────────────────────────────

(defun +tramp/connection-info ()
  "Show current TRAMP connection details and performance hints."
  (interactive)
  (let ((buf (get-buffer-create "*TRAMP Info*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "TRAMP Configuration\n\n"
                            'face '(:height 1.3 :weight bold)))
        (insert (format "Default method:       %s\n" tramp-default-method))
        (insert (format "Connection share:     %s\n" tramp-use-connection-share))
        (insert (format "Verbose level:        %s\n" tramp-verbose))
        (insert (format "Cache timeout:        %s s\n" remote-file-name-inhibit-cache))
        (insert (format "Connection timeout:   %s s\n" tramp-connection-timeout))
        (insert (format "Lock files disabled:  %s\n" remote-file-name-inhibit-locks))
        (insert (format "VC on remote:         %s\n\n"
                        (if (string-match-p "tramp" vc-ignore-dir-regexp)
                            "DISABLED (good)" "enabled (slow!)")))
        ;; Active connections
        (insert (propertize "Active Connections\n" 'face '(:weight bold)))
        (let ((conns (tramp-list-connections)))
          (if (null conns)
              (insert "  None\n")
            (dolist (c conns)
              (insert (format "  %s\n" c)))))
        (insert "\n")
        ;; SSH config check
        (insert (propertize "SSH ControlMaster\n" 'face '(:weight bold)))
        (let ((ssh-out (shell-command-to-string "ssh -G localhost 2>/dev/null | grep controlmaster")))
          (insert (format "  %s\n"
                          (if (string-match-p "auto" ssh-out)
                              "auto (good)" "NOT configured (slow!)")))))
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

(defun +tramp/cleanup ()
  "Clean up all TRAMP connections and caches."
  (interactive)
  (tramp-cleanup-all-connections)
  (tramp-cleanup-all-buffers)
  (message "TRAMP connections and caches cleaned"))

;;;; Quick connect ───────────────────────────────────────────────────────────

(defun +tramp/connect-inari ()
  "Open dired on inari (wolfhard.net) home directory."
  (interactive)
  (dired "/ssh:cypl0x@wolfhard.net:~/"))

(defun +tramp/connect-inari-turm ()
  "Open dired on inari's Turm project."
  (interactive)
  (dired "/ssh:cypl0x@wolfhard.net:~/dev/Turm/"))

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      (:prefix ("R" . "remote")
       :desc "TRAMP info"         "i" #'+tramp/connection-info
       :desc "Cleanup connections" "c" #'+tramp/cleanup
       :desc "Connect inari"      "h" #'+tramp/connect-inari
       :desc "Connect Turm"       "t" #'+tramp/connect-inari-turm))

(provide '+tramp)
;;; +tramp.el ends here
