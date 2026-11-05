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
(require 'ring)

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

;; A CPU profile is blind to waits: the 07:37 freeze of 2026-10-30 held
;; Emacs for over 20 s with 1.8 s of samples, so it was blocked on a
;; process, the network or a file.  Each recording gets a .txt beside it:
;; the last commands (names only, never keys), the live subprocesses and
;; the echo area, which is what the wait was most likely about.

(defvar +perf--freeze-commands (make-ring 20)
  "Recent (TIME . COMMAND) pairs, newest first.")

(defun +perf--freeze-note-command-h ()
  (when (symbolp this-command)
    (ring-insert +perf--freeze-commands (cons (float-time) this-command))))

(defun +perf-freeze-context (gap)
  "What Emacs was doing around a freeze of GAP seconds, as text."
  (let ((now (float-time)))
    (concat
     (format "Frozen for %.0f s, recovered %s\n\nLast commands (seconds ago):\n"
             gap (format-time-string "%F %T"))
     (mapconcat (lambda (c) (format "  %6.0f  %s" (- now (car c)) (cdr c)))
                (ring-elements +perf--freeze-commands) "\n")
     "\n\nLive processes:\n"
     (mapconcat (lambda (p)
                  (format "  %s [%s] %s" (process-name p) (process-status p)
                          (string-join (ensure-list (process-command p)) " ")))
                (process-list) "\n")
     (format "\n\nEcho area: %s\n" (or (current-message) "")))))

;; A suspended laptop looks like a freeze to a wall-clock timer: on
;; 2026-11-03 the recorder reported "frozen for 208409 s" after a 58-hour
;; sleep.  The kernel counts completed suspends; a gap during which the
;; count changed was sleep, not Emacs.

(defvar +perf-suspend-count-file "/sys/power/suspend_stats/success"
  "Kernel counter of completed suspends; nil to treat every gap as a freeze.")

(defvar +perf--suspend-count nil "The suspend count at the last tick.")

(defun +perf--suspend-count ()
  "Completed suspends so far, or nil when unknown."
  (and +perf-suspend-count-file
       (ignore-errors
         (with-temp-buffer
           (insert-file-contents +perf-suspend-count-file)
           (string-to-number (buffer-string))))))

(defun +perf--cpu-log ()
  "The CPU profiler's samples so far (the profiler starts a new log), or nil.
Exporting them can fail (\"Stack overflow in equal\" on some object in a
sampled backtrace; seen on Emacs 32.0.50).  The C log is then never freed,
so every later export fails too: the recorder turns itself off, once, and
says so, instead of an error every 30 seconds.  A restart clears it."
  (condition-case err
      (profiler-cpu-log)
    (error
     (+perf-freeze-recorder-mode -1)
     (profiler-cpu-stop)
     (message "Freeze recorder off: Emacs can't read its CPU profile any more (%s); restarting Emacs clears it"
              (error-message-string err))
     nil)))

(defun +perf--freeze-tick ()
  (let* ((now (float-time))
         (suspends (+perf--suspend-count))
         (gap (and (or (null suspends) (eql suspends +perf--suspend-count))
                   (+perf-freeze-gap now +perf--freeze-last))))
    (setq +perf--freeze-last now
          +perf--suspend-count suspends
          +perf--freeze-ticks (1+ +perf--freeze-ticks))
    (unless (profiler-cpu-running-p) (profiler-cpu-start profiler-sampling-interval))
    (cond
     (gap
      (let ((file (expand-file-name (format-time-string "freeze-%Y%m%d-%H%M%S.prof")
                                    +perf-freeze-dir)))
        (make-directory +perf-freeze-dir t)
        ;; Before our own message replaces the echo area.
        (write-region (+perf-freeze-context gap) nil
                      (concat (file-name-sans-extension file) ".txt") nil 'silent)
        ;; `profiler-cpu-profile' wraps the variable that `profiler-stop' fills;
        ;; the live samples come from the function `profiler-cpu-log'.
        (when-let* ((log (+perf--cpu-log)))
          (profiler-write-profile
           (profiler-make-profile :type 'cpu :timestamp (current-time) :log log)
           file))
        (message "Emacs was frozen for %.0f s; profile: %s" gap file)
        (when (executable-find "notify-send")
          (call-process "notify-send" nil 0 nil "-a" "Emacs" "-u" "critical"
                        (format "Emacs was frozen for %.0f s" gap)
                        (format "Profile and context saved: %s (.txt)\nM-x profiler-find-profile"
                                (abbreviate-file-name file))))))
     ;; Keep only the last minute or so, so a recording shows the freeze.
     ((zerop (% +perf--freeze-ticks 30))
      (+perf--cpu-log)))))

(define-minor-mode +perf-freeze-recorder-mode
  "Record a CPU profile of every freeze longer than `+perf-freeze-threshold'."
  :global t
  :group 'convenience
  (when +perf--freeze-timer (cancel-timer +perf--freeze-timer))
  (setq +perf--freeze-timer nil +perf--freeze-last nil)
  (remove-hook 'pre-command-hook #'+perf--freeze-note-command-h)
  (when +perf-freeze-recorder-mode
    (add-hook 'pre-command-hook #'+perf--freeze-note-command-h)
    (unless (profiler-cpu-running-p) (profiler-cpu-start profiler-sampling-interval))
    (setq +perf--freeze-timer (run-with-timer 2 2 #'+perf--freeze-tick))))

(unless noninteractive (+perf-freeze-recorder-mode 1))


;;;; pulsar resolves its command aliases once, not per buffer

;; `pulsar-mode' is buffer-local and turned on in every new buffer and after
;; every major-mode change; each time it calls
;; `pulsar-resolve-function-aliases', which scans the whole obarray twice
;; for aliases of ~110 commands: 50 ms in a fresh daemon, 209 ms after some
;; hours (freeze profile of 2026-10-30, opening *familiar*).  The result
;; only changes when code loads (new aliases) or the lists are replaced, so
;; it's computed again only then.

(defvar pulsar-pulse-functions)
(defvar pulsar-pulse-region-functions)

(defvar +perf--pulsar-resolved nil
  "(LOAD-HISTORY-LENGTH PULSE-FUNCTIONS REGION-FUNCTIONS) after the last run.")

(defun +perf-pulsar-resolve-once-a (fn)
  "Around `pulsar-resolve-function-aliases' (FN): skip when nothing changed."
  (unless (and +perf--pulsar-resolved
               (= (car +perf--pulsar-resolved) (length load-history))
               (eq (nth 1 +perf--pulsar-resolved) pulsar-pulse-functions)
               (eq (nth 2 +perf--pulsar-resolved) pulsar-pulse-region-functions))
    (funcall fn)
    (setq +perf--pulsar-resolved (list (length load-history)
                                       pulsar-pulse-functions
                                       pulsar-pulse-region-functions))))

(with-eval-after-load 'pulsar
  (advice-add 'pulsar-resolve-function-aliases :around #'+perf-pulsar-resolve-once-a))


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
    (let ((kill-ring (+perf-kills-to-persist (+perf--without-secrets (+perf-persistable-kills kill-ring)))))
      (cl-progv vars vals (apply fn args)))))
(advice-add 'savehist-save :around #'+perf-savehist-filter-a)



;;;; The kill ring's archive: never discarded, not loaded at startup

;; savehist reads the whole kill ring at startup (9,759 kills: 76 ms on
;; 2026-11-05, growing with every kill).  The newest `+perf-kill-keep' stay
;; there; older ones go, once each, into an append-only archive that only
;; SPC i Y reads (the live ring, then the archive, newest first).  Nothing
;; is discarded; M-y stays quick.

(defvar +perf-kill-keep 3000
  "Kills persisted in savehist; older ones go to `+perf-kill-archive-file'.")

(defvar +perf-kill-archive-file
  (expand-file-name "kill-archive.eld" (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  "Kills too old for savehist, one printed string per line, oldest first.")

(defvar +perf--kill-archived nil "md5s of archived kills (loaded on first use).")

(defun +perf--kill-archive-read ()
  "Every archived kill, oldest first."
  (when (file-readable-p +perf-kill-archive-file)
    (with-temp-buffer
      (insert-file-contents +perf-kill-archive-file)
      (let (out)
        (goto-char (point-min))
        (condition-case nil (while t (push (read (current-buffer)) out)) (end-of-file nil))
        (nreverse out)))))

(defun +perf-kill-archive (kills)
  "Append KILLS (newest first) not yet archived to the archive."
  (unless +perf--kill-archived
    (setq +perf--kill-archived (make-hash-table :test #'equal))
    (dolist (k (+perf--kill-archive-read)) (puthash (md5 k) t +perf--kill-archived)))
  (let ((new (seq-remove (lambda (k) (gethash (md5 k) +perf--kill-archived)) (reverse kills))))
    (when new
      (make-directory (file-name-directory +perf-kill-archive-file) t)
      (with-temp-buffer
        (dolist (k new) (puthash (md5 k) t +perf--kill-archived) (prin1 (substring-no-properties k) (current-buffer)) (insert "\n"))
        (let ((coding-system-for-write 'utf-8-emacs)) (write-region nil nil +perf-kill-archive-file 'append 'silent))))
    (length new)))

(defun +perf-kills-to-persist (kills)
  "The newest `+perf-kill-keep' of KILLS; the rest archived on the way."
  (when (> (length kills) +perf-kill-keep)
    (+perf-kill-archive (nthcdr +perf-kill-keep kills)))
  (seq-take kills +perf-kill-keep))

(defun +kill/yank-archived ()
  "Yank any kill ever: the live ring, then the archive (newest first)."
  (interactive)
  (let* ((all (delete-dups (append (mapcar #'substring-no-properties kill-ring)
                                   (nreverse (+perf--kill-archive-read)))))
         (pick (completing-read (format "Yank (%d kills): " (length all))
                                (lambda (s p a) (if (eq a 'metadata) '(metadata (display-sort-function . identity))
                                                  (complete-with-action a all s p)))
                                nil t)))
    (insert pick)))

(map! :leader :desc "Yank from every kill (archive too)" "i Y" #'+kill/yank-archived)
;;;; doom-modeline in git worktrees: a glyph no font has

;; In a git worktree doom-modeline's vcs segment shows nf-cod-worktree,
;; U+EC7E: nerd-icons knows it, no released Nerd Font (3.4.0 included) has
;; it.  doom-modeline measures the right half with `string-pixel-width' on
;; every redisplay, and a glyph without a font sends Emacs through every
;; font each time: 175 ms per measure, ~4 a second idle in the Turm worktree
;; buffers (measured 2026-11-04; reported as input lag).  A codicon that
;; exists says the same: nf-cod-repo_forked, U+EA63, 0.04 ms.
(defvar +perf-modeline-icon-substitutes
  '(("nf-cod-worktree" . "nf-cod-repo_forked"))
  "Icon names doom-modeline asks for that no installed font has → stand-ins.")

(defun +perf-modeline-icon-a (args)
  "Swap icon names in ARGS of `doom-modeline-vcs-icon' for ones fonts have."
  (if-let* ((sub (cdr (assoc (car args) +perf-modeline-icon-substitutes))))
      (cons sub (cdr args))
    args))

(with-eval-after-load 'doom-modeline
  (advice-add 'doom-modeline-vcs-icon :filter-args #'+perf-modeline-icon-a))

;;;; The first frame of the daemon

;; Profiled 2026-11-04 in a throwaway daemon: the first frame took 0.76 s
;; (a second one 0.43 s).  Of that, 104 ms were garbage collection while
;; the frame was built, and 57 ms Doom's dashboard looking up the keys of
;; its seven menu entries with `where-is-internal' over every keymap, on
;; every draw.  The theme (78 ms) and the display connection (93 ms) stay:
;; a daemon can't load a theme before it has a display.

(defvar gcmh-mode)
(defvar gcmh-high-cons-threshold)
(defvar +perf--gc-restore nil "The GC threshold to restore once idle after a new frame.")
(defun +perf-frame-without-gc-a (fn &rest args)
  "Build and show a frame (FN) before collecting garbage: at idle, after.
Binding the threshold around FN only moved the GC (104 ms grew to 254)
to just after, still before the frame was drawn."
  ;; Two frames within the second: the first one's value is the one to restore.
  (unless +perf--gc-restore
    (setq +perf--gc-restore (if (bound-and-true-p gcmh-mode) gcmh-high-cons-threshold gc-cons-threshold)
          gc-cons-threshold most-positive-fixnum)
    (run-with-idle-timer 1 nil (lambda ()
                                 (setq gc-cons-threshold +perf--gc-restore
                                       +perf--gc-restore nil))))
  (apply fn args))
(advice-add 'server-create-window-system-frame :around #'+perf-frame-without-gc-a)

(defvar +perf--where-is-cache (make-hash-table :test #'eq)
  "COMMAND → its first global key, for the dashboard menu.")

(defun +perf-dashboard-keys-once-a (fn &rest args)
  "Run the dashboard menu (FN) with its key lookups remembered."
  (let ((where-is (symbol-function 'where-is-internal)))
    (cl-letf (((symbol-function 'where-is-internal)
               (lambda (cmd &optional maps firstonly &rest rest)
                 ;; Only the slow one: all keymaps (MAPS nil).  The dashboard's
                 ;; own maps are small, and keymaps make poor hash keys.
                 (if (and firstonly (null maps) (symbolp cmd))
                     (with-memoization (gethash cmd +perf--where-is-cache)
                       (apply where-is cmd maps firstonly rest))
                   (apply where-is cmd maps firstonly rest)))))
      (apply fn args))))
(advice-add '+dashboard-widget-shortmenu :around #'+perf-dashboard-keys-once-a)
;; Bindings changed: look again.
(add-hook 'doom-after-reload-hook (lambda () (clrhash +perf--where-is-cache)))

(defvar +dashboard-menu-sections)
(defun +perf-dashboard-warm-h ()
  "Look the dashboard's keys up while the daemon waits for its first frame."
  (when (and (daemonp) (boundp '+dashboard-menu-sections))
    (run-with-idle-timer
     1 nil (lambda ()
             (dolist (section +dashboard-menu-sections)
               (let ((action (plist-get (cdr section) :action)))
                 (when (fboundp action)
                   (puthash action (where-is-internal action nil t) +perf--where-is-cache))))))))
(add-hook 'doom-after-init-hook #'+perf-dashboard-warm-h)


;;;; M-S-x (execute-extended-command-for-buffer) without the freeze

;; M-X offers the commands relevant to the buffer: marked for its modes, or
;; bound in its keymaps.  Emacs asks `where-is-internal' once per command
;; (11,099 of them): 7.7–9.9 s for one pass in an Org buffer, and vertico
;; filters again as you type, so the UI froze and the fans spun up.  Here
;; the keymaps are walked once per M-X into a table: 0.09 s, and the same
;; commands plus those bound through remaps (`[remap fill-paragraph]').

(defun +perf--bound-commands (map table seen &optional remap)
  "Put every command bound in keymap MAP (prefix maps too) into TABLE.
Under a remap, the remapped commands count as well."
  (when (and map (not (gethash map seen)))
    (puthash map t seen)
    (map-keymap
     (lambda (event def)
       (when (and remap (symbolp event) (commandp event)) (puthash event t table))
       (let ((def (pcase def
                    (`(menu-item ,_ ,cmd . ,_) cmd)
                    ((and `(,(pred stringp) . ,cmd) (guard (not (keymapp def)))) cmd)
                    (_ def))))
         (cond ((keymapp def)
                (+perf--bound-commands (if (symbolp def) (symbol-function def) def)
                                       table seen (eq event 'remap)))
               ((and (symbolp def) (commandp def)) (puthash def t table)))))
     map)))

(defun +perf-command-for-buffer-a ()
  "Override `command-completion--command-for-this-buffer-function'."
  (let ((bound (make-hash-table :test #'eq))
        (seen (make-hash-table :test #'eq)))
    (dolist (map (nconc (and (current-local-map) (list (current-local-map)))
                        (mapcar #'cdr (seq-filter (lambda (e) (symbol-value (car e)))
                                                  minor-mode-map-alist))))
      (+perf--bound-commands map bound seen))
    (lambda (symbol buffer)
      (or (command-completion-using-modes-p symbol buffer)
          (and (gethash symbol bound)
               (or (null (get symbol 'completion-predicate))
                   (funcall (get symbol 'completion-predicate) symbol buffer)))))))
(advice-add 'command-completion--command-for-this-buffer-function
            :override #'+perf-command-for-buffer-a)

(provide '+perf)
;;; +perf.el ends here
