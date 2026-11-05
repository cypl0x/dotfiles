;;; lisp/+usage.el --- Which commands do I actually use, and by which keys? -*- lexical-binding: t; -*-
;;
;; Local, private evidence for keybinding decisions: every interactive command
;; is counted together with the key sequence that ran it (or "M-x").  Counts
;; are kept in memory, merged into `+usage-file' every few minutes and on exit.
;; Nothing leaves the machine.
;;
;;   M-x +usage-mode     start/stop counting (off by default)
;;   M-x +usage/report   commands by frequency, with keys used and keys bound
;;   M-x +usage/suggest  familiar reads the counts and suggests keys and shortcuts
;;   M-x +usage/time     time per mode, cancelled prompts and key prefixes
;;   M-x                 commands you run here (this mode, after this command) first
;;   SPC A .             anticipate: likely next commands here (C-u: ask the model)
;;   coach               after 12 j/l/DEL... in a row, the bigger steps bound
;;                       here, in the echo area (`+usage-coach' nil: off)
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


;; Sequences, for anticipating the next command: which command follows
;; which, and what each major mode sees most.  Local like the counts.
(defvar +usage-sequence-file (locate-user-emacs-file "usage-sequences.eld")
  "Where pair and per-mode counts persist: (:pairs ALIST :modes ALIST),
keys (PREVIOUS . COMMAND) and (MAJOR-MODE . COMMAND).")

(defvar +usage--pairs (make-hash-table :test #'equal) "Unsaved (PREV . CMD) → count.")
(defvar +usage--modes (make-hash-table :test #'equal) "Unsaved (MODE . CMD) → count.")
(defvar +usage--last nil "The last command counted.")
(defvar +usage--recent nil "The last 40 commands counted, newest first, as (CMD . MODE).")
(defvar +usage--timer nil)
(defvar +usage-coach) (defvar +usage-coach-after) (defvar +usage--run)   ; the coach, below
(declare-function familiar-ask "familiar-ask" (prompt &optional new))

(defvar +usage-runners '((execute-extended-command . "M-x"))
  "Commands that run another one (it sets `this-command'), and how that
counts: the one run is recorded, not the runner.")

(defun +usage--record-h ()
  "Count the command that ran and how it was invoked."
  ;; Keyboard macros replay keys nobody typed now (Claude's lab tests too):
  ;; not evidence of how you work.  `real-this-command', not `this-command':
  ;; commands rewrite the latter (`kill-region' sets it so the next kill
  ;; appends), which once filed 1,226 M-DEL (backward-kill-word) as
  ;; kill-region.  After M-x it is `execute-extended-command' itself.
  (let* ((runner (alist-get real-this-command +usage-runners))
         (this-command (if runner this-command real-this-command)))
  (when (and (symbolp this-command) this-command
             (not executing-kbd-macro)
             (not (memq this-command +usage-ignore)))
    (let* ((keys (this-command-keys-vector))
           (how (cond (runner runner)
                      ((and (> (length keys) 0) (memq (aref keys 0) '(?\M-x)))
                       "M-x")
                      ;; Timers, mouse-less remaps, programmatic calls.
                      ((zerop (length keys)) "(no keys)")
                      (t (key-description keys))))
           (table (or (gethash this-command +usage--counts)
                      (puthash this-command (make-hash-table :test #'equal)
                               +usage--counts))))
      (cl-incf (gethash how table 0))
      (when +usage--last
        (cl-incf (gethash (cons +usage--last this-command) +usage--pairs 0)))
      (setq +usage--run (if (eq this-command +usage--last) (1+ +usage--run) 1))
      (when (and +usage-coach (= +usage--run +usage-coach-after))
        (+usage--coach this-command +usage--run how))
      (when (equal how "M-x") (+usage--equivalent-hint this-command))
      (cl-incf (gethash (cons major-mode this-command) +usage--modes 0))
      (setq +usage--last this-command)
      (push (cons this-command major-mode) +usage--recent)
      (when (nthcdr 40 +usage--recent) (setcdr (nthcdr 39 +usage--recent) nil))))))



(defun +usage-fix-kill-region-counts ()
  "Move counts recorded as `kill-region' via word-deleting keys to
`backward-kill-word' / `kill-word' (recorded before `real-this-command')."
  (when-let* ((table (gethash 'kill-region +usage--counts)))
    (pcase-dolist (`(,keys . ,cmd) '(("M-DEL" . backward-kill-word) ("<M-backspace>" . backward-kill-word)
                                    ("C-<backspace>" . backward-kill-word) ("M-d" . kill-word)))
      (when-let* ((n (gethash keys table)))
        (remhash keys table)
        (let ((to (or (gethash cmd +usage--counts) (puthash cmd (make-hash-table :test #'equal) +usage--counts))))
          (cl-incf (gethash keys to 0) n))))))
;;;; Coach: long runs of one-step commands
;;
;; The counts showed held keys: j/k through PDFs (~1,900 line scrolls
;; against 220 half screens), l through Turm code (272 in a row), DEL in
;; Org.  After `+usage-coach-after' repeats of such a command, the echo area
;; names the bigger steps bound right here (looked up, never assumed), at
;; most once per command every `+usage-coach-quiet' seconds.

(defvar +usage-coach t "Whether to show tips after long runs of one-step commands.")
(defvar +usage-coach-after 12 "Repeats of one command before its tip.")
(defvar +usage-coach-quiet 600 "Seconds before the same tip again.")
(defvar +usage--run 0 "How many times `+usage--last' ran in a row.")
(defvar +usage--coached nil "Alist COMMAND → time of its last tip.")

(defvar +usage-coach-alternatives
  '((next-line              (evil-forward-paragraph . "paragraph") (org-next-visible-heading . "heading")
                            (+evil/next-section . "section") (evil-scroll-down . "half screen"))
    (evil-next-line         . next-line)
    (evil-next-visual-line  . next-line)
    (previous-line          (evil-backward-paragraph . "paragraph") (org-previous-visible-heading . "heading")
                            (evil-scroll-up . "half screen"))
    (evil-previous-line     . previous-line)
    (evil-previous-visual-line . previous-line)
    (evil-forward-char      (evil-forward-word-begin . "word") (evil-forward-word-end . "word end")
                            (evil-snipe-s . "to 2 chars") (evil-snipe-f . "to a char")
                            (evil-find-char . "to a char") (evil-end-of-line . "line end"))
    (evil-backward-char     (evil-backward-word-begin . "word") (evil-snipe-S . "back to 2 chars")
                            (evil-snipe-F . "back to a char") (evil-find-char-backward . "back to a char")
                            (evil-first-non-blank . "line start"))
    (evil-delete-backward-char-and-join (evil-delete-backward-word . "word") (backward-kill-word . "word")
                                        (evil-delete-back-to-indentation . "to line start"))
    (delete-backward-char   . evil-delete-backward-char-and-join)
    (vellumory-scroll-down  (vellumory-half-screen-down . "half screen") (vellumory-next-screen . "screen")
                            (vellumory-next-page . "page"))
    (vellumory-scroll-up    (vellumory-half-screen-up . "half screen") (vellumory-previous-screen . "screen")
                            (vellumory-previous-page . "page")))
  "One-step COMMAND → bigger steps (COMMAND . WHAT), or another entry to share.")

(defun +usage-coach-tip (command n &optional pressed)
  "The tip after N runs of COMMAND here, or nil: keys bound in this buffer.
PRESSED is the key that ran it, when known."
  (let* ((alts (alist-get command +usage-coach-alternatives))
         (alts (if (symbolp alts) (alist-get alts +usage-coach-alternatives) alts))
         (keys (lambda (cmd) (when-let* ((k (where-is-internal cmd nil t)))
                               (key-description k))))
         (own (if (and pressed (not (member pressed '("M-x" "(no keys)"))))
                  pressed
                (funcall keys command)))
         (seen nil)
         (parts (delq nil (mapcar (lambda (alt)
                                    (when-let* ((k (funcall keys (car alt)))
                                                ((not (member (cdr alt) seen))))
                                      (push (cdr alt) seen)
                                      (format "%s %s" (propertize k 'face 'help-key-binding) (cdr alt))))
                                  alts))))
    (when parts
      (format "%s×%d → %s"
              (if own (propertize own 'face 'help-key-binding) command) n
              (string-join (if (and own (string-match-p "\\`[hjkl]\\'" own))
                               (cons (format "%s%s" (propertize (format "%d%s" n own) 'face 'help-key-binding)
                                             " counted")
                                     parts)
                             parts)
                           " · ")))))

(defun +usage--coach (command n &optional pressed)
  (unless (or (minibufferp) executing-kbd-macro
              (when-let* ((last (alist-get command +usage--coached)))
                (< (float-time (time-since last)) +usage-coach-quiet)))
    (when-let* ((tip (+usage-coach-tip command n pressed)))
      (setf (alist-get command +usage--coached) (current-time))
      (let ((message-log-max nil)) (message "%s" tip)))))

;;;; M-x hint: the same thing has a key

;; Emacs names a key after M-x only for the command you ran.  The log had
;; unbound commands run by name whose twin is bound: kill-file-path (6×, the
;; same as SPC f y), count-words (4×; text stats are SPC P s).
(defvar +usage-equivalents
  '((kill-file-path . +default/yank-buffer-path)
    (kill-file-path-basename . +file/yank-name)
    (kill-file-path-basename-without-extension . +file/yank-base-name)
    (count-words . +prose/text-stats)
    (count-words-region . +prose/text-stats))
  "COMMAND run through M-x → a bound command doing the same.")

(defun +usage--equivalent-hint (command)
  "After M-x COMMAND: name the key of its bound twin, if it has one."
  (when-let* ((twin (alist-get command +usage-equivalents))
              (key (where-is-internal twin nil t)))
    (+usage-say-later (format "Next time: %s (%s)"
                              (propertize (key-description key) 'face 'help-key-binding)
                              twin))))

(defun +usage-say-later (text)
  "Show TEXT in a moment, after what the command itself said (not logged)."
  (run-at-time 1.5 nil
               (lambda ()
                 (let ((shown (current-message))
                       (message-log-max nil))
                   (message "%s%s%s" (or shown "") (if shown "   " "") text)))))

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
        (add-hook 'kill-emacs-hook #'+usage--save-sequences)
        (setq +usage--timer (run-with-idle-timer +usage-save-interval t
                                            (lambda () (+usage-save) (+usage--save-sequences)))))
    (remove-hook 'post-command-hook #'+usage--record-h)
    (when +usage--timer (cancel-timer +usage--timer))
    (+usage-save)
    (+usage--save-sequences)))

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

(defun +usage-summary (&optional n)
  "The N (default 80) most used commands, one line each, for a model to read."
  (let ((rows (sort (mapcar (lambda (e) (cons (car e) (cons (apply #'+ (mapcar #'cdr (cdr e))) (cdr e))))
                            (+usage--merged))
                    (lambda (a b) (> (cadr a) (cadr b))))))
    (mapconcat (lambda (row)
                 (pcase-let ((`(,cmd ,count . ,hows) row))
                   (format "%5d  %s  via %s  bound to %s"
                           count cmd
                           (mapconcat (lambda (h) (format "%s×%d" (car h) (cdr h)))
                                      (seq-take (sort (copy-sequence hows) (lambda (a b) (> (cdr a) (cdr b)))) 3)
                                      ", ")
                           (or (ignore-errors (key-description (where-is-internal cmd nil t))) "nothing"))))
               (seq-take rows (or n 80))
               "\n")))

(declare-function +usage-flows-summary "+usage-flows" (&optional days))

;;;###autoload
(defun +usage/suggest ()
  "Ask familiar for workflow suggestions from what you actually use."
  (interactive)
  (unless (fboundp 'familiar-ask) (user-error "familiar-ask isn't available"))
  (familiar-ask
   (concat "Here is how I use Emacs (counts of commands, how each was invoked, what it's bound to). "
           "Suggest concrete improvements: commands I run by M-x often that deserve a key "
           "(name a free one in Doom/evil), long key sequences I repeat that have shorter ones, "
           "chains of commands that want one command, built-in or package features that would "
           "replace what I do by hand.  Lead with the five with the most effect.\n\n"
           "#+begin_example\n" (+usage-summary) "\n#+end_example"
           ;; The order too: chains repeated, undone, retried (lisp/+usage-flows.el).
           (let ((flows (and (fboundp '+usage-flows-summary) (+usage-flows-summary))))
             (if (string-empty-p (or flows "")) ""
               (concat "\n\nAnd the order I work in:\n#+begin_example\n" flows "\n#+end_example"))))
   t))


(defun +usage--sequences ()
  "Saved plus unsaved sequence counts: (PAIRS . MODES), two `equal' hash tables."
  (let ((saved (when (file-readable-p +usage-sequence-file)
                 (with-temp-buffer
                   (insert-file-contents +usage-sequence-file)
                   (ignore-errors (read (current-buffer))))))
        (pairs (make-hash-table :test #'equal))
        (modes (make-hash-table :test #'equal)))
    (pcase-dolist (`(,k . ,n) (plist-get saved :pairs)) (puthash k n pairs))
    (pcase-dolist (`(,k . ,n) (plist-get saved :modes)) (puthash k n modes))
    (maphash (lambda (k n) (cl-incf (gethash k pairs 0) n)) +usage--pairs)
    (maphash (lambda (k n) (cl-incf (gethash k modes 0) n)) +usage--modes)
    (cons pairs modes)))

(defun +usage--save-sequences ()
  (when (or (> (hash-table-count +usage--pairs) 0) (> (hash-table-count +usage--modes) 0))
    (pcase-let ((`(,pairs . ,modes) (+usage--sequences))
                (print-length nil) (print-level nil))
      (with-temp-file +usage-sequence-file
        (prin1 (list :pairs (let (l) (maphash (lambda (k n) (push (cons k n) l)) pairs) l)
                     :modes (let (l) (maphash (lambda (k n) (push (cons k n) l)) modes) l))
               (current-buffer)))
      (clrhash +usage--pairs)
      (clrhash +usage--modes))))

(defun +usage-anticipations (last mode &optional n)
  "Up to N (default 15) likely next commands after LAST in MODE, best first.
Each is (COMMAND SCORE AFTER-LAST IN-MODE); following LAST weighs three times
what being common in MODE does."
  (pcase-let ((`(,pairs . ,modes) (+usage--sequences))
              (scores (make-hash-table :test #'eq)))
    (maphash (lambda (k c) (when (eq (car k) last) (cl-incf (gethash (cdr k) scores 0) (* 3 c)))) pairs)
    (maphash (lambda (k c) (when (eq (car k) mode) (cl-incf (gethash (cdr k) scores 0) c))) modes)
    (let (rows)
      (maphash (lambda (cmd score)
                 (when (and (not (eq cmd last)) (commandp cmd)
                            (not (memq cmd +usage-ignore)))
                   (push (list cmd score (gethash (cons last cmd) pairs 0)
                               (gethash (cons mode cmd) modes 0))
                         rows)))
               scores)
      (seq-take (sort rows (lambda (a b) (> (nth 1 a) (nth 1 b)))) (or n 15)))))

(defconst +usage--ask-model "✦ Ask the model to anticipate (edits, commands, searches)")

;;;###autoload
(defun +usage/anticipate (&optional ask)
  "Pick a likely next command, from what you do after the last one and in
this mode; RET runs it.  With prefix arg ASK, or the last entry, have the
model anticipate edits, commands and searches from the same evidence."
  (interactive "P")
  (let* ((last +usage--last)
         (rows (+usage-anticipations last major-mode))
         (pick (unless ask
                 (let* ((cands (append (mapcar (lambda (r) (symbol-name (car r))) rows)
                                       (list +usage--ask-model)))
                        (annotate
                         (lambda (c)
                           (when-let* ((row (assq (intern-soft c) rows)))
                             (concat (propertize " " 'display '(space :align-to 40))
                                     (propertize (or (ignore-errors (key-description (where-is-internal (car row) nil t))) "")
                                                 'face 'help-key-binding)
                                     (propertize " " 'display '(space :align-to 56))
                                     (propertize (format "after %s ×%d · here ×%d" last (nth 2 row) (nth 3 row))
                                                 'face 'completions-annotations))))))
                   (let ((completion-extra-properties (list :annotation-function annotate)))
                     (completing-read (format "Next (after %s): " last)
                                      (lambda (s p a) (if (eq a 'metadata) '(metadata (display-sort-function . identity))
                                                        (complete-with-action a cands s p)))
                                      nil t))))))
    (if (and pick (not (equal pick +usage--ask-model)))
        (call-interactively (intern pick))
      (unless (fboundp 'familiar-ask) (user-error "familiar-ask isn't available"))
      (familiar-ask
       (concat "@fast Anticipate what I'll do next here: the edits I'm likely to make, "
               "the commands (with their keys), and what I might search for.  Short list, "
               "most likely first; don't do anything yet.\n\n"
               "My last commands, oldest first:\n"
               (mapconcat (lambda (c) (format "- %s (%s)" (car c) (cdr c)))
                          (reverse +usage--recent) "\n")
               "\n\nWhat I usually run after the last one, or in this mode:\n"
               (mapconcat (lambda (r) (format "- %s: after ×%d, here ×%d" (car r) (nth 2 r) (nth 3 r)))
                          rows "\n"))))))

;; Opt-in: M-x +usage-mode (or (+usage-mode 1) in config.el) to start counting.


;;;; Where the time goes, and what gets cancelled
;;
;; From the task list: time spent per kind of buffer, cancelled popups,
;; minibuffers and key sequences, for an AI (or you) to read later.  Cheap:
;; a few hash increments per command, saved with the counts.
;;
;;   M-x +usage/time    time per mode (popups apart), cancelled prompts and
;;                      prefixes, since counting began
;;
;; Time: the seconds between two commands go to the buffer kind you were in
;; (its major mode, or "popup"); gaps over `+usage-idle-gap' are you away.
;; A minibuffer left with C-g / ESC counts as its command cancelled; C-g in
;; the middle of a key sequence counts as that prefix abandoned.

(defvar +usage-events-file (locate-user-emacs-file "usage-events.eld")
  "Where time and cancellations persist: (:time ALIST :cancelled ALIST),
keys KIND (a string) and (WHAT . NAME), what being minibuffer or prefix.")

(defvar +usage-idle-gap 300 "Seconds between commands that count as away.")

(defvar +usage--time (make-hash-table :test #'equal) "Unsaved KIND → seconds.")
(defvar +usage--cancelled (make-hash-table :test #'equal) "Unsaved (WHAT . NAME) → count.")
(defvar +usage--mx-commands '(execute-extended-command execute-extended-command-for-buffer))
(defvar +usage--last-time nil "When the last command ended.")
(defvar +usage--last-kind nil "The buffer kind after the last command.")

(defconst +usage--quit-commands
  '(keyboard-quit abort-minibuffers abort-recursive-edit minibuffer-keyboard-quit
    keyboard-escape-quit doom/escape evil-force-normal-state)
  "Commands that cancel.")

(defun +usage--kind ()
  (if (and (fboundp '+popup-buffer-p) (+popup-buffer-p)) "popup" (symbol-name major-mode)))

(defun +usage--events-h ()
  "Time since the last command, to where you were; prefixes abandoned."
  (unless executing-kbd-macro
    (let ((now (float-time)))
      (when (and +usage--last-time +usage--last-kind)
        (let ((gap (- now +usage--last-time)))
          (when (< 0 gap +usage-idle-gap)
            (cl-incf (gethash +usage--last-kind +usage--time 0) gap))))
      (let ((keys (this-command-keys-vector)))
        (when (and (memq this-command +usage--quit-commands)
                   (> (length keys) 1)
                   (not (minibufferp)))
          (cl-incf (gethash (cons 'prefix (key-description (substring keys 0 -1)))
                            +usage--cancelled 0))))
      (setq +usage--last-time now
            +usage--last-kind (if (minibufferp) "minibuffer" (+usage--kind))))))

(defun +usage--minibuffer-exit-h ()
  "A minibuffer left by quitting: its command cancelled.
For M-x, what was typed is kept too (see \"M-x that gave up\" below)."
  (when (and (memq this-command +usage--quit-commands)
             (symbolp current-minibuffer-command) current-minibuffer-command)
    (cl-incf (gethash (cons 'minibuffer (symbol-name current-minibuffer-command))
                      +usage--cancelled 0))
    (when (memq current-minibuffer-command +usage--mx-commands)
      (+usage--mx-gave-up (minibuffer-contents-no-properties)))))

(defun +usage--events-read ()
  (and (file-exists-p +usage-events-file)
       (ignore-errors (with-temp-buffer (insert-file-contents +usage-events-file)
                                        (read (current-buffer))))))

(defun +usage--events-merged ()
  "Saved events plus unsaved: (:time ALIST :cancelled ALIST)."
  (let* ((saved (+usage--events-read))
         (merge (lambda (alist table)
                  (let ((alist (copy-alist alist)))
                    (maphash (lambda (k v)
                               (let ((cell (assoc k alist)))
                                 (if cell (setcdr cell (+ (cdr cell) v))
                                   (push (cons k v) alist))))
                             table)
                    alist))))
    (list :time (funcall merge (plist-get saved :time) +usage--time)
          :cancelled (funcall merge (plist-get saved :cancelled) +usage--cancelled))))

(defun +usage-save-events ()
  "Merge unsaved time and cancellations into `+usage-events-file'."
  (when (or (> (hash-table-count +usage--time) 0) (> (hash-table-count +usage--cancelled) 0))
    (let ((data (+usage--events-merged)) (print-length nil) (print-level nil))
      (make-directory (file-name-directory +usage-events-file) t)
      (with-temp-file +usage-events-file (prin1 data (current-buffer)))
      (clrhash +usage--time)
      (clrhash +usage--cancelled))))

(defvar +usage--events-timer nil)

(add-hook '+usage-mode-hook
          (defun +usage--events-setup-h ()
            (if +usage-mode
                (progn
                  (add-hook 'post-command-hook #'+usage--events-h)
                  (add-hook 'minibuffer-exit-hook #'+usage--minibuffer-exit-h)
                  (add-hook 'kill-emacs-hook #'+usage-save-events)
                  (unless +usage--events-timer
                    (setq +usage--events-timer
                          (run-with-idle-timer +usage-save-interval t #'+usage-save-events))))
              (remove-hook 'post-command-hook #'+usage--events-h)
              (remove-hook 'minibuffer-exit-hook #'+usage--minibuffer-exit-h)
              (when +usage--events-timer
                (cancel-timer +usage--events-timer)
                (setq +usage--events-timer nil))
              (+usage-save-events))))

(defun +usage/time ()
  "Where the time went (per buffer kind) and what was cancelled."
  (interactive)
  (let* ((data (+usage--events-merged))
         (time (sort (plist-get data :time) (lambda (a b) (> (cdr a) (cdr b)))))
         (total (max 1 (apply #'+ (mapcar #'cdr time))))
         (cancelled (sort (plist-get data :cancelled) (lambda (a b) (> (cdr a) (cdr b))))))
    (with-current-buffer (get-buffer-create "*usage time*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "* Time, %.1f h active\n" (/ total 3600.0)))
        (dolist (e (seq-take time 25))
          (insert (format "%7.1f h %5.1f %%  %s\n" (/ (cdr e) 3600.0) (/ (* 100.0 (cdr e)) total) (car e))))
        (insert "\n* Cancelled minibuffers (C-g / ESC)\n")
        (dolist (e (seq-take (seq-filter (lambda (e) (eq (caar e) 'minibuffer)) cancelled) 20))
          (insert (format "%6d  %s\n" (cdr e) (cdar e))))
        (insert "\n* Abandoned key prefixes\n")
        (dolist (e (seq-take (seq-filter (lambda (e) (eq (caar e) 'prefix)) cancelled) 20))
          (insert (format "%6d  %s\n" (cdr e) (cdar e)))))
      (goto-char (point-min))
      (org-mode)
      (view-mode)
      (pop-to-buffer (current-buffer)))))

;;;; M-x, ranked for where you are
;;
;; From the task list: a context-sensitive M-x, the commands that matter
;; here at the top.  When M-x (or M-S-x) opens, the commands you actually
;; run in this major mode, and after the command you just ran, come first,
;; best first (`+usage-anticipations': the same evidence as SPC A .); the
;; rest follow in vertico's usual order (history, then length).  Keys show
;; through marginalia as before.  Nothing is sent anywhere.

(defvar vertico-sort-function)
(defvar vertico-sort-override-function)

(defcustom +usage-mx-ranked 300
  "How many commands M-x ranks by context (the rest keep vertico's order)."
  :type 'natnum :group 'convenience)

(defun +usage--mx-sort (scores)
  "A vertico sort: commands with SCORES first, highest first, then the rest
in vertico's own order."
  (lambda (cands)
    (let* ((base (if vertico-sort-function (funcall vertico-sort-function cands) cands))
           ranked rest)
      (dolist (c base)
        (if (gethash c scores) (push c ranked) (push c rest)))
      (nconc (sort ranked (lambda (a b) (> (gethash a scores) (gethash b scores))))
             (nreverse rest)))))

(defun +usage-mx-setup-h ()
  "In M-x's minibuffer: rank by this context (see above)."
  (when (and (memq this-command '(execute-extended-command execute-extended-command-for-buffer))
             (boundp 'vertico-sort-override-function))
    (let* ((buf (window-buffer (minibuffer-selected-window)))
           (scores (make-hash-table :test #'equal)))
      ;; How you reach each command: a context score counts in proportion to
      ;; your M-x share for it, so motions you run by keys (next-line,
      ;; evil-append) don't crowd M-x, and what you run through M-x does.
      (let ((via (make-hash-table :test #'eq)))
        (pcase-dolist (`(,cmd . ,hows) (+usage--merged))
          (let ((total (apply #'+ (mapcar #'cdr hows)))
                (mx (or (cdr (assoc "M-x" hows)) 0)))
            (puthash cmd (/ mx (+ total 1.0)) via)))
        (pcase-dolist (`(,cmd ,score . ,_)
                       (+usage-anticipations +usage--last (buffer-local-value 'major-mode buf)
                                             +usage-mx-ranked))
          (let ((share (gethash cmd via 0)))
            ;; A habit, not the odd M-x: a quarter of its uses at least.  And
            ;; never the minibuffer's own commands (some ran inside M-x's
            ;; minibuffer and were counted as by M-x).
            (when (and (>= share 0.25)
                       (not (string-match-p "\\`\\(?:execute-extended-command\\|exit-minibuffer\\|abort-\\|minibuffer-\\|vertico-\\|keyboard-\\)"
                                            (symbol-name cmd))))
              (puthash (symbol-name cmd) (* score share) scores)))))
      (when (> (hash-table-count scores) 0)
        (setq-local vertico-sort-override-function (+usage--mx-sort scores))))))

(add-hook 'minibuffer-setup-hook #'+usage-mx-setup-h)

;;;; M-x that gave up
;;
;; 114 of 443 M-x were left with C-g (2026-11-05): you looked for a command
;; and didn't find it by the words you typed.  What was typed is kept
;; (locally, like the counts).  When you then run a command some other way
;; within two minutes, that is taken as what you meant: next time the same
;; words show "→ COMMAND (KEY)" after your input, and RET with nothing
;; matching runs it.  With nothing learned, RET asks familiar which command
;; does that.  M-x +usage/mx-gave-up lists both.

(defvar +usage-mx-file (locate-user-emacs-file "usage-mx.eld")
  "(:gave-up ((INPUT . N) …) :meant (((INPUT . COMMAND) . N) …)).")

(defvar +usage-mx-meant-within 120
  "Seconds after giving up in which the next command counts as the one meant.")

(defconst +usage--mx-not-meant
  (concat "\\`\\(?:evil-\\(?:next\\|previous\\|forward\\|backward\\|insert\\|append\\|normal\\|"
          "delete\\|escape\\|open\\|scroll\\|goto\\|undo\\|redo\\|exit\\|force\\)\\|"
          "next-line\\|previous-line\\|\\(?:org-\\)?self-insert\\|vertico-\\|corfu-\\|"
          "abort-\\|keyboard-\\|minibuffer-\\|exit-minibuffer\\|undo\\|ultra-scroll\\|"
          "mwheel\\|mouse-\\|handle-\\|doom/escape\\|execute-extended-command\\)")
  "Commands that are moving or typing, never the command you were looking for.")

(defvar +usage--mx-data nil "The file's data, read on first use.")
(defvar +usage--mx-pending nil "(INPUT . TIME) of the last M-x given up.")

(defun +usage--mx-norm (input)
  (downcase (string-join (split-string input "[ \t-]+" t) " ")))

(defun +usage--mx-data ()
  (or +usage--mx-data
      (setq +usage--mx-data
            (or (and (file-exists-p +usage-mx-file)
                     (ignore-errors (with-temp-buffer (insert-file-contents +usage-mx-file)
                                                      (read (current-buffer)))))
                (list :gave-up nil :meant nil)))))

(defun +usage--mx-save ()
  (let ((print-length nil) (print-level nil))
    (make-directory (file-name-directory +usage-mx-file) t)
    (with-temp-file +usage-mx-file (prin1 (+usage--mx-data) (current-buffer)))))

(defun +usage--mx-bump (key alist-key)
  (let* ((data (+usage--mx-data))
         (alist (plist-get data alist-key))
         (cell (assoc key alist)))
    (if cell (cl-incf (cdr cell)) (push (cons key 1) alist))
    (setq +usage--mx-data (plist-put data alist-key alist))
    (+usage--mx-save)))

(defun +usage--mx-gave-up (input)
  "M-x left with INPUT typed: keep it, and wait for what you do next."
  (let ((input (+usage--mx-norm input)))
    (unless (or (string-empty-p input) executing-kbd-macro)
      (+usage--mx-bump input :gave-up)
      (setq +usage--mx-pending (cons input (float-time))))))

(defun +usage--mx-meant-h ()
  "The first real command after giving up on M-x: what was meant."
  (when (and +usage--mx-pending (not executing-kbd-macro))
    (let ((cmd (if (eq real-this-command 'execute-extended-command) this-command real-this-command)))
      (cond ((> (- (float-time) (cdr +usage--mx-pending)) +usage-mx-meant-within)
             (setq +usage--mx-pending nil))
            ((and (symbolp cmd) cmd (commandp cmd)
                  (not (memq cmd +usage--quit-commands))
                  (not (string-match-p +usage--mx-not-meant (symbol-name cmd))))
             (+usage--mx-bump (cons (car +usage--mx-pending) cmd) :meant)
             (setq +usage--mx-pending nil))))))

(defun +usage-mx-meant (input)
  "The command most often meant by INPUT, or nil.
INPUT matches a remembered attempt when it is that attempt or the start of
it (3 characters at least)."
  (let ((input (+usage--mx-norm input)) best (n 0))
    (when (>= (length input) 3)
      (pcase-dolist (`((,typed . ,cmd) . ,count) (plist-get (+usage--mx-data) :meant))
        (when (and (string-prefix-p input typed) (> count n) (fboundp cmd))
          (setq best cmd n count))))
    best))

(defvar-local +usage--mx-overlay nil)

(defun +usage--mx-show-meant-h ()
  "In M-x: after the input, the command these words meant before."
  (when (memq current-minibuffer-command +usage--mx-commands)
    (let* ((meant (+usage-mx-meant (minibuffer-contents-no-properties)))
           (key (and meant (with-current-buffer (window-buffer (minibuffer-selected-window))
                               (where-is-internal meant nil t))))
           (text (and meant (concat "  → " (symbol-name meant)
                                    (if key (format " (%s)" (key-description key)) "")))))
      (unless +usage--mx-overlay
        (setq +usage--mx-overlay (make-overlay (point-max) (point-max) nil t t)))
      (move-overlay +usage--mx-overlay (point-max) (point-max))
      (overlay-put +usage--mx-overlay 'after-string
                   (and text (propertize text 'face 'shadow))))))

(defun +usage--mx-setup-meant-h ()
  (when (memq current-minibuffer-command +usage--mx-commands)
    (add-hook 'post-command-hook #'+usage--mx-show-meant-h nil t)))

(add-hook 'minibuffer-setup-hook #'+usage--mx-setup-meant-h)

(defvar vertico--total)

(defun +usage-mx-exit-a (fn &rest args)
  "RET in M-x with nothing matching: the command meant, or ask familiar."
  (let ((input (minibuffer-contents-no-properties)))
    (if (not (and (memq current-minibuffer-command +usage--mx-commands)
                  (boundp 'vertico--total) (eql vertico--total 0)
                  (not (string-blank-p input))))
        (apply fn args)
      (let ((meant (+usage-mx-meant input)))
        (run-at-time 0 nil
                     (if meant
                         (lambda () (call-interactively meant))
                       (lambda ()
                         (+usage--mx-gave-up input)
                         (if (fboundp 'familiar-ask)
                             (familiar-ask
                              (format "@echo Which Emacs command (name, and its key here if bound) does this: %s" input)
                              t)
                           (message "No command matches %S" input)))))
        (abort-minibuffers)))))

(with-eval-after-load 'vertico
  (advice-add 'vertico-exit :around #'+usage-mx-exit-a))

(defun +usage--mx-setup-h ()
  (if +usage-mode
      (add-hook 'post-command-hook #'+usage--mx-meant-h)
    (remove-hook 'post-command-hook #'+usage--mx-meant-h)))
(add-hook '+usage-mode-hook #'+usage--mx-setup-h)
(when (bound-and-true-p +usage-mode) (+usage--mx-setup-h))

(defun +usage/mx-gave-up ()
  "What M-x was left with, most often first, and what it turned out to mean."
  (interactive)
  (let* ((data (+usage--mx-data))
         (gave (sort (copy-sequence (plist-get data :gave-up)) (lambda (a b) (> (cdr a) (cdr b)))))
         (meant (plist-get data :meant)))
    (with-current-buffer (get-buffer-create "*M-x given up*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "* M-x left with C-g: what was typed, and what it meant\n\n")
        (pcase-dolist (`(,input . ,n) gave)
          (let ((cmds (seq-filter (lambda (e) (equal (caar e) input)) meant)))
            (insert (format "%4d  %-30s %s\n" n input
                            (if cmds (mapconcat (lambda (e) (format "→ %s (%d)" (cdar e) (cdr e))) cmds ", ")
                              "")))))
        (goto-char (point-min))
        (org-mode)
        (view-mode)
        (pop-to-buffer (current-buffer))))))

(provide '+usage)
;;; +usage.el ends here
