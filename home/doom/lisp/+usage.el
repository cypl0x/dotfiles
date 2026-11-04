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
;;   SPC A .             anticipate: likely next commands here (C-u: ask the model)
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
(declare-function familiar-ask "familiar-ask" (prompt &optional new))

(defun +usage--record-h ()
  "Count `this-command' and how it was invoked."
  ;; Keyboard macros replay keys nobody typed now (Claude's lab tests too):
  ;; not evidence of how you work.
  (when (and (symbolp this-command) this-command
             (not executing-kbd-macro)
             (not (memq this-command +usage-ignore)))
    (let* ((keys (this-command-keys-vector))
           (how (cond ((or (eq real-this-command 'execute-extended-command)
                           (and (> (length keys) 0) (memq (aref keys 0) '(?\M-x))))
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
      (cl-incf (gethash (cons major-mode this-command) +usage--modes 0))
      (setq +usage--last this-command)
      (push (cons this-command major-mode) +usage--recent)
      (when (nthcdr 40 +usage--recent) (setcdr (nthcdr 39 +usage--recent) nil)))))

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
           "#+begin_example\n" (+usage-summary) "\n#+end_example")
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

(provide '+usage)
;;; +usage.el ends here
