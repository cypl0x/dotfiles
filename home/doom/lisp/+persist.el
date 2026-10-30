;;; lisp/+persist.el --- Persistent scratch and new buffers -*- lexical-binding: t; -*-
;;
;; Auto-save non-file-visiting buffers (*scratch*, *new*, etc.) to disk
;; so their content survives daemon/Emacs restarts.  Like Sublime Text 2+.
;;
;;; Code:

(defvar doom-cache-dir)

;; Set by `load'ing a persisted file.  They must be special: under
;; lexical-binding a `let' of undeclared names is lexical, the loaded file's
;; `setq' then set globals instead, and restore silently restored nothing.
(defvar +persist/--name nil)
(defvar +persist/--mode nil)
(defvar +persist/--content nil)

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

(defvar +persist/include-names "\\`\\*\\(?:new\\|scratch\\)\\*\\(?:<[0-9]+>\\)?\\'"
  "Starred buffer names that hold the user's own text and are persisted.
Other starred buffers are generated (logs, sidebars, search results) and
are not; buffers the user named themselves (no leading `*') are.")

(defun +persist/--should-persist-p (buf)
  "Return non-nil if BUF holds text of the user's own worth keeping.
That is a non-file, non-empty, editable text, prog or fundamental buffer
named *new*/*scratch* or named by the user, and none of the generated
buffers in `+persist/exclude-patterns'."
  (and (buffer-live-p buf)
       (not (buffer-file-name buf))
       (> (buffer-size buf) 0)
       (let ((name (buffer-name buf)))
         (and (or (string-match-p +persist/include-names name)
                  (not (string-match-p "\\`[* ]" name)))
              (not (string-match-p "\\`CAPTURE-\\|stderr" name))
              (not (seq-some (lambda (pat) (string-match-p pat name))
                             +persist/exclude-patterns))))
       (with-current-buffer buf
         (and (not buffer-read-only)
              (null (get-buffer-process buf))
              (or (derived-mode-p 'text-mode 'prog-mode)
                  (eq major-mode 'fundamental-mode))))))

(defun +persist/--restorable-p (name mode)
  "Non-nil if a persisted buffer NAME in MODE (a string) is the user's own text.
The on-disk counterpart of `+persist/--should-persist-p'."
  (let ((mode (and mode (intern-soft mode))))
    (and (stringp name)
         (or (string-match-p +persist/include-names name)
             (not (string-match-p "\\`[* ]" name)))
         (not (string-match-p "\\`CAPTURE-\\|stderr" name))
         (not (seq-some (lambda (pat) (string-match-p pat name))
                        +persist/exclude-patterns))
         (or (eq mode 'fundamental-mode)
             ;; A mode not loaded here (org/markdown in batch) can't be
             ;; classified; keep it rather than move the user's text.
             (not (and mode (fboundp mode)))
             (autoloadp (symbol-function mode))
             (and mode (provided-mode-derived-p mode '(text-mode prog-mode)))))))

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
        (insert (format ";; -*- mode: emacs-lisp; coding: utf-8; lexical-binding: t -*-\n")
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
                         (+persist/--restorable-p +persist/--name +persist/--mode)
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

(defun +persist/prune ()
  "Move persisted files that are not the user's own text out of the way.
They go to a dated sibling directory (nothing is deleted).  Returns the
number moved."
  (interactive)
  (let ((backup (concat (directory-file-name +persist/directory)
                        (format-time-string ".pruned-%Y%m%d/")))
        (moved 0))
    (dolist (file (and (file-directory-p +persist/directory)
                       (directory-files +persist/directory t "\\.el\\'")))
      (let (+persist/--name +persist/--mode +persist/--content)
        (ignore-errors (load file nil t t))
        (unless (+persist/--restorable-p +persist/--name +persist/--mode)
          (make-directory backup t)
          (rename-file file (expand-file-name (file-name-nondirectory file) backup) t)
          (cl-incf moved))))
    (when (called-interactively-p 'any)
      (message "Moved %d generated buffers to %s" moved backup))
    moved))

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
  ;; Killing a persisted buffer discards it.  (This used to check
  ;; `+persist/tracked-buffers', which nothing ever filled, so files were
  ;; never removed and 158 piled up.)
  (add-hook 'kill-buffer-hook #'+persist/--forget-killed-h))

(defun +persist/--forget-killed-h ()
  "Delete the persisted copy of the buffer being killed, if any."
  (unless (buffer-file-name)
    (+persist/remove (current-buffer))))

;;;; Boot ────────────────────────────────────────────────────────────────────

(unless noninteractive (+persist/enable))

(map! :leader
      (:prefix "b"
       :desc "Save persist buffers" "P" #'+persist/save-all))

(provide '+persist)
;;; +persist.el ends here
