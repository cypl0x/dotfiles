;;; lisp/+perf.el --- Performance fixes, each found by measurement -*- lexical-binding: t; -*-
;;
;; Opening a remote /etc file on a NixOS host (e.g. /ssh:inari:/etc/hosts)
;; froze Emacs at 100% CPU.  /etc files there are symlinks into /nix/store,
;; and on `find-file-hook' doom-modeline asks projectile for the project root,
;; which lists every directory up the tree, so all of remote /nix/store
;; (~80k entries).  TRAMP's `file-name-all-completions' skeleton then merges
;; that listing with `seq-union', which is quadratic: 2.0 s for 8k entries,
;; 4x per doubling, minutes for the store.  Measured 2026-10-30 in `emacs -Q'
;; (seq 2.24 and Emacs 32's built-in seq alike); see JOURNAL.org.
;;
;; Two independent fixes:
;;  1. The store is immutable and never a project: projectile stops looking
;;     for a root inside it, so the listing never happens.
;;  2. `seq-union' on two lists with `equal' semantics runs in linear time,
;;     same result and order, so big remote directories complete quickly.
;;
;;; Code:

(require 'cl-lib)
(require 'seq)

(defun +perf-nix-store-p (path)
  "Non-nil if PATH, local or remote, lies in /nix/store.  Never connects."
  (and path
       (string-prefix-p "/nix/store/"
                        (or (file-remote-p path 'localname) path))))

(defun +perf-projectile-skip-store-a (fn &optional dir)
  "Around `projectile-project-root' (FN): no root for DIR in the store.
DIR defaults to `default-directory'."
  (unless (+perf-nix-store-p (or dir default-directory))
    (funcall fn dir)))

(with-eval-after-load 'projectile
  (advice-add 'projectile-project-root :around #'+perf-projectile-skip-store-a))

(defconst +perf-seq-union-threshold 64
  "Below this combined length the generic `seq-union' is fast enough.")

(cl-defmethod seq-union ((sequence1 list) (sequence2 list) &optional testfn)
  "Linear-time `seq-union' for lists compared with `equal'.
Same result and order as the generic method: SEQUENCE1's elements without
duplicates, then SEQUENCE2's that are new."
  (if (or (not (memq testfn '(nil equal)))
          (< (+ (length sequence1) (length sequence2)) +perf-seq-union-threshold))
      (cl-call-next-method)
    (let ((seen (make-hash-table :test #'equal
                                 :size (+ (length sequence1) (length sequence2))))
          result)
      (dolist (seq (list sequence1 sequence2))
        (dolist (elt seq)
          (unless (gethash elt seen)
            (puthash elt t seen)
            (push elt result))))
      (nreverse result))))


;;;; eldoc's command list, in one pass

;; Loading eldoc registers its default commands with one
;; `eldoc-add-command-completions' call over ~34 prefixes, each scanning the
;; whole obarray (120k symbols here): 898 ms of every daemon start (measured
;; 2026-10-30).  One pass testing all prefixes gives the same set, ~11x
;; faster.  Falls back to the original for few names or when
;; `completion-regexp-list' would change `all-completions' results.

(declare-function eldoc-add-command "eldoc" (&rest cmds))

(defun +perf-eldoc-add-command-completions-a (fn &rest names)
  "Around `eldoc-add-command-completions' (FN): one obarray pass for NAMES."
  (if (or completion-regexp-list (< (length names) 3))
      (apply fn names)
    (let ((re (concat "\\`" (regexp-opt names)))
          (case-fold-search completion-ignore-case)
          cmds)
      (mapatoms (lambda (s)
                  (when (and (commandp s) (string-match-p re (symbol-name s)))
                    (push (symbol-name s) cmds))))
      (apply #'eldoc-add-command cmds))))

(advice-add 'eldoc-add-command-completions :around
            #'+perf-eldoc-add-command-completions-a)


;;;; Fewer, not shorter, garbage collections

;; One collection here takes ~0.18 s whatever the threshold; its cost grows
;; with the live heap (26 MB strings, 3.6 M vector slots on 2026-10-30).
;; gcmh raises the threshold to 64 MB only while a command runs; between
;; commands it stays at Emacs's 800 KB, where timers, process output and
;; idle work allocate.  That session logged 4,560 collections in 94 minutes,
;; 773 s of GC, ~14% of wall time; at 64 MB that count would have meant
;; ~290 GB allocated, at 800 KB ~3.6 GB, so they ran at the low threshold.
;; 16 MB makes those up to 20x rarer for at most 16 MB more garbage.
(defvar gcmh-low-cons-threshold)
(with-eval-after-load 'gcmh
  (setq gcmh-low-cons-threshold (* 16 1024 1024)))


;;;; Freeze recorder: the next long freeze diagnoses itself

;; Twice the session froze at 100% CPU for minutes (2026-10-30), with no way
;; to look inside while it lasted, and a later profiler report had already
;; consumed the evidence.  This keeps the CPU profiler sampling, resets its
;; log every minute while all is well, and when a 2 s timer finds it was
;; held up for more than `+perf-freeze-threshold' seconds, writes the log
;; (the freeze plus at most a minute before it) to `+perf-freeze-dir' and
;; says so.  Open a recording with M-x profiler-find-profile.

(require 'profiler)

(defvar +perf-freeze-threshold 20
  "Seconds without the timer running that count as a freeze.")

(defvar +perf-freeze-dir (expand-file-name "freezes/" (bound-and-true-p doom-cache-dir))
  "Where freeze profiles are written.")

(defvar +perf--freeze-last nil "When the freeze timer last ran.")
(defvar +perf--freeze-ticks 0)
(defvar +perf--freeze-timer nil)

(defun +perf-freeze-gap (now last)
  "Seconds NOW lags behind LAST beyond the 2 s period, if a freeze; else nil."
  (and last (> (- now last 2) +perf-freeze-threshold) (- now last 2)))

(defun +perf--freeze-tick ()
  (let* ((now (float-time))
         (gap (+perf-freeze-gap now +perf--freeze-last)))
    (setq +perf--freeze-last now
          +perf--freeze-ticks (1+ +perf--freeze-ticks))
    (unless (profiler-cpu-running-p) (profiler-cpu-start profiler-sampling-interval))
    (cond
     (gap
      (let ((file (expand-file-name (format-time-string "freeze-%Y%m%d-%H%M%S.prof")
                                    +perf-freeze-dir)))
        (make-directory +perf-freeze-dir t)
        ;; `profiler-cpu-profile' wraps the variable that `profiler-stop' fills;
        ;; the live samples come from the function `profiler-cpu-log'.
        (when-let* ((log (profiler-cpu-log)))
          (profiler-write-profile
           (profiler-make-profile :type 'cpu :timestamp (current-time) :log log)
           file))
        (message "Emacs was frozen for %.0f s; profile: %s" gap file)
        (when (executable-find "notify-send")
          (call-process "notify-send" nil 0 nil "-a" "Emacs" "-u" "critical"
                        (format "Emacs was frozen for %.0f s" gap)
                        (format "CPU profile saved: %s\nM-x profiler-find-profile"
                                (abbreviate-file-name file))))))
     ;; Keep only the last minute or so, so a recording shows the freeze.
     ((zerop (% +perf--freeze-ticks 30))
      (profiler-cpu-log)))))

(define-minor-mode +perf-freeze-recorder-mode
  "Record a CPU profile of every freeze longer than `+perf-freeze-threshold'."
  :global t
  :group 'convenience
  (when +perf--freeze-timer (cancel-timer +perf--freeze-timer))
  (setq +perf--freeze-timer nil +perf--freeze-last nil)
  (when +perf-freeze-recorder-mode
    (unless (profiler-cpu-running-p) (profiler-cpu-start profiler-sampling-interval))
    (setq +perf--freeze-timer (run-with-timer 2 2 #'+perf--freeze-tick))))

(unless noninteractive (+perf-freeze-recorder-mode 1))


;;;; What savehist writes of the kill ring

;; kill-ring-max is unlimited on purpose (config.el), and Doom persists the
;; kill ring.  On 2026-10-30 that made savehist 11.5 MB (doom doctor: "may
;; cause ... odd startup delays"): 8,950 entries, 109 of them over 10 k chars
;; holding 9.3 MB, the largest 3.2 MB; and 8 Claude API keys in plain text.
;; Only the saved copy is filtered; the live kill ring keeps everything.

(defvar +perf-savehist-max-kill 65536
  "Kill-ring entries longer than this many characters are not persisted.")

(defvar +perf-secret-regexp
  (concat "sk-ant-[a-z0-9]+-[A-Za-z0-9_-]\\{20,\\}"   ; Anthropic
          "\\|gh[pousr]_[A-Za-z0-9]\\{30,\\}\\|github_pat_[A-Za-z0-9_]\\{30,\\}"
          "\\|AKIA[0-9A-Z]\\{16\\}"                     ; AWS access key id
          "\\|xox[abprs]-[A-Za-z0-9-]\\{10,\\}"         ; Slack
          "\\|-----BEGIN [A-Z ]*PRIVATE KEY-----")
  "Kill-ring entries matching this are never written to disk.")

(defun +perf-persistable-kills (kills)
  "KILLS without entries too long or containing secrets."
  (seq-remove (lambda (s)
                (or (not (stringp s))
                    (> (length s) +perf-savehist-max-kill)
                    (let ((case-fold-search nil))
                      (string-match-p +perf-secret-regexp s))))
              kills))

(defvar savehist-minibuffer-history-variables)
(defvar savehist-additional-variables)

(defun +perf--without-secrets (items)
  "ITEMS without elements whose printed form contains a secret."
  (let ((case-fold-search nil))
    (seq-remove (lambda (x)
                  (string-match-p +perf-secret-regexp
                                  (if (stringp x) x (prin1-to-string x))))
                items)))

(defun +perf-savehist-filter-a (fn &rest args)
  "Around `savehist-save' (FN): persist filtered copies, never the live values.
Every list savehist writes (minibuffer histories, registers, ...) loses
elements containing secrets; the kill ring also loses huge entries."
  ;; `seq-uniq', not `delete-dups': `append' shares its last list, the live
  ;; `savehist-additional-variables', and `delete-dups' once dropped kill-ring
  ;; from it.  Entries may be (VAR . MAX-LENGTH).
  (let* ((vars (seq-filter (lambda (v) (and (not (eq v 'kill-ring))
                                           (boundp v) (listp (symbol-value v))))
                           (seq-uniq (mapcar (lambda (v) (if (consp v) (car v) v))
                                             (append (bound-and-true-p savehist-minibuffer-history-variables)
                                                     (bound-and-true-p savehist-additional-variables))))))
         (vals (mapcar (lambda (v)
                         (+perf--without-secrets (symbol-value v)))
                       vars)))
    ;; The kill ring also loses entries too long to persist.
    (let ((kill-ring (+perf--without-secrets (+perf-persistable-kills kill-ring))))
      (cl-progv vars vals (apply fn args)))))
(advice-add 'savehist-save :around #'+perf-savehist-filter-a)

(provide '+perf)
;;; +perf.el ends here
