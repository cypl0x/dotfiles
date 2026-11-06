;;; lisp/+wait.el --- Say what Emacs is waiting for, and that C-g stops it -*- lexical-binding: t; -*-
;;
;; A blocked Emacs looks the same whatever it waits for: a TRAMP connection
;; to a host that is off (132 s on 2026-11-06, /ssh: in SPC f f), a GitHub
;; listing (85 s on 2026-11-05), a download.  Both times the way out, C-g,
;; was not obvious.  Now, after `+wait-after' seconds of waiting, the echo
;; area says what for and for how long, every second:
;;
;;   Connecting to pi-zero-lan… 4 s (C-g stops it)
;;
;; A timer says it while url.el or gh-fs (lisp/+gh-fs.el) wait with
;; `accept-process-output'; `call-process' runs no timers, so gh-fs no
;; longer uses it.  TRAMP suspends timers while it connects, so there its
;; wait loop says it.  Places: `+wait-places', `+wait-poll-points'.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar +wait-after 2
  "Seconds of waiting before the echo area says what for.")

(defvar +wait--stack nil
  "What is being waited for, innermost first: (START . WHAT) pairs.")

(defvar +wait--timer nil)
(defvar +wait--said nil "Whether the echo area shows a wait now.")

(defvar +wait--last 0 "When the note was last updated.")

(defun +wait--poll (&rest _)
  "From inside a wait loop: the note, at most twice a second.
TRAMP suspends timers while it connects (`with-tramp-suspended-timers'),
so the timer never fires there; its loop calls this instead
\(`+wait-poll-points')."
  (when (and +wait--stack (> (float-time) (+ +wait--last 0.5)))
    (+wait--tick)))

(defun +wait--tick ()
  "Say what the innermost wait is for, once it is `+wait-after' old."
  (setq +wait--last (float-time))
  (when-let* ((w (car +wait--stack)))
    (let ((secs (- (float-time) (car w))))
      (when (>= secs +wait-after)
        (setq +wait--said t)
        (let ((message-log-max nil))
          (message "%s… %d s (C-g stops it)" (cdr w) (round secs)))
        ;; Blocked, Emacs doesn't redisplay by itself: the message
        ;; reached the screen only after the wait (seen in a tty).
        (redisplay t)))))

(defun +wait-call (what fn &rest args)
  "Call FN with ARGS; if that waits `+wait-after' seconds or more, say WHAT
\(a string, or a function returning one) is being waited for."
  (let ((what (if (functionp what) (ignore-errors (funcall what)) what)))
    (if (not (stringp what))
        (apply fn args)
      (let ((+wait--stack (cons (cons (float-time) what) +wait--stack)))
        (unless (timerp +wait--timer)
          (setq +wait--timer (run-with-timer 0.5 0.5 #'+wait--tick)))
        (unwind-protect (apply fn args)
          ;; The outermost wait ends: no more ticks, and our note goes.
          (when (null (cdr +wait--stack))
            (when (timerp +wait--timer) (cancel-timer +wait--timer))
            (setq +wait--timer nil)
            (when +wait--said
              (setq +wait--said nil)
              (let ((message-log-max nil)) (message nil)))))))))

;;;; Where Emacs waits

(defvar tramp-file-name-structure)
(declare-function tramp-file-name-host "tramp")
(declare-function url-host "url-parse")

(defvar +wait-places
  `((tramp-maybe-open-connection
     . ,(lambda (vec &rest _) (format "Connecting to %s" (tramp-file-name-host vec))))
    (url-retrieve-synchronously
     . ,(lambda (url &rest _)
          (format "Fetching %s" (if (stringp url) (url-host (url-generic-parse-url url)) (url-host url)))))
    (+gh-fs--api . ,(lambda (path &rest _) (format "GitHub: %s" path))))
  "Functions that wait, and how to say what for (from their arguments).")

(defun +wait--advice (describe)
  "An :around advice saying what DESCRIBE makes of the arguments."
  (lambda (fn &rest args)
    (apply #'+wait-call (lambda () (apply describe args)) fn args)))

(defvar +wait-poll-points '(tramp-accept-process-output)
  "Functions called over and over by wait loops that suspend timers.")

(defun +wait--install ()
  (pcase-dolist (`(,fn . ,describe) +wait-places)
    (advice-add fn :around (+wait--advice describe) '((name . +wait))))
  (dolist (fn +wait-poll-points)
    (advice-add fn :after #'+wait--poll)))

(+wait--install)

(provide '+wait)
;;; +wait.el ends here
