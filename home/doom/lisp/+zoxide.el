;;; lisp/+zoxide.el --- zoxide's directory ranking, in Emacs too -*- lexical-binding: t; -*-
;;
;; `z' is one of the most run shell commands here (169 times on the
;; thinkpad, 56 on inari, Atuin and zsh history, 2026-11-04), and Emacs knew
;; nothing of its ranking.  Now:
;;
;;   SPC f z    jump to a directory by zoxide's ranking (score shown), into
;;              find-file there; C-u: dired it
;;
;; and every directory you visit in Emacs (files, dired) is added to zoxide,
;; so the shell's `z' and this share one ranking.  Without zoxide on PATH
;; nothing happens.
;;
;;; Code:

(defvar +zoxide-program (executable-find "zoxide")
  "The zoxide binary, or nil (then this file does nothing).")

(defvar +zoxide--last-added nil "The directory added last, not to repeat it.")

(defun +zoxide-add-h ()
  "Add this buffer's directory to zoxide's ranking (local directories only)."
  (when-let* ((dir (and +zoxide-program (not noninteractive)
                        (not (file-remote-p default-directory))
                        (expand-file-name default-directory))))
    (unless (equal dir +zoxide--last-added)
      (setq +zoxide--last-added dir)
      ;; Fire and forget: `zoxide add' takes ~1 ms, but no waiting either way.
      (let ((process-connection-type nil))
        (start-process "zoxide-add" nil +zoxide-program "add" "--" dir)))))

(defun +zoxide--candidates ()
  "zoxide's directories, best first: (DISPLAY . DIR)."
  (mapcar (lambda (line)
            (when (string-match "\\` *\\([0-9.]+\\) \\(.*\\)\\'" line)
              (let ((dir (match-string 2 line)))
                (cons (concat (abbreviate-file-name dir)
                              (propertize (format "  %s" (match-string 1 line)) 'face 'shadow))
                      dir))))
          (process-lines +zoxide-program "query" "--list" "--score")))

;;;###autoload
(defun +zoxide/find (&optional dired)
  "Find a file in a directory picked by zoxide's ranking; DIRED: open it."
  (interactive "P")
  (unless +zoxide-program (user-error "zoxide isn't installed"))
  (let* ((cands (delq nil (+zoxide--candidates)))
         (pick (completing-read
                "zoxide: "
                (lambda (str pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity)
                                 (category . file))
                    (complete-with-action action (mapcar #'car cands) str pred)))
                nil t))
         (dir (file-name-as-directory (cdr (assoc pick cands)))))
    (if dired
        (dired dir)
      (let ((default-directory dir))
        (call-interactively #'find-file)))))

(when (and +zoxide-program (not noninteractive))   ; not tests or batch runs
  (add-hook 'find-file-hook #'+zoxide-add-h)
  (add-hook 'dired-mode-hook #'+zoxide-add-h))

(map! :leader :desc "Directory by zoxide" "f z" #'+zoxide/find)

(provide '+zoxide)
;;; +zoxide.el ends here
