;;; lisp/+watch.el --- Errors in the background: noticed, named, caught -*- lexical-binding: t; -*-
;;
;; A timer, hook or process that fails says so in *Messages* ("Error
;; running timer: …") and then again, unnoticed: minuet's 109 in one
;; evening, slender's every 0.25 s.  Now:
;;
;;   - the first time an error shows up, the echo area says so, once
;;   - its next occurrence is caught with a backtrace (a one-shot signal
;;     hook for exactly that error): which code it is; for a timer also its
;;     function's values (slender's held a killed buffer)
;;   - SPC h ! e: each one this session, how often, when, the backtrace;
;;     RET (or a) on one asks the assistant why and how to fix it
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function backtrace-to-string "backtrace" (&optional frames))
(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin))
(declare-function +usage-say-later "+usage" (text))

(defvar +watch-interval 2 "Seconds between looks at *Messages*.")

(defconst +watch--regexp
  (concat "^\\(Error running timer\\(?: ‘[^’\n]*’\\)?"
          "\\|Error in [^ \n]+ ([^)\n]*)"
          "\\|error in process \\(?:filter\\|sentinel\\)"
          "\\|Error in timer\\): \\(.*?\\)\\(?: \\[\\([0-9]+\\) times\\]\\)?$")
  "A background error line in *Messages*: where, the error, its repeats.")

(defvar +watch--errors (make-hash-table :test #'equal)
  "KEY → plist :where :error :count :first :last :backtrace :timer.")
(defvar +watch--pos nil "Where in *Messages* the last look ended.")
(defvar +watch--armed nil "(KEY SYMBOL HEAD): errors whose next signal is caught.")
(defvar +watch--capturing nil "Inside the signal hook (no recursion).")

(defun +watch--key (where error)
  "One key for the same error: numbers don't count."
  (replace-regexp-in-string "[0-9]+" "N" (concat where ": " error)))

(defun +watch--signature (error)
  "(SYMBOL . HEAD) to recognize ERROR's signal: its symbol and, when a
symbol, its first argument (timerp of wrong-type-argument)."
  (let* ((form (ignore-errors (car (read-from-string error))))
         (sym (if (consp form) (car form)
                (ignore-errors (intern (car (split-string (string-trim error "(" ")") "[ )]" t)))))))
    (when (and sym (symbolp sym))
      (cons sym (and (consp form) (symbolp (cadr form)) (cadr form))))))

;;;; Looking at *Messages*

(defun +watch--scan ()
  "New background errors in *Messages* since the last look."
  (let ((buf (messages-buffer)))
    (with-current-buffer buf
      (unless (and (markerp +watch--pos) (eq (marker-buffer +watch--pos) buf))
        (setq +watch--pos (copy-marker (point-min))))
      ;; From the start of the line: "[N times]" grows the last line in place.
      (save-excursion
        (goto-char +watch--pos)
        (beginning-of-line)
        (while (re-search-forward +watch--regexp nil t)
          (let* ((where (match-string-no-properties 1))
                 (error (match-string-no-properties 2))
                 (times (if (match-string 3) (string-to-number (match-string 3)) 1))
                 (key (+watch--key where error))
                 (old (gethash key +watch--errors)))
            (if old
                (plist-put old :count (max (plist-get old :count) times))
              (puthash key (list :where where :error error :count times
                                 :first (current-time) :last (current-time))
                       +watch--errors)
              (+watch--first-seen key where error))
            (plist-put (gethash key +watch--errors) :last (current-time))))
        (set-marker +watch--pos (line-beginning-position))))))

(defun +watch--first-seen (key where error)
  "Say once that something fails in the background; catch it next time."
  (when-let* ((sig (+watch--signature error)))
    (push (list key (car sig) (cdr sig)) +watch--armed)
    (+watch--arm))
  (let ((text (format "⚠ In the background: %s: %s  (SPC h ! e)"
                      where (truncate-string-to-width error 80 nil nil "…"))))
    (if (fboundp '+usage-say-later) (+usage-say-later text)
      (let ((message-log-max nil)) (message "%s" text)))))

;;;; Catching it

(defun +watch--arm ()
  "The signal hook on while errors wait to be caught (unless another one
is set: then nothing is caught)."
  (cond ((and +watch--armed (null signal-hook-function))
         (setq signal-hook-function #'+watch--signal-h))
        ((and (null +watch--armed) (eq signal-hook-function #'+watch--signal-h))
         (setq signal-hook-function nil))))

(defun +watch--timer-values ()
  "The values the running timer's function holds, if a timer runs now."
  (cl-loop for frame in (backtrace-frames)
           when (eq (cadr frame) 'timer-event-handler)
           return (let* ((timer (car (nth 2 frame)))
                         (fn (and (timerp timer) (timer--function timer))))
                    (when fn
                      (if (and (byte-code-function-p fn) (> (length fn) 2))
                          (format "%S" (aref fn 2))
                        (format "%S" fn))))))

(defun +watch--signal-h (sym data)
  "Catch the next signal of an armed error: its backtrace, once."
  (unless +watch--capturing
    (let ((+watch--capturing t))
      (when-let* ((armed (cl-find-if (lambda (a) (and (eq (nth 1 a) sym)
                                                      (or (null (nth 2 a))
                                                          (eq (nth 2 a) (car-safe data)))))
                                     +watch--armed)))
        (condition-case nil
            (progn
              (require 'backtrace)
              (let ((entry (gethash (car armed) +watch--errors)))
                (plist-put entry :backtrace (backtrace-to-string))
                (plist-put entry :timer (+watch--timer-values))))
          (error nil))
        (setq +watch--armed (delq armed +watch--armed))
        (+watch--arm)))))

(defvar +watch--timer nil)
(when (timerp +watch--timer) (cancel-timer +watch--timer))
(setq +watch--timer (run-with-timer +watch-interval +watch-interval #'+watch--scan))

;;;; SPC h ! e

(defvar-local +watch--entry nil)

(defun +watch/errors ()
  "The errors in the background this session: how often, when, which code."
  (interactive)
  (+watch--scan)
  (with-current-buffer (get-buffer-create "*Background errors*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (special-mode)
      (local-set-key (kbd "RET") #'+watch/ask)
      (local-set-key (kbd "a") #'+watch/ask)
      (if (zerop (hash-table-count +watch--errors))
          (insert "Nothing has failed in the background this session.\n")
        (insert (substitute-command-keys
                 "Errors in the background this session.  RET or a on one: ask the assistant.\n\n"))
        (let (entries)
          (maphash (lambda (_ e) (push e entries)) +watch--errors)
          (dolist (e (sort entries (lambda (a b) (time-less-p (plist-get b :last) (plist-get a :last)))))
            (let ((start (point)))
              (insert (propertize (format "%4d× " (plist-get e :count)) 'face 'error)
                      (format-time-string "%H:%M" (plist-get e :first))
                      (if (equal (format-time-string "%H:%M" (plist-get e :first))
                                 (format-time-string "%H:%M" (plist-get e :last)))
                          "        " (format-time-string "–%H:%M  " (plist-get e :last)))
                      (plist-get e :where) ": " (plist-get e :error) "\n")
              (cond ((plist-get e :backtrace)
                     (when-let* ((tv (plist-get e :timer)))
                       (insert (propertize (concat "      timer holds: " tv "\n") 'face 'shadow)))
                     (dolist (line (seq-take (split-string (plist-get e :backtrace) "\n" t) 12))
                       (insert (propertize (concat "      " (truncate-string-to-width line 150 nil nil "…") "\n")
                                           'face 'shadow))))
                    (t (insert (propertize "      (its backtrace is caught the next time it happens)\n"
                                           'face 'shadow))))
              (put-text-property start (point) '+watch-entry e)
              (insert "\n")))))
      (goto-char (point-min)))
    (pop-to-buffer (current-buffer))))

(defun +watch/ask ()
  "Ask the assistant about the error at point: which code, why, the fix."
  (interactive)
  (let ((e (or (get-text-property (point) '+watch-entry) (user-error "No error here"))))
    (familiar-ask
     (format "This keeps failing in the background of my Emacs (Doom):\n%s: %s (%d times)\n%s%s\nWhich code is it, why does it fail, and how do I fix it?"
             (plist-get e :where) (plist-get e :error) (plist-get e :count)
             (if-let* ((tv (plist-get e :timer))) (format "The timer's function holds: %s\n" tv) "")
             (if-let* ((bt (plist-get e :backtrace)))
                 (concat "Backtrace:\n" (truncate-string-to-width bt 4000 nil nil "…"))
               "(No backtrace caught yet.)"))
     t)))

(with-eval-after-load '+attention
  (transient-append-suffix '+attention-menu "a"
    '("e" "errors in the background" +watch/errors)))

(provide '+watch)
;;; +watch.el ends here
