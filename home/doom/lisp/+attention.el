;;; lisp/+attention.el --- "This is slow": measure it, and an agent fixes it -*- lexical-binding: t; -*-
;;
;; SPC h !   attention: something is wrong right now
;;   l   +attention/lag   typing lags: for 30 s, every function on the
;;       keystroke path (pre/post-command, after-change, post-self-insert,
;;       pre-redisplay, …) and every command is timed, GC counted
;;   s   +attention/slow  Emacs is slow: a CPU profile over 30 s, the
;;       functions that took the time (inclusive and self)
;;   a   a snapshot of Emacs' state (buffers, modes, timers, hooks, processes)
;;
;; The measurement goes to a file, then to a dedicated agent session
;; (agent-shell, Claude Code, in ~/dotfiles) briefed as a performance
;; engineer: read the data, find the cause, fix it in the config, measure
;; again (it can, through emacsclient, with the same functions), and stop
;; when the numbers say it's fixed, with before and after.
;;
;; The measuring functions are safe to call from outside (they return at
;; once and write their result later): (+attention-measure-lag 30 FILE),
;; (+attention-measure-slow 30 FILE), (+attention-snapshot FILE).
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)

(declare-function profiler-start "profiler" (mode))
(declare-function profiler-stop "profiler" ())
(declare-function profiler-cpu-log "profiler" ())
(declare-function profiler-running-p "profiler" (&optional mode))
(declare-function agent-shell-insert "ext:agent-shell" (&rest args))
(declare-function agent-shell--start "ext:agent-shell" (&rest args))
(declare-function agent-shell-anthropic-make-claude-code-config "ext:agent-shell-anthropic" (&rest args))

(defvar +attention-dir (expand-file-name "attention/" (or (bound-and-true-p doom-cache-dir) user-emacs-directory))
  "Where measurements are written.")

(defvar +attention-seconds 30 "How long a measurement runs.")

(defun +attention--file (kind)
  (make-directory +attention-dir t)
  (expand-file-name (format-time-string (concat kind "-%Y%m%d-%H%M%S.txt")) +attention-dir))

(defun +attention--fn-name (f)
  (cond ((symbolp f) (symbol-name f))
        ((byte-code-function-p f) "#<bytecode>")
        ((functionp f) (truncate-string-to-width (format "%S" f) 70 nil nil "…"))
        (t (format "%S" f))))

;;;; State

(defun +attention--snapshot-text ()
  (let ((buf (window-buffer (selected-window))))
    (with-current-buffer buf
      (concat
       (format "Emacs %s, up %s, %d buffers, %d frames, GCs %d (%.1f s), gc-cons-threshold %s\n"
               emacs-version (emacs-uptime) (length (buffer-list)) (length (frame-list))
               gcs-done gc-elapsed gc-cons-threshold)
       (format "\nSelected buffer: %s (%s, %d chars)\n  minor modes: %s\n"
               (buffer-name) major-mode (buffer-size)
               (string-join (mapcar #'symbol-name local-minor-modes) " "))
       (cl-loop for hook in '(pre-command-hook post-command-hook after-change-functions before-change-functions
                              post-self-insert-hook pre-redisplay-functions window-scroll-functions
                              jit-lock-functions completion-at-point-functions eldoc-documentation-functions)
                concat (format "  %s: %s\n" hook
                               (mapconcat #'+attention--fn-name
                                          (append (and (boundp hook) (local-variable-p hook) (symbol-value hook))
                                                  (and (boundp hook) (default-value hook)))
                                          ", ")))
       "\nTimers (repeating or due soon):\n"
       (cl-loop for tm in (append timer-list timer-idle-list)
                concat (format "  %s%s %s\n"
                               (if (memq tm timer-idle-list) "idle " "")
                               (or (timer--repeat-delay tm) "once")
                               (+attention--fn-name (timer--function tm))))
       "\nProcesses:\n"
       (cl-loop for p in (process-list)
                concat (format "  %s %s %s\n" (process-name p) (process-status p)
                               (truncate-string-to-width (string-join (or (process-command p) '("")) " ") 80 nil nil "…")))
       "\nLargest buffers:\n"
       (cl-loop for b in (seq-take (sort (buffer-list) (lambda (a b) (> (buffer-size a) (buffer-size b)))) 10)
                concat (format "  %8d  %s (%s)\n" (buffer-size b) (buffer-name b) (buffer-local-value 'major-mode b)))))))

;;;###autoload
(defun +attention-snapshot (&optional file)
  "Write Emacs' state to FILE (or a new file); return the file."
  (let ((file (or file (+attention--file "snapshot"))))
    (with-temp-file file (insert (+attention--snapshot-text)))
    file))

;;;; Lag

(defconst +attention-lag-hooks
  '(pre-command-hook post-command-hook after-change-functions before-change-functions
    post-self-insert-hook pre-redisplay-functions window-scroll-functions jit-lock-functions)
  "Hooks on the path from a key to the screen, whose functions are timed.")

(defvar +attention--times nil "Hash: function name → (CALLS TOTAL MAX).")
(defvar +attention--advised nil)
(defvar +attention--commands nil "Hash: command → list of durations.")
(defvar +attention--command-start nil)

(defun +attention--timer-advice (name)
  (lambda (fn &rest args)
    (let ((start (float-time)))
      (unwind-protect (apply fn args)
        (let* ((d (- (float-time) start))
               (e (or (gethash name +attention--times) (list 0 0.0 0.0))))
          (puthash name (list (1+ (nth 0 e)) (+ (nth 1 e) d) (max (nth 2 e) d)) +attention--times))))))

(defun +attention--pre-command () (setq +attention--command-start (float-time)))
(defun +attention--post-command ()
  (when +attention--command-start
    (push (- (float-time) +attention--command-start)
          (gethash (or this-command 'unknown) +attention--commands))
    (setq +attention--command-start nil)))

(defun +attention--lag-start ()
  (setq +attention--times (make-hash-table :test #'equal)
        +attention--commands (make-hash-table :test #'eq)
        +attention--advised nil)
  (let (fns)
    (dolist (hook +attention-lag-hooks)
      (dolist (b (buffer-list))
        (when (local-variable-p hook b)
          (setq fns (append (buffer-local-value hook b) fns))))
      (when (boundp hook) (setq fns (append (default-value hook) fns))))
    ;; Lisp functions only (primitives are rarely the culprit; advising them is riskier).
    (dolist (f (delete-dups (seq-filter (lambda (f) (and (symbolp f) (fboundp f) (not (eq f t))
                                                         (not (subrp (indirect-function f)))))
                                        fns)))
      (let ((advice (+attention--timer-advice (symbol-name f))))
        (advice-add f :around advice '((name . +attention)))
        (push f +attention--advised))))
  (add-hook 'pre-command-hook #'+attention--pre-command -100)
  (add-hook 'post-command-hook #'+attention--post-command 100))

(defun +attention--percentile (sorted p)
  (nth (min (1- (length sorted)) (floor (* p (length sorted)))) sorted))

(defun +attention--lag-stop (gc0 gct0 seconds)
  (dolist (f +attention--advised) (advice-remove f '+attention))
  (remove-hook 'pre-command-hook #'+attention--pre-command)
  (remove-hook 'post-command-hook #'+attention--post-command)
  (let (fns cmds)
    (maphash (lambda (k v) (push (cons k v) fns)) +attention--times)
    (maphash (lambda (k v) (push (cons k (sort v #'<)) cmds)) +attention--commands)
    (concat
     (format "Input lag measurement: %d s, %d commands, %d GCs (%.0f ms in GC)\n\n"
             seconds (cl-loop for c in cmds sum (length (cdr c)))
             (- gcs-done gc0) (* 1000 (- gc-elapsed gct0)))
     "Commands (ms: median, 95th percentile, max, count):\n"
     (cl-loop for (cmd . ds) in (seq-take (sort cmds (lambda (a b) (> (car (last (cdr a))) (car (last (cdr b)))))) 25)
              concat (format "  %-40s %7.1f %7.1f %7.1f  %d\n" cmd
                             (* 1000 (+attention--percentile ds 0.5)) (* 1000 (+attention--percentile ds 0.95))
                             (* 1000 (car (last ds))) (length ds)))
     "\nHook functions on the keystroke path (ms: total, max single call, calls):\n"
     (cl-loop for (name calls total max) in (seq-take (sort fns (lambda (a b) (> (nth 2 a) (nth 2 b)))) 30)
              concat (format "  %-50s %8.1f %7.1f  %d\n" name (* 1000 total) (* 1000 max) calls))
     "\n" (+attention--snapshot-text))))

;;;###autoload
(defun +attention-measure-lag (&optional seconds file callback)
  "Time the keystroke path for SECONDS; write the report to FILE.
Returns at once (\"measuring until …\"); CALLBACK gets the file."
  (let ((seconds (or seconds +attention-seconds))
        (file (or file (+attention--file "lag")))
        (gc0 gcs-done) (gct0 gc-elapsed))
    (+attention--lag-start)
    (run-with-timer seconds nil
                    (lambda ()
                      (with-temp-file file (insert (+attention--lag-stop gc0 gct0 seconds)))
                      (when callback (funcall callback file))))
    (format "measuring until %s, report: %s" (format-time-string "%T" (time-add nil seconds)) file)))

;;;; Slow

(defun +attention--profile-text (log)
  "Top functions of profiler LOG (a hash: backtrace vector → samples)."
  (let ((incl (make-hash-table :test #'eq)) (self (make-hash-table :test #'eq)) (total 0))
    (maphash (lambda (bt n)
               (setq total (+ total n))
               (let ((seen nil))
                 (cl-loop for f across bt
                          when (and f (not (memq f seen)))
                          do (push f seen) (cl-incf (gethash f incl 0) n))
                 (when-let* ((leaf (cl-find-if #'identity bt))) (cl-incf (gethash leaf self 0) n))))
             log)
    (cl-flet ((top (h)
                (let (out) (maphash (lambda (k v) (push (cons k v) out)) h)
                     (seq-take (sort out (lambda (a b) (> (cdr a) (cdr b)))) 30))))
      (concat
       (format "CPU profile: %d samples\n\nInclusive (time in the function and what it called):\n" total)
       (cl-loop for (f . n) in (top incl)
                concat (format "  %5.1f%%  %s\n" (* 100.0 (/ n (float (max 1 total)))) (+attention--fn-name f)))
       "\nSelf (time in the function itself):\n"
       (cl-loop for (f . n) in (top self)
                concat (format "  %5.1f%%  %s\n" (* 100.0 (/ n (float (max 1 total)))) (+attention--fn-name f)))))))

;;;###autoload
(defun +attention-measure-slow (&optional seconds file callback)
  "Profile the CPU for SECONDS; write the top functions to FILE.
Returns at once; CALLBACK gets the file."
  (require 'profiler)
  (let ((seconds (or seconds +attention-seconds))
        (file (or file (+attention--file "slow"))))
    (when (profiler-running-p) (profiler-stop))
    (profiler-start 'cpu)
    (run-with-timer seconds nil
                    (lambda ()
                      (let ((log (ignore-errors (profiler-cpu-log))))
                        (profiler-stop)
                        (with-temp-file file
                          (insert (if (hash-table-p log) (+attention--profile-text log) "No profile (profiler-cpu-log failed)\n")
                                  "\n" (+attention--snapshot-text))))
                      (when callback (funcall callback file))))
    (format "profiling until %s, report: %s" (format-time-string "%T" (time-add nil seconds)) file)))

;;;; The agent

(defconst +attention-brief
  "You are an Emacs performance engineer working on Wolfhard's Doom Emacs \
(Emacs 32, pgtk, config in ~/dotfiles/home/doom: config.el/init.el/packages.el \
are deployed copies needing `nrs`; lisp/ is live).  He reported: %s.  \
A measurement taken while it happened is in %s; read it first.

Your job: find the cause from evidence, fix it, prove it's fixed, then stop.
1. Diagnose from the data.  Name the culprit (function, hook, mode, timer) \
and the mechanism.  If the data isn't enough, measure again from outside: \
`emacsclient -e '(+attention-measure-lag 20)'` or \
`emacsclient -e '(+attention-measure-slow 20)'` (they return at once and \
write a report file after N seconds; ask him to reproduce meanwhile), \
`emacsclient -e '(+attention-snapshot)'`.
2. Fix it in ~/dotfiles/home/doom/lisp (smallest change that removes the \
cause; never just disable a feature he uses without saying so).  Run \
home/doom/test/run.sh.  Load the changed file into his Emacs with \
`emacsclient -e '(load FILE nil t)'`.
3. Measure again the same way.  Compare before and after in numbers.
4. Stop when the numbers show the problem gone (say which numbers), or when \
you've found it's outside the config (say where).  Commit with a message \
saying cause, fix and before/after; end the message with \
\"Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\".

Never: kill, signal or restart his Emacs daemon; evaluate anything heavy in \
it (no full-buffer scans over large files, no package installs); send keys \
to his frames; print tokens or credential files.  Keep emacsclient \
evaluations small and their output short.  Be brief in your reports: \
cause, fix, numbers."
  "The brief of the attention agent: complaint and data file.")

(defvar +attention--agent nil "The last attention agent's buffer.")
(defvar shell-maker--busy)
(declare-function agent-shell-project-buffers "ext:agent-shell" (&optional cwd))

(defun +attention--idle-p (buf)
  (and (buffer-live-p buf) (not (buffer-local-value 'shell-maker--busy buf))))

(defun +attention--agent-for-job ()
  "An agent to brief: the last attention agent if idle; else, asked, an
idle agent in ~/dotfiles; else nil (start a dedicated one)."
  (or (and (+attention--idle-p +attention--agent) +attention--agent)
      (when-let* ((idle (seq-find #'+attention--idle-p
                                  (ignore-errors (agent-shell-project-buffers (expand-file-name "~/dotfiles/"))))))
        (and (y-or-n-p (format "Give this to the running agent %s? (n: a dedicated one) " (buffer-name idle)))
             idle))))

(defun +attention--hand-off (complaint file)
  "Brief an agent on COMPLAINT with the measurement FILE: a running idle
one if there is (see `+attention--agent-for-job'), else a dedicated one."
  (if (not (and (require 'agent-shell nil t) (require 'agent-shell-anthropic nil t)))
      (progn (find-file-other-window file)
             (message "No agent-shell here: the measurement is open; %s" file))
    (let* ((default-directory (expand-file-name "~/dotfiles/"))
           (buf (or (+attention--agent-for-job)
                    (agent-shell--start :config (agent-shell-anthropic-make-claude-code-config)
                                        :no-focus t :new-session t :session-strategy 'new))))
      (setq +attention--agent buf)
      (agent-shell-insert :text (format +attention-brief complaint file)
                          :submit t :no-focus t :shell-buffer buf)
      (display-buffer buf)
      (message "An agent is on it (%s); the data: %s" (buffer-name buf) file))))

;;;###autoload
(defun +attention/lag ()
  "Typing lags: measure the keystroke path for 30 s, then an agent fixes it."
  (interactive)
  (message "%s — keep typing where it lags"
           (+attention-measure-lag +attention-seconds nil
                                   (lambda (file) (+attention--hand-off "typing lags (input lag)" file)))))

;;;###autoload
(defun +attention/slow ()
  "Emacs is slow: profile for 30 s, then an agent fixes it."
  (interactive)
  (message "%s — do what is slow"
           (+attention-measure-slow +attention-seconds nil
                                    (lambda (file) (+attention--hand-off "Emacs is slow" file)))))


(defvar +perf-freeze-dir)
(declare-function profiler-read-profile "profiler" (filename))
(declare-function profiler-profile-log "profiler" (profile))

(defun +attention-profile-file-text (prof)
  "The profile PROF (a file `profiler-write-profile' wrote) as text."
  (require 'profiler)
  (+attention--profile-text (profiler-profile-log (profiler-read-profile prof))))

;;;###autoload
(defun +attention/last-freeze ()
  "The last freeze the recorder caught: its report and profile to an agent."
  (interactive)
  (let* ((txts (and (boundp '+perf-freeze-dir)
                    (directory-files +perf-freeze-dir t "\\`freeze-.*\\.txt\\'")))
         (txt (or (car (last txts)) (user-error "No freeze recorded yet")))
         (prof (concat (file-name-sans-extension txt) ".prof"))
         (file (+attention--file "freeze")))
    (with-temp-file file
      (insert-file-contents txt)
      (goto-char (point-max))
      (when (file-exists-p prof)
        (insert "\n\nCPU profile during the freeze (time in a subprocess or a"
                " blocking call doesn't show as CPU; the live processes above do):\n\n"
                (+attention-profile-file-text prof))))
    (+attention--hand-off (format "Emacs froze (%s)" (with-temp-buffer (insert-file-contents txt) (buffer-substring 1 (line-end-position))))
                          file)))
;;;###autoload
(defun +attention/snapshot ()
  "Emacs' state, in a buffer."
  (interactive)
  (find-file (+attention-snapshot)))

(transient-define-prefix +attention-menu ()
  "Something is wrong right now: measure it, and an agent fixes it."
  [["Measure, then an agent fixes it"
    ("l" "typing lags (30 s of typing)" +attention/lag)
    ("s" "Emacs is slow (30 s profile)" +attention/slow)
    ("f" "the last freeze (recorded)" +attention/last-freeze)]
   ["Look"
    ("a" "Emacs' state now" +attention/snapshot)]])

(map! :leader :desc "Attention: measure, agent fixes" "h !" #'+attention-menu)

(provide '+attention)
;;; +attention.el ends here
