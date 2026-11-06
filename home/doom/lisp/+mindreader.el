;;; lisp/+mindreader.el --- M-#: what you'd do next, here -*- lexical-binding: t; -*-
;;
;; M-# (normal and insert state, anywhere) lists what you would most likely
;; do next, from what you did before in the same situation: the commands,
;; with their keys, and the whole flows you repeat.  RET runs one.
;;
;; The situation is your last two commands, the major mode and the project.
;; The evidence is the order of everything you did (lisp/+usage-flows.el,
;; on with +usage-mode, local): what followed the same two commands, the
;; same one, in the same mode, in the same project, weighed in that order.
;; Recent days count more (half as much a week ago), so it follows your
;; habits as they change; what you run from M-# is recorded like the rest.
;;
;; A flow is a chain you repeat (org-capture → org-set-tags-command →
;; org-capture-finalize).  Picking one runs its first step and then walks
;; you through it: after each step the echo area names the next one with
;; its key, and M-# offers it first.  Doing something else ends the walk.
;;
;; Typing, moving, the minibuffer's own commands and cancelling aren't
;; steps: they say little about what comes next.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar +usage-flows-directory)
(defvar +usage-flows--pending)
(defvar +usage-flow-gap)
(declare-function +usage-flows--motion-p "+usage-flows" (cmd))

(defvar +mindreader-days 30 "Days of flows read.")
(defvar +mindreader-half-life 7.0 "Days after which a step counts half.")
(defvar +mindreader-max 40 "Most commands offered.")
(defvar +mindreader-flow-gap 600 "Seconds a flow may take, from its first step.")
(defvar +mindreader-flow-window 6 "Steps after the first among which a flow's others are looked for.")

(defconst +mindreader--skip-regexp
  (concat "\\`\\(?:self-insert-command\\|org-self-insert-command\\|newline\\|evil-ret"
          "\\|delete-backward-char\\|delete-char\\|backward-delete-char\\|evil-delete-backward-char"
          "\\|org-delete-backward-char\\|org-delete-char\\|backward-kill-word\\|kill-word"
          "\\|evil-normal-state\\|evil-insert\\|evil-append\\|evil-force-normal-state\\|evil-escape"
          "\\|keyboard-quit\\|keyboard-escape-quit\\|doom/escape\\|abort-\\|minibuffer-\\|exit-minibuffer"
          "\\|vertico-\\|corfu-\\|mwheel-\\|ultra-scroll\\|pixel-scroll\\|ignore\\|handle-switch-frame"
          "\\|undo\\|evil-undo\\|undo-fu\\|evil-redo\\|execute-extended-command\\|\\+mindreader"
          "\\|evil-mouse\\|mouse-\\|yank\\|evil-paste\\|org-cycle\\|indent-for-tab"
          ;; Editing and moving by key: you press those without being reminded.
          "\\|evil-\\|\\+evil\\|\\+org/\\(?:return\\|insert-item\\|dwim\\|shift\\)\\|\\+completion\\|\\+corfu\\|cape-\\|minuet-"
          "\\|org-return\\|org-meta-return\\|org-shift\\|org-meta\\(?:up\\|down\\|left\\|right\\)"
          "\\|org-\\(?:forward\\|backward\\|next\\|previous\\)-\\|outline-\\|transpose-\\|kill-line\\|kill-region"
          "\\|comment-\\|recenter\\|\\+suggest/\\|\\+default/\\(?:newline\\|yank\\)\\)")
  "Commands that aren't steps: typing, moving, minibuffer and popup keys.")

(defun +mindreader--step-p (cmd mode)
  "Non-nil when CMD (run in MODE) is a step worth predicting."
  (and (symbolp cmd) (not (eq mode 'minibuffer))
       (not (string-match-p +mindreader--skip-regexp (symbol-name cmd)))
       ;; A mode's own motions: dired-next-line, magit-section-forward …
       (not (string-match-p "-\\(?:next\\|previous\\|forward\\|backward\\|up\\|down\\)\\(?:-\\(?:line\\|char\\|word\\|item\\|sibling\\)\\)?\\'"
                            (symbol-name cmd)))
       (not (and (fboundp '+usage-flows--motion-p) (+usage-flows--motion-p cmd)))))

;;;; The evidence: steps, one cache per day file

(defvar +mindreader--cache (make-hash-table :test #'equal)
  "Day file → (MTIME . STEPS), STEPS a vector of [TIME CMD MODE PROJECT].")

(defun +mindreader--file-steps (file)
  "The steps in day FILE, cached while it doesn't change."
  (let ((mtime (file-attribute-modification-time (file-attributes file)))
        (hit (gethash file +mindreader--cache)))
    (if (and hit (equal (car hit) mtime)) (cdr hit)
      (let (steps)
        (with-temp-buffer
          (insert-file-contents file)
          (condition-case nil
              (while t
                (let ((e (read (current-buffer))))
                  (when (+mindreader--step-p (nth 2 e) (nth 5 e))
                    (push (vector (nth 0 e) (nth 2 e) (nth 5 e) (nth 6 e)) steps))))
            (error nil)))
        (let ((v (vconcat (nreverse steps))))
          (puthash file (cons mtime v) +mindreader--cache)
          v)))))

(defun +mindreader-steps ()
  "Steps of the last `+mindreader-days' days and those not saved yet, oldest first."
  (let (parts files)
    (dotimes (i +mindreader-days)
      (let ((file (expand-file-name (format-time-string "%F.eld" (time-subtract nil (* 86400 i)))
                                    +usage-flows-directory)))
        (push file files)
        (when (file-readable-p file) (push (+mindreader--file-steps file) parts))))
    ;; Days out of the window leave the cache (a daemon runs for weeks).
    (maphash (lambda (f _) (unless (member f files) (remhash f +mindreader--cache))) +mindreader--cache)
    (apply #'vconcat
           (append parts
                   (list (vconcat (delq nil (mapcar (lambda (e) (and (+mindreader--step-p (nth 2 e) (nth 5 e))
                                                                     (vector (nth 0 e) (nth 2 e) (nth 5 e) (nth 6 e))))
                                                    (reverse +usage-flows--pending)))))))))

;;;; The prediction

(defun +mindreader--weight (time now)
  (expt 0.5 (/ (- now time) 86400.0 +mindreader-half-life)))

(defun +mindreader-context ()
  "The situation now: (PREV2 PREV1 MODE PROJECT)."
  (let* ((steps (+mindreader-steps))
         (n (length steps)))
    (list (and (> n 1) (aref (aref steps (- n 2)) 1))
          (and (> n 0) (aref (aref steps (1- n)) 1))
          major-mode
          (and (fboundp '+usage-flows--project) (+usage-flows--project)))))

(defun +mindreader-predict (context &optional steps now)
  "Likely next commands in CONTEXT (see `+mindreader-context'), best first.
Each is (COMMAND SCORE WHY): WHY a list of (KIND . WEIGHTED-COUNT).
STEPS and NOW default to the recorded steps and the current time."
  (pcase-let* ((`(,p2 ,p1 ,mode ,project) context)
               (steps (or steps (+mindreader-steps)))
               (now (or now (float-time)))
               (kinds '((after2 . 4.0) (after . 2.0) (mode . 1.0) (project . 0.5)))
               (counts (make-hash-table :test #'equal))   ; (KIND . CMD) → weight
               (totals (make-hash-table :test #'eq)))     ; KIND → weight
    (dotimes (i (length steps))
      (let* ((s (aref steps i))
             (cmd (aref s 1))
             (w (+mindreader--weight (aref s 0) now))
             (prev1 (and (> i 0) (aref (aref steps (1- i)) 1)))
             (prev2 (and (> i 1) (aref (aref steps (- i 2)) 1)))
             (hits (delq nil (list (and p1 p2 (eq prev1 p1) (eq prev2 p2) 'after2)
                                   (and p1 (eq prev1 p1) 'after)
                                   (and (eq (aref s 2) mode) 'mode)
                                   (and project (equal (aref s 3) project) 'project)))))
        (dolist (k hits)
          (cl-incf (gethash (cons k cmd) counts 0) w)
          (cl-incf (gethash k totals 0) w))))
    (let ((scores (make-hash-table :test #'eq)) (why (make-hash-table :test #'eq)))
      (maphash (lambda (key w)
                 (let ((k (car key)) (cmd (cdr key)))
                   (cl-incf (gethash cmd scores 0)
                            (* (alist-get k kinds) (/ w (max 1e-9 (gethash k totals)))))
                   (push (cons k w) (gethash cmd why))))
               counts)
      (let (rows)
        (maphash (lambda (cmd score)
                   (when (and (commandp cmd) (not (eq cmd p1)))
                     (push (list cmd score (gethash cmd why)) rows)))
                 scores)
        (seq-take (sort rows (lambda (a b) (> (nth 1 a) (nth 1 b)))) +mindreader-max)))))

(defun +mindreader--subsequences (items n)
  "The ordered subsequences of ITEMS of length N (2 or 3), without repeats."
  (let (out)
    (cl-loop for (a . rest) on items
             do (cl-loop for (b . rest2) on rest
                         unless (eq a b)
                         do (if (= n 2) (push (list a b) out)
                              (dolist (c rest2)
                                (unless (memq c (list a b)) (push (list a b c) out))))))
    (delete-dups out)))

(defun +mindreader-flows (first &optional steps now min)
  "Flows that start with FIRST: (CHAIN WEIGHT COUNT), best first.
CHAIN is FIRST and the steps that followed it, in that order, among the
next `+mindreader-flow-window' steps and within `+mindreader-flow-gap'
seconds (other commands may come in between: a capture is written
between its steps), seen at least MIN (3) times."
  (let ((steps (or steps (+mindreader-steps)))
        (now (or now (float-time)))
        (table (make-hash-table :test #'equal)))
    (when first
      (dotimes (i (length steps))
        (let ((s (aref steps i)))
          (when (eq (aref s 1) first)
            (let ((w (+mindreader--weight (aref s 0) now))
                  (next (cl-loop for j from (1+ i) below (min (length steps) (+ i 1 +mindreader-flow-window))
                                 for n = (aref steps j)
                                 while (<= (- (aref n 0) (aref s 0)) +mindreader-flow-gap)
                                 until (eq (aref n 1) first)
                                 collect (aref n 1))))
              (dolist (len '(1 2))
                (dolist (tail (if (= len 1) (mapcar #'list (delete-dups (copy-sequence next)))
                                (+mindreader--subsequences next 2)))
                  (let ((cell (or (gethash tail table) (puthash tail (cons 0 0) table))))
                    (cl-incf (car cell) w) (cl-incf (cdr cell))))))))))
    (let (rows)
      (maphash (lambda (tail cell)
                 (when (and (>= (cdr cell) (or min 3)) (cl-every #'commandp tail))
                   (push (list (cons first tail) (car cell) (cdr cell)) rows)))
               table)
      ;; Most frequent first; among as frequent, the longer (it holds the shorter).
      (setq rows (sort rows (lambda (a b) (or (> (nth 2 a) (nth 2 b))
                                              (and (= (nth 2 a) (nth 2 b))
                                                   (> (length (car a)) (length (car b))))))))
      (let (kept)
        (dolist (r rows)
          (unless (seq-find (lambda (k) (and (>= (nth 2 k) (nth 2 r))
                                             (equal (seq-take (car k) (length (car r))) (car r))))
                            kept)
            (push r kept)))
        (seq-take (nreverse kept) 4)))))

;;;; Walking through a flow

(defvar +mindreader--walk nil "The steps left of the flow being walked through.")
(defvar +mindreader--walk-first nil "Non-nil until the first step of a walk has run.")
(defvar +mindreader--walk-since nil "When the walk started, and the other steps since: (TIME . N).")

(defun +mindreader--key (cmd)
  (or (ignore-errors (key-description (where-is-internal cmd nil t))) "M-x"))

(defun +mindreader--walk-h ()
  "After each command of a walk: the next step, or the end of the walk."
  (when +mindreader--walk
    (let ((cmd (if (eq real-this-command 'execute-extended-command) this-command real-this-command)))
      (cond (+mindreader--walk-first
             ;; The first step ran from M-# itself: only say what comes next.
             (setq +mindreader--walk-first nil)
             (message "Flow, next: %s (%s, or M-#)" (car +mindreader--walk)
                      (+mindreader--key (car +mindreader--walk))))
            ((not (+mindreader--step-p cmd (if (minibufferp) 'minibuffer major-mode))))
            ((eq cmd (car +mindreader--walk))
             (setcdr +mindreader--walk-since 0)
             (pop +mindreader--walk)
             (if +mindreader--walk
                 (message "Flow, next: %s (%s, or M-#)" (car +mindreader--walk)
                          (+mindreader--key (car +mindreader--walk)))
               (message "Flow done")
               (remove-hook 'post-command-hook #'+mindreader--walk-h)))
            ;; Other commands may come in between, a few, within the flow's time.
            ((and (<= (cl-incf (cdr +mindreader--walk-since)) +mindreader-flow-window)
                  (<= (- (float-time) (car +mindreader--walk-since)) +mindreader-flow-gap)))
            (t (setq +mindreader--walk nil)
               (message "Flow left")
               (remove-hook 'post-command-hook #'+mindreader--walk-h))))))

(defun +mindreader--run (cmd)
  "Run CMD as if you had: recorded as itself, not as M-#."
  (setq real-this-command cmd this-command cmd)
  (call-interactively cmd t))

;;;; M-#

(defun +mindreader--why (why)
  (mapconcat #'identity
             (delq nil (mapcar (lambda (kind)
				 (when-let* ((w (alist-get kind why)))
				   (format "%s ×%s" (pcase kind ('after2 "after these two") ('after "after it")
							   ('mode "in this mode") ('project "in this project"))
					   (if (< w 10) (format "%.1f" w) (format "%d" (round w))))))
			       '(after2 after mode project)))
             " · "))

(defun +mindreader/next ()
  "What you'd likely do next here: commands and flows; RET runs one.
Walking through a flow: its next step first."
  (interactive)
  (unless (bound-and-true-p +usage-mode)
    (user-error "Nothing recorded: turn on +usage-mode (it records what you do, locally)"))
  (let* ((context (+mindreader-context))
         (steps (+mindreader-steps))
         (now (float-time))
         (rows (+mindreader-predict context steps now))
         ;; Flows that start with what you'd likely do next.
         (flows (seq-take (sort (mapcan (lambda (r) (+mindreader-flows (car r) steps now))
                                        (seq-take rows 3))
                                (lambda (a b) (> (nth 1 a) (nth 1 b))))
                          5))
         (cands nil) (info (make-hash-table :test #'equal)))
    (when-let* ((next (car +mindreader--walk)))
      (let ((c (format "%s" next)))
        (push c cands)
        (puthash c (list 'walk next) info)))
    (dolist (f flows)
      (let ((c (concat "▶ " (mapconcat #'symbol-name (car f) " → "))))
        (push c cands)
        (puthash c (list 'flow (car f) (nth 2 f)) info)))
    (dolist (r rows)
      (let ((c (symbol-name (car r))))
        (unless (gethash c info)
          (push c cands)
          (puthash c (list 'command (car r) (nth 2 r)) info))))
    (setq cands (nreverse cands))
    (unless cands (user-error "Nothing to go on yet here"))
    (let* ((group (lambda (c transform)
                    (if transform c
                      (pcase (car (gethash c info))
                        ('walk "The flow you're in") ('flow "Flows you repeat from here")
                        (_ (format "Next, after %s" (or (nth 1 context) "nothing")))))))
           (annotate (lambda (c)
                       (pcase (gethash c info)
                         (`(walk ,cmd) (concat "  " (propertize (+mindreader--key cmd) 'face 'help-key-binding)
                                               (propertize "  the next step" 'face 'completions-annotations)))
                         (`(flow ,chain ,n)
                          (concat "  " (propertize (mapconcat #'+mindreader--key chain " → ")
                                                   'face 'help-key-binding)
                                  (propertize (format "  ×%d" n) 'face 'completions-annotations)))
                         (`(command ,cmd ,why)
                          (concat (propertize " " 'display '(space :align-to 44))
                                  (propertize (+mindreader--key cmd) 'face 'help-key-binding)
                                  (propertize " " 'display '(space :align-to 62))
                                  (propertize (+mindreader--why why) 'face 'completions-annotations))))))
           (pick (completing-read
                  "Next: "
                  (lambda (s p a)
                    (if (eq a 'metadata)
                        `(metadata (display-sort-function . identity) (cycle-sort-function . identity)
                                   (group-function . ,group) (annotation-function . ,annotate)
                                   (category . mindreader))
                      (complete-with-action a cands s p)))
                  nil t)))
      (pcase (gethash pick info)
        (`(walk ,cmd) (+mindreader--run cmd))
        (`(flow ,chain ,_)
         (setq +mindreader--walk (cdr chain) +mindreader--walk-first t
               +mindreader--walk-since (cons (float-time) 0))
         (add-hook 'post-command-hook #'+mindreader--walk-h)
         (message "Flow: %s" (mapconcat #'symbol-name chain " → "))
         (+mindreader--run (car chain)))
        (`(command ,cmd ,_) (+mindreader--run cmd))))))

(map! "M-#" #'+mindreader/next
      :ni "M-#" #'+mindreader/next)

(provide '+mindreader)
;;; +mindreader.el ends here
