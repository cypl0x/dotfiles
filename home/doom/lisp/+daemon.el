;;; lisp/+daemon.el --- Sync, restart and restore the Emacs daemon -*- lexical-binding: t; -*-
;;
;; Replaces the terminal loop `doom sync' → `ps aux | rg emacs' → `pkill
;; emacs' → `emacs --daemon' → `emacsclient -c' with one command that keeps
;; your workspaces:
;;
;;   SPC q R  +daemon/sync-and-restart   save, `doom sync', restart, restore
;;   C-u SPC q R                         same, but skip `doom sync'
;;
;; Why not `doom/reload'?  It re-runs init in the live process and can't
;; unload anything (packages, hooks, advice, timers stay); see JOURNAL.org.
;; Why not the built-in `restart-emacs'?  In a daemon it re-execs without
;; frames, so the `emacsclient -c' frame you were looking at is just gone.
;;
;; The relauncher is a detached shell that waits for this process to exit,
;; starts `emacs --daemon' with the same server name, then opens a frame on
;; the same display and loads the saved session into it.
;;
;;; Code:

(defvar server-name)

;; NEO Emacs (the `neomacs' command, home/neomacs.nix) runs this config
;; beside the main Emacs: a server it starts must not take the main one's socket.
(when (getenv "NEOMACS_DOOM") (setq server-name "neomacs"))

(defvar +daemon-session-name "restart"
  "Session file name (under `doom-session-file's directory) used across restarts.")

(defvar +daemon-sync-args '("sync" "-B")
  "Arguments for the `doom' CLI before a restart.")

(defun +daemon--doom-bin ()
  (expand-file-name "bin/doom" doom-emacs-dir))

(defun +daemon--relaunch-script (session)
  "Shell script restarting the daemon and restoring SESSION in a new frame."
  (require 'server)
  (let ((emacs (expand-file-name invocation-name invocation-directory))
        (client (expand-file-name "emacsclient" invocation-directory))
        (name (shell-quote-argument server-name)))
    (format "while kill -0 %d 2>/dev/null; do sleep 0.2; done
%s --daemon=%s || { notify-send -u critical 'Emacs' 'daemon failed to start'; exit 1; }
exec %s -s %s -c -n -e %s"
            (emacs-pid)
            (shell-quote-argument emacs) name
            (shell-quote-argument client) name
            (shell-quote-argument
             (format "(progn (doom-load-session %S) (message \"Restarted & restored %s\"))"
                     session (format-time-string "%T"))))))

(defun +daemon--restart (session)
  "Save SESSION, spawn the relauncher and kill this Emacs."
  (doom-save-session session)
  (let ((process-environment
         ;; The new frame goes where the current one is.
         (if-let* ((display (frame-parameter nil 'display)))
             (cons (concat "WAYLAND_DISPLAY=" display) process-environment)
           process-environment)))
    (call-process "setsid" nil 0 nil "sh" "-c" (+daemon--relaunch-script session)))
  (let ((kill-emacs-query-functions nil)
        (confirm-kill-processes nil))
    (kill-emacs)))

;;;###autoload
(defun +daemon/sync-and-restart (&optional skip-sync)
  "Save buffers, run `doom sync', then restart the daemon and restore the session.
With prefix arg SKIP-SYNC, restart without syncing. Aborts, showing the
output, if `doom sync' fails."
  (interactive "P")
  (unless (daemonp)
    (user-error "Not a daemon; use `doom/restart' instead"))
  (save-some-buffers)
  (let ((session (doom-session-file +daemon-session-name)))
    (if skip-sync
        (+daemon--restart session)
      (let ((buf (get-buffer-create "*doom sync*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t)) (erase-buffer))
          (special-mode))
        (message "doom sync running… (restart follows on success)")
        (make-process
         :name "doom-sync" :buffer buf :noquery t
         :command (cons (+daemon--doom-bin) +daemon-sync-args)
         :sentinel
         (lambda (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (if (zerop (process-exit-status proc))
                 (+daemon--restart session)
               (pop-to-buffer (process-buffer proc))
               (message "doom sync failed (exit %d); daemon NOT restarted"
                        (process-exit-status proc))))))))))

(map! :leader
      :desc "Sync, restart & restore" "q R" #'+daemon/sync-and-restart)


;;;; Is this Emacs in sync with the config?

;; What the running Emacs has can lag behind what is on disk in four ways,
;; each with its own fix: a file under lisp/ or modules/ edited after it
;; was loaded (load it); config.el, init.el or packages.el deployed anew
;; since start (nrs put them there; config.el can be loaded, the other two
;; need doom sync and a restart); the repo's copy of those not deployed yet
;; (nrs); doom sync or a new Emacs since start (restart).
;;
;;   SPC q ?  +daemon/status   what is out of sync, each with its fix

(defvar doom-user-dir)
(defvar doom-profile-dir)

(defvar +daemon--load-times (make-hash-table :test #'equal)
  "File truename → when it was last loaded, for files loaded since this
file was.  Earlier ones count as loaded when Emacs started.")

(defun +daemon--note-load-h (file)
  (puthash (file-truename file) (current-time) +daemon--load-times))
(add-hook 'after-load-functions #'+daemon--note-load-h)

(defun +daemon--mtime (file &optional link)
  "FILE's modification time; with LINK, the symlink's own (home-manager
relinks when it deploys a new version; the store file's time is 1970)."
  (when-let* ((attrs (file-attributes (if link file (file-truename file)))))
    (file-attribute-modification-time attrs)))

(defconst +daemon--deployed-files '("config.el" "init.el" "packages.el")
  "Files of the config that are Nix store copies, not live links.")

(defvar +daemon--deployed nil
  "NAME → the store file it pointed to when this Emacs started, or
`unknown' (redeployed between start and this file's loading).  A store
path changes only with the content; the links' own times change with
every home-manager generation, whichever file changed.")

(defun +daemon--note-deployed (&optional names)
  "Remember where NAMES (default: all deployed files) point now."
  (dolist (name (or names +daemon--deployed-files))
    (let ((link (expand-file-name name doom-user-dir)))
      (when (file-exists-p link)
        (setf (alist-get name +daemon--deployed nil nil #'equal)
              (if (and (null names)
                       (time-less-p before-init-time (or (+daemon--mtime link t) 0)))
                  'unknown
                (file-truename link)))))))

(when (and (boundp 'doom-user-dir) (null +daemon--deployed)) (+daemon--note-deployed))

(defun +daemon--repo-dir ()
  "The checkout of home/doom: where lisp/ (a live link) points."
  (file-name-directory (directory-file-name
                        (file-truename (expand-file-name "lisp" doom-user-dir)))))

(defun +daemon--stale-files ()
  "Loaded files of this config edited since they were loaded: (FILE . MTIME)."
  (let* ((repo (+daemon--repo-dir))
         (user (file-name-as-directory (expand-file-name doom-user-dir)))
         seen out)
    (dolist (entry load-history)
      (when-let* ((f (car entry))
                  ((stringp f))
                  ;; Cheap first: load-history has thousands of files.
                  ((or (string-prefix-p user f) (string-prefix-p repo f)))
                  (src (file-truename (if (string-suffix-p ".elc" f) (substring f 0 -1) f)))
                  ((string-prefix-p repo src))
                  ((not (member src seen)))
                  ((file-exists-p src)))
        (push src seen)
        (let ((loaded (gethash src +daemon--load-times before-init-time))
              (mtime (+daemon--mtime src)))
          (when (time-less-p loaded mtime)
            (push (cons src mtime) out)))))
    (sort out (lambda (a b) (time-less-p (cdr b) (cdr a))))))

(defun +daemon--store-name (path)
  "The /nix/store entry PATH lies in, or PATH."
  (if (string-match "\\`/nix/store/[^/]+-\\([^/]+\\)" path) (match-string 1 path) path))

(defun +daemon--differs-p (a b)
  "Non-nil when files A and B differ in content."
  (not (equal (with-temp-buffer (insert-file-contents-literally a) (buffer-string))
              (with-temp-buffer (insert-file-contents-literally b) (buffer-string)))))

(defun +daemon-sync-checks ()
  "What is out of sync: a list of (WHAT DETAIL FIX), FIX a command or nil."
  (let* ((start before-init-time)
         (repo (+daemon--repo-dir))
         (profile-init (expand-file-name (format "init.%d.%d.el" emacs-major-version emacs-minor-version)
                                         doom-profile-dir))
         (synced (+daemon--mtime profile-init))
         (running (file-truename (expand-file-name invocation-name invocation-directory)))
         (installed (and (executable-find "emacs") (file-truename (executable-find "emacs"))))
         out)
    (when-let* ((stale (+daemon--stale-files)))
      (push (list (format "%d file%s edited since loaded" (length stale) (if (cdr stale) "s" ""))
                  (mapconcat (lambda (s) (format "%s (%s)" (file-relative-name (car s) repo)
                                                 (format-time-string "%R" (cdr s))))
                             stale ", ")
                  #'+daemon/load-stale)
            out))
    (dolist (name +daemon--deployed-files)
      (let ((deployed (expand-file-name name doom-user-dir))
            (source (expand-file-name name repo)))
        (when (and (file-exists-p deployed) (file-exists-p source)
                   (+daemon--differs-p deployed source))
          (push (list (format "%s: your edit isn't deployed" name)
                      "the repo's copy differs from the one Emacs reads (a Nix store copy)"
                      'nrs)
                out))
        (when-let* ((was (alist-get name +daemon--deployed nil nil #'equal))
                    ((not (equal was (file-truename deployed)))))
          (push (list (if (eq was 'unknown)
                          (format "%s may be newer than what this Emacs read (deployed %s)"
                                  name (format-time-string "%R" (+daemon--mtime deployed t)))
                        (format "%s deployed anew since this Emacs started" name))
                      (if (equal name "config.el") "load it, or restart"
                        "it lists modules or packages: doom sync, then restart")
                      (if (equal name "config.el") #'+daemon/load-config #'+daemon/sync-and-restart))
                out))))
    (when (and synced (time-less-p start synced))
      (push (list (format "doom sync ran at %s, after this Emacs started (%s)"
                          (format-time-string "%R" synced) (format-time-string "%R" start))
                  "packages and autoloads it built are used from the next start"
                  (lambda () (interactive) (+daemon/sync-and-restart t)))
            out))
    (when (and installed (not (equal running installed)))
      (push (list "A different Emacs is installed than the one running"
                  (format "running %s, installed %s"
                          (+daemon--store-name running) (+daemon--store-name installed))
                  (lambda () (interactive) (+daemon/sync-and-restart t)))
            out))
    (nreverse out)))

(defun +daemon/load-stale ()
  "Load the files of this config edited since they were loaded."
  (interactive)
  (let* ((lisp (file-name-as-directory (expand-file-name "lisp" (+daemon--repo-dir))))
         (all (mapcar #'car (+daemon--stale-files)))
         ;; A module's config.el starts servers and timers: loaded twice, twice.
         (files (seq-filter (lambda (f) (string-prefix-p lisp f)) all))
         (rest (seq-difference all files))
         failed)
    (dolist (f (reverse files))
      (condition-case err (load f nil t)
        (error (push (format "%s: %s" (file-name-nondirectory f) (error-message-string err)) failed))))
    (message "Loaded %d file%s%s%s" (length files) (if (= 1 (length files)) "" "s")
             (if failed (concat "; failed: " (string-join failed "; ")) "")
             (if rest (format "; at the next restart: %s"
                              (mapconcat (lambda (f) (file-relative-name f (+daemon--repo-dir))) rest ", "))
               ""))))

(defun +daemon/load-config ()
  "Load config.el again (what nrs deployed)."
  (interactive)
  (load (expand-file-name "config.el" doom-user-dir) nil t)
  (+daemon--note-deployed '("config.el"))
  (message "config.el loaded"))

(defun +daemon--fix-label (fix)
  (cond ((eq fix 'nrs) "run nrs in a terminal")
        ((eq fix #'+daemon/load-stale) "load them")
        ((eq fix #'+daemon/load-config) "load config.el")
        ((eq fix #'+daemon/sync-and-restart) "doom sync and restart (SPC q R)")
        (t "restart (C-u SPC q R)")))

(defun +daemon/status ()
  "Say whether this Emacs is in sync with your config.
If not: what lags behind, and the fix for each."
  (interactive)
  (let ((checks (+daemon-sync-checks)))
    (if (null checks)
        (message "✔ In sync: every loaded file as on disk, config deployed, no doom sync or new Emacs since start (%s)"
                 (format-time-string "%R" before-init-time))
      (with-current-buffer (get-buffer-create "*in sync?*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "This Emacs (started %s) lags behind your config:\n\n"
                          (format-time-string "%F %R" before-init-time)))
          (pcase-dolist (`(,what ,detail ,fix) checks)
            (insert "✘ " (propertize what 'face 'bold) "\n  " detail "\n  → ")
            (if (functionp fix)
                (insert-text-button (+daemon--fix-label fix) 'action (lambda (_) (funcall fix))
                                    'follow-link t)
              (insert (+daemon--fix-label fix)))
            (insert "\n\n"))
          (insert "g checks again.")
          (goto-char (point-min)))
        (special-mode)
        (local-set-key "g" (lambda () (interactive) (+daemon/status)))
        (display-buffer (current-buffer))))))

(map! :leader :desc "In sync with the config?" "q ?" #'+daemon/status)
(provide '+daemon)
;;; +daemon.el ends here
