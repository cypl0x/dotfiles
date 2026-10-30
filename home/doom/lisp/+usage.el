;;; lisp/+usage.el --- Which commands do I actually use, and by which keys? -*- lexical-binding: t; -*-
;;
;; Local, private evidence for keybinding decisions: every interactive command
;; is counted together with the key sequence that ran it (or "M-x").  Counts
;; are kept in memory, merged into `+usage-file' every few minutes and on exit.
;; Nothing leaves the machine.
;;
;;   M-x +usage-mode     start/stop counting (off by default)
;;   M-x +usage/report   commands by frequency, with keys used and keys bound
;;
;;; Code:

(require 'cl-lib)

(defvar +usage-file (locate-user-emacs-file "usage-counts.eld")
  "Where command counts persist: an alist ((COMMAND . ((KEYS . COUNT) ...)) ...).")

(defvar +usage-save-interval 300 "Seconds between saves.")

(defvar +usage-ignore
  '(self-insert-command org-self-insert-command evil-normal-state
    mwheel-scroll pixel-scroll-precision ignore handle-switch-frame
    keyboard-quit evil-force-normal-state)
  "Commands not worth counting.")

(defvar +usage--counts (make-hash-table :test #'eq)
  "COMMAND → hash of KEYS → count, since the last save.")

(defvar +usage--timer nil)

(defun +usage--record-h ()
  "Count `this-command' and how it was invoked."
  (when (and (symbolp this-command) this-command
             (not (memq this-command +usage-ignore)))
    (let* ((keys (this-command-keys-vector))
           (how (if (or (eq real-this-command 'execute-extended-command)
                        (zerop (length keys))
                        (memq (aref keys 0) '(?\M-x)))
                    "M-x"
                  (key-description keys)))
           (table (or (gethash this-command +usage--counts)
                      (puthash this-command (make-hash-table :test #'equal)
                               +usage--counts))))
      (cl-incf (gethash how table 0)))))

(defun +usage--read ()
  (when (file-readable-p +usage-file)
    (with-temp-buffer
      (insert-file-contents +usage-file)
      (ignore-errors (read (current-buffer))))))

(defun +usage--merged ()
  "Saved counts plus the unsaved ones, as an alist."
  (let ((all (copy-tree (+usage--read))))
    (maphash
     (lambda (cmd table)
       (let ((entry (or (assq cmd all)
                        (car (push (list cmd) all)))))
         (maphash (lambda (how n)
                    (let ((cell (assoc how (cdr entry))))
                      (if cell (cl-incf (cdr cell) n)
                        (push (cons how n) (cdr entry)))))
                  table)))
     +usage--counts)
    all))

(defun +usage-save ()
  "Merge unsaved counts into `+usage-file'."
  (when (> (hash-table-count +usage--counts) 0)
    (let ((data (+usage--merged))
          (print-length nil) (print-level nil))
      (make-directory (file-name-directory +usage-file) t)
      (with-temp-file +usage-file (prin1 data (current-buffer)))
      (clrhash +usage--counts))))

;;;###autoload
(define-minor-mode +usage-mode
  "Count interactive commands and the keys that run them."
  :group 'convenience
  :global t
  (if +usage-mode
      (progn
        (add-hook 'post-command-hook #'+usage--record-h)
        (add-hook 'kill-emacs-hook #'+usage-save)
        (setq +usage--timer (run-with-idle-timer +usage-save-interval t #'+usage-save)))
    (remove-hook 'post-command-hook #'+usage--record-h)
    (when +usage--timer (cancel-timer +usage--timer))
    (+usage-save)))

;;;###autoload
(defun +usage/report ()
  "Show commands by use, with the keys used and the keys bound."
  (interactive)
  (let ((rows (sort (mapcar (lambda (e)
                              (cons (car e) (cons (apply #'+ (mapcar #'cdr (cdr e)))
                                                  (cdr e))))
                            (+usage--merged))
                    (lambda (a b) (> (cadr a) (cadr b))))))
    (with-current-buffer (get-buffer-create "*usage*")
      (tabulated-list-mode)
      (setq tabulated-list-format [("Count" 7 t :right-align t) ("Command" 42 t)
                                   ("Invoked by" 40 nil) ("Bound to" 0 nil)])
      (setq tabulated-list-entries
            (cl-loop for (cmd n . hows) in rows
                     collect (list cmd
                                   (vector (number-to-string n) (symbol-name cmd)
                                           (mapconcat (lambda (h) (format "%s×%d" (car h) (cdr h)))
                                                      (seq-take (sort hows (lambda (a b) (> (cdr a) (cdr b)))) 3)
                                                      "  ")
                                           (or (ignore-errors
                                                 (key-description (where-is-internal cmd nil t)))
                                               "")))))
      (setq header-line-format
            (format " %d commands, %d invocations (local only)"
                    (length rows) (apply #'+ (mapcar #'cadr rows))))
      (tabulated-list-init-header)
      (tabulated-list-print)
      (pop-to-buffer (current-buffer)))))

;; Opt-in: M-x +usage-mode (or (+usage-mode 1) in config.el) to start counting.

(provide '+usage)
;;; +usage.el ends here
