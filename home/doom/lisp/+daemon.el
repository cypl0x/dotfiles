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

(defvar +daemon-session-name "restart"
  "Session file name (under `doom-session-file's directory) used across restarts.")

(defvar +daemon-sync-args '("sync" "-B")
  "Arguments for the `doom' CLI before a restart.")

(defun +daemon--doom-bin ()
  (expand-file-name "bin/doom" doom-emacs-dir))

(defun +daemon--relaunch-script (session)
  "Shell script restarting the daemon and restoring SESSION in a new frame."
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

(provide '+daemon)
;;; +daemon.el ends here
