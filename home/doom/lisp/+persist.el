;;; lisp/+persist.el --- Persistent scratch and new buffers -*- lexical-binding: t; -*-
;;
;; Auto-save non-file-visiting buffers (*scratch*, *new*, etc.) to disk
;; so their content survives daemon/Emacs restarts.  Like Sublime Text 2+.
;;
;;; Code:

(defvar +persist/directory
  (expand-file-name "persist-buffers/" doom-cache-dir)
  "Directory for persisted buffer contents.")

(defvar +persist/tracked-buffers nil
  "List of buffer names currently being tracked for persistence.")

(defvar +persist/exclude-patterns
  '("^\\*Messages\\*$" "^\\*Completions\\*$" "^\\*Help\\*$"
    "^\\*Compile" "^\\*Backtrace\\*$" "^\\*Warnings\\*$"
    "^\\*straight" "^\\*doom" "^ " "^\\*Minibuf"
    "^\\*Echo Area" "^\\*agent-shell" "^\\*Claude")
  "Patterns for buffers to NOT persist.")

(defun +persist/--should-persist-p (buf)
  "Return non-nil if BUF should be persisted."
  (and (buffer-live-p buf)
       (not (buffer-file-name buf))
       (> (buffer-size buf) 0)
       (not (seq-some (lambda (pat)
                        (string-match-p pat (buffer-name buf)))
                      +persist/exclude-patterns))))

(defun +persist/--file-for-buffer (name)
  "Return persistence file path for buffer NAME."
  (expand-file-name
   (concat (replace-regexp-in-string "[^a-zA-Z0-9_-]" "_" name) ".el")
   +persist/directory))

(defun +persist/save-buffer (buf)
  "Save non-file-visiting BUF to persist directory."
  (when (+persist/--should-persist-p buf)
    (make-directory +persist/directory t)
    (let ((file (+persist/--file-for-buffer (buffer-name buf))))
      (with-temp-file file
        (insert (format ";; -*- mode: emacs-lisp; coding: utf-8 -*-\n")
                (format ";; Persisted buffer: %s\n" (buffer-name buf))
                (format ";; Mode: %s\n" (with-current-buffer buf (symbol-name major-mode)))
                (format ";; Saved: %s\n\n" (format-time-string "%Y-%m-%d %H:%M:%S"))
                (format "(setq +persist/--name %S)\n" (buffer-name buf))
                (format "(setq +persist/--mode '%s)\n"
                        (with-current-buffer buf (symbol-name major-mode)))
                (format "(setq +persist/--content %S)\n"
                        (with-current-buffer buf
                          (buffer-substring-no-properties
                           (point-min) (point-max)))))))))

(defun +persist/save-all ()
  "Save all persistable buffers."
  (interactive)
  (let ((count 0))
    (dolist (buf (buffer-list))
      (when (+persist/--should-persist-p buf)
        (+persist/save-buffer buf)
        (cl-incf count)))
    (message "Persisted %d buffers" count)))

(defun +persist/restore-all ()
  "Restore all persisted buffers from disk."
  (interactive)
  (when (file-directory-p +persist/directory)
    (let ((count 0))
      (dolist (file (directory-files +persist/directory t "\\.el$"))
        (condition-case nil
            (let (+persist/--name +persist/--mode +persist/--content)
              (load file nil t t)
              (when (and +persist/--name +persist/--content
                         (not (get-buffer +persist/--name)))
                (with-current-buffer (get-buffer-create +persist/--name)
                  (insert +persist/--content)
                  (goto-char (point-min))
                  (when +persist/--mode
                    (condition-case nil
                        (funcall (intern +persist/--mode))
                      (error nil)))
                  (set-buffer-modified-p nil)
                  (cl-incf count))))
          (error nil)))
      (when (> count 0)
        (message "Restored %d persisted buffers" count)))))

(defun +persist/remove (buf)
  "Remove persistence file for BUF."
  (let ((file (+persist/--file-for-buffer
               (if (bufferp buf) (buffer-name buf) buf))))
    (when (file-exists-p file)
      (delete-file file))))

;;;; Auto-save timer ─────────────────────────────────────────────────────────

(defvar +persist/--timer nil)

(defun +persist/enable ()
  "Enable periodic buffer persistence."
  (interactive)
  ;; Save every 60 seconds
  (unless +persist/--timer
    (setq +persist/--timer
          (run-with-timer 60 60 #'+persist/save-all)))
  ;; Save on kill-emacs
  (add-hook 'kill-emacs-hook #'+persist/save-all)
  ;; Restore on startup
  (+persist/restore-all)
  ;; Clean up when buffer killed
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when (and (not (buffer-file-name))
                         (member (buffer-name) +persist/tracked-buffers))
                (+persist/remove (current-buffer))))))

;;;; Boot ────────────────────────────────────────────────────────────────────

(+persist/enable)

(map! :leader
      (:prefix "b"
       :desc "Save persist buffers" "P" #'+persist/save-all))

(provide '+persist)
;;; +persist.el ends here
