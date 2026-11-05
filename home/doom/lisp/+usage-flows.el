;;; lisp/+usage-flows.el --- What you did, in order: flows of commands -*- lexical-binding: t; -*-
;;
;; +usage.el counts commands, keys and which command follows which: totals.
;; This keeps the order, so a workflow can be looked at afterwards: every
;; command as an event (time, command, keys, mode, project, whether it
;; edited), runs of the same command folded into one (typing 40 letters is
;; one self-insert-command ×40), one file a day.  Never what you typed or
;; any buffer's text.  Local, like the rest of +usage; on with +usage-mode.
;;
;; A flow is what happens between two pauses longer than `+usage-flow-gap'
;; seconds, across buffers (magit → a file → the commit is one flow).
;;
;;   M-x +usage/flows   the chains you repeat (3-5 commands), with how often
;;                      and the time they take; what you undo at once; what
;;                      you retry after cancelling; long walks before an
;;                      edit; flows by hour; and what that suggests
;;
;; +usage/suggest hands the same summary to the model with the counts.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar +usage-mode)
(defvar +usage-save-interval)

(defvar +usage-flows-directory (locate-user-emacs-file "usage-flows/")
  "Where the events are kept, one file a day (YYYY-MM-DD.eld).")

(defvar +usage-flow-gap 8
  "Seconds without a command that end a flow.")

(defvar +usage-flows-days 14 "Days `+usage/flows' reads.")

(defvar +usage-flows-ignore '(ignore handle-switch-frame evil-normal-state)
  "Commands that aren't steps of a flow.
Typing, scrolling and cancelling are, unlike in `+usage-ignore' (the counts).")

(defconst +usage-flows--undo-commands
  '(undo undo-only undo-redo evil-undo undo-fu-only-undo undo-tree-undo vundo)
  "Commands that take something back.")

(defconst +usage-flows--quit-commands
  '(keyboard-quit abort-minibuffers abort-recursive-edit minibuffer-keyboard-quit
    keyboard-escape-quit doom/escape)
  "Commands that cancel.")

(defconst +usage-flows--motion-regexp
  (concat "\\`\\(?:evil-\\(?:next\\|previous\\|forward\\|backward\\)-\\|evil-\\(?:scroll\\|goto\\)-"
          "\\|\\(?:next\\|previous\\|forward\\|backward\\)-\\(?:line\\|char\\|word\\|paragraph\\)"
          "\\|scroll-\\|mwheel-scroll\\|ultra-scroll\\|pixel-scroll\\)")
  "Commands that only move.")

;;;; Recording

(defvar +usage-flows--pending nil "Events not yet written, newest first.")
(defvar +usage-flows--tick nil "The buffer and its change tick before the command.")
(defvar-local +usage-flows--project 'unknown "This buffer's project name, once looked up.")

(defun +usage-flows--project ()
  "This buffer's project (its git root's name), cached; nil remotely."
  (when (eq +usage-flows--project 'unknown)
    (setq +usage-flows--project
          (unless (or (file-remote-p default-directory)
                      (find-file-name-handler default-directory 'file-exists-p))
            (when-let* ((root (locate-dominating-file default-directory ".git")))
              (file-name-nondirectory (directory-file-name root))))))
  +usage-flows--project)

(defun +usage-flows--pre-h ()
  "Note the buffer's change tick, to tell later whether the command edited."
  (setq +usage-flows--tick (cons (current-buffer) (buffer-chars-modified-tick))))

(defun +usage-flows--post-h ()
  "Record the command that ran as an event, folding runs of the same one."
  (let ((cmd (if (eq real-this-command 'execute-extended-command) this-command real-this-command)))
    (when (and cmd (symbolp cmd) (not executing-kbd-macro)
               (not (memq cmd +usage-flows-ignore)))
      (let* ((now (/ (round (* 10 (float-time))) 10.0))
             (edited (and (eq (car +usage-flows--tick) (current-buffer))
                          (/= (cdr +usage-flows--tick) (buffer-chars-modified-tick))))
             (last (car +usage-flows--pending)))
        ;; (START END COMMAND COUNT KEYS MODE PROJECT EDITED)
        (if (and last (eq (nth 2 last) cmd) (< (- now (nth 1 last)) 2))
            (setcar +usage-flows--pending
                    (list (nth 0 last) now cmd (1+ (nth 3 last)) (nth 4 last) (nth 5 last) (nth 6 last)
                          (or (nth 7 last) edited)))
          (push (list now now cmd 1
                      (let ((keys (this-command-keys-vector)))
                        (if (eq real-this-command 'execute-extended-command) "M-x"
                          (and (> (length keys) 0) (key-description keys))))
                      (if (minibufferp) 'minibuffer major-mode)
                      (+usage-flows--project) edited)
                +usage-flows--pending))))))

(defun +usage-flows-save ()
  "Append the pending events to today's file."
  (when +usage-flows--pending
    (make-directory +usage-flows-directory t)
    (let ((events (reverse +usage-flows--pending)) (print-length nil) (print-level nil))
      (setq +usage-flows--pending nil)
      (with-temp-buffer
        (dolist (e events) (prin1 e (current-buffer)) (insert "\n"))
        (write-region (point-min) (point-max)
                      (expand-file-name (format-time-string "%F.eld") +usage-flows-directory)
                      'append 'silent)))))

(defvar +usage-flows--timer nil)

(defun +usage-flows--setup-h ()
  "Record flows while `+usage-mode' is on."
  (if (bound-and-true-p +usage-mode)
      (progn
        (add-hook 'pre-command-hook #'+usage-flows--pre-h)
        (add-hook 'post-command-hook #'+usage-flows--post-h)
        (add-hook 'kill-emacs-hook #'+usage-flows-save)
        (unless +usage-flows--timer
          (setq +usage-flows--timer
                (run-with-idle-timer (or (bound-and-true-p +usage-save-interval) 300) t #'+usage-flows-save))))
    (remove-hook 'pre-command-hook #'+usage-flows--pre-h)
    (remove-hook 'post-command-hook #'+usage-flows--post-h)
    (when +usage-flows--timer (cancel-timer +usage-flows--timer) (setq +usage-flows--timer nil))
    (+usage-flows-save)))

(add-hook '+usage-mode-hook #'+usage-flows--setup-h)
(when (bound-and-true-p +usage-mode) (+usage-flows--setup-h))

;;;; Reading

(defun +usage-flows-events (&optional days)
  "Events of the last DAYS days (default `+usage-flows-days'), oldest first."
  (let (out)
    (dotimes (i (or days +usage-flows-days))
      (let ((file (expand-file-name (format-time-string "%F.eld" (time-subtract nil (* 86400 i)))
                                    +usage-flows-directory)))
        (when (file-readable-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (let (day)
              (condition-case nil
                  (while t (push (read (current-buffer)) day))
                (error nil))
              (setq out (nconc (nreverse day) out)))))))
    (append out (reverse +usage-flows--pending))))

(defun +usage-flows-split (events)
  "EVENTS cut into flows at pauses longer than `+usage-flow-gap'."
  (let (flows current last-end)
    (dolist (e events)
      (when (and current last-end (> (- (nth 0 e) last-end) +usage-flow-gap))
        (push (nreverse current) flows)
        (setq current nil))
      (push e current)
      (setq last-end (nth 1 e)))
    (when current (push (nreverse current) flows))
    (nreverse flows)))

(defun +usage-flows--motion-p (cmd)
  (string-match-p +usage-flows--motion-regexp (symbol-name cmd)))

(defun +usage-flows-chains (flows &optional min-count)
  "Chains of 3-5 commands repeated at least MIN-COUNT (4) times in FLOWS:
list of (CHAIN COUNT SECONDS), maximal ones, most frequent first.  Motion
and typing aren't steps of a chain."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (f flows)
      (let ((steps (vconcat (seq-remove (lambda (e) (or (+usage-flows--motion-p (nth 2 e))
                                                        (eq (nth 2 e) 'self-insert-command)
                                                        (string-prefix-p "org-self-insert" (symbol-name (nth 2 e)))))
                                        f))))
        (dotimes (i (length steps))
          (cl-loop for n from 3 to 5
                   while (<= (+ i n) (length steps))
                   do (let* ((part (cl-subseq steps i (+ i n)))
                             (chain (mapcar (lambda (e) (nth 2 e)) part)))
                        (when (>= (length (delete-dups (copy-sequence chain))) 3)
                          (let ((cell (gethash chain table (list 0 0.0))))
                            (puthash chain (list (1+ (car cell))
                                                 (+ (cadr cell) (- (nth 1 (aref part (1- n))) (nth 0 (aref part 0)))))
                                     table))))))))
    (let (all)
      (maphash (lambda (chain v) (when (>= (car v) (or min-count 4)) (push (list chain (car v) (cadr v)) all))) table)
      ;; Drop a chain inside a longer one seen as often.
      (setq all (seq-remove
                 (lambda (c)
                   (cl-some (lambda (d) (and (> (length (car d)) (length (car c)))
                                             (>= (nth 1 d) (nth 1 c))
                                             (cl-search (car c) (car d))))
                            all))
                 all))
      (sort all (lambda (a b) (> (* (nth 1 a) (length (car a))) (* (nth 1 b) (length (car b)))))))))

(defun +usage-flows-detours (events)
  "Commands undone right after (within two events): alist (COMMAND . TIMES)."
  (let ((table (make-hash-table)))
    (cl-loop for (a b c) on events
             when (and a (not (memq (nth 2 a) +usage-flows--undo-commands))
                       (or (and b (memq (nth 2 b) +usage-flows--undo-commands))
                           (and c (memq (nth 2 c) +usage-flows--undo-commands)
                                (+usage-flows--motion-p (nth 2 b))))
                       (nth 7 a))
             do (cl-incf (gethash (nth 2 a) table 0)))
    (let (out) (maphash (lambda (k v) (push (cons k v) out)) table)
         (sort out (lambda (x y) (> (cdr x) (cdr y)))))))

(defun +usage-flows-retries (events)
  "Commands run again within 10 s of cancelling them: alist (COMMAND . TIMES)."
  (let ((table (make-hash-table)))
    (cl-loop for (a q b) on events
             when (and b (memq (nth 2 q) +usage-flows--quit-commands)
                       (eq (nth 2 a) (nth 2 b))
                       (not (memq (nth 2 a) +usage-flows--quit-commands))
                       (< (- (nth 0 b) (nth 1 a)) 10))
             do (cl-incf (gethash (nth 2 a) table 0)))
    (let (out) (maphash (lambda (k v) (push (cons k v) out)) table)
         (sort out (lambda (x y) (> (cdr x) (cdr y)))))))

(defun +usage-flows-walks (flows)
  "Flows with 15 or more moves before their first edit: (MOVES . FLOW) list."
  (cl-loop for f in flows
           for moves = (cl-loop for e in f
                                until (nth 7 e)
                                when (+usage-flows--motion-p (nth 2 e)) sum (nth 3 e))
           when (and (>= moves 15) (cl-find-if (lambda (e) (nth 7 e)) f))
           collect (cons moves f)))

(defun +usage-flows-summary (&optional days)
  "Plain-text summary of DAYS of flows, for a model to read."
  (let* ((events (+usage-flows-events days))
         (flows (+usage-flows-split events)))
    (if (null events) ""
      (concat
       (format "Flows (%d over %d days, %d commands):\n" (length flows) (or days +usage-flows-days) (length events))
       (mapconcat (pcase-lambda (`(,chain ,n ,secs))
                    (format "- %s: %d times, %.0f s in all" (mapconcat #'symbol-name chain " → ") n secs))
                  (seq-take (+usage-flows-chains flows) 15) "\n")
       "\nUndone right after: "
       (mapconcat (lambda (c) (format "%s ×%d" (car c) (cdr c))) (seq-take (+usage-flows-detours events) 8) ", ")
       "\nRetried after cancelling: "
       (mapconcat (lambda (c) (format "%s ×%d" (car c) (cdr c))) (seq-take (+usage-flows-retries events) 8) ", ")
       (format "\nFlows with 15+ moves before the first edit: %d\n" (length (+usage-flows-walks flows)))))))

;;;; The report

(defun +usage-flows--heading (title)
  (insert "\n" (propertize title 'face '(:inherit (outline-1 bold) :height 1.1)) "\n\n"))

(defun +usage-flows--render ()
  "Fill this buffer with the report on recent flows."
  (let* ((inhibit-read-only t)
         (events (+usage-flows-events))
         (flows (+usage-flows-split events))
         (chains (+usage-flows-chains flows))
         (detours (+usage-flows-detours events))
         (retries (+usage-flows-retries events))
         (walks (+usage-flows-walks flows)))
    (erase-buffer)
    (insert (propertize "What you did, in order" 'face '(:inherit (outline-1 bold) :height 1.3))
            (propertize (format "   last %d days · g refresh · q quit\n" +usage-flows-days) 'face 'shadow))
    (if (null events)
        (insert "\nNothing recorded yet: +usage-mode records from now on.\n")
      (let ((lens (mapcar #'length flows))
            (durs (mapcar (lambda (f) (- (nth 1 (car (last f))) (nth 0 (car f)))) flows)))
        (insert (format "\n  %d flows, %d commands.  A flow: %d commands and %.0f s at the median, %.0f s at the longest.\n"
                        (length flows) (length events)
                        (nth (/ (length lens) 2) (sort (copy-sequence lens) #'<))
                        (nth (/ (length durs) 2) (sort (copy-sequence durs) #'<))
                        (apply #'max durs))))
      (+usage-flows--heading "Chains you repeat")
      (if (null chains)
          (insert "  None four times yet.\n")
        (pcase-dolist (`(,chain ,n ,secs) (seq-take chains 20))
          (insert (format "  %3d×  %5.0f s  " n secs)
                  (mapconcat (lambda (c) (propertize (symbol-name c) 'face 'font-lock-function-name-face))
                             chain (propertize " → " 'face 'shadow))
                  "\n")))
      (+usage-flows--heading "Undone right after")
      (if detours
          (dolist (d (seq-take detours 10))
            (insert (format "  %4d×  %s\n" (cdr d) (car d))))
        (insert "  Nothing.\n"))
      (+usage-flows--heading "Retried after cancelling")
      (if retries
          (dolist (r (seq-take retries 10))
            (insert (format "  %4d×  %s\n" (cdr r) (car r))))
        (insert "  Nothing.\n"))
      (+usage-flows--heading "Long walks before an edit")
      (insert (format "  %d flows moved 15 times or more before their first edit.\n" (length walks)))
      (let ((movers (make-hash-table)))
        (dolist (w walks)
          (dolist (e (cdr w))
            (when (+usage-flows--motion-p (nth 2 e)) (cl-incf (gethash (nth 2 e) movers 0) (nth 3 e)))))
        (let (top) (maphash (lambda (k v) (push (cons k v) top)) movers)
             (dolist (m (seq-take (sort top (lambda (a b) (> (cdr a) (cdr b)))) 5))
               (insert (format "  %6d  %s\n" (cdr m) (car m))))))
      (+usage-flows--heading "Flows by hour")
      (let ((hours (make-vector 24 0)))
        (dolist (f flows) (cl-incf (aref hours (decoded-time-hour (decode-time (nth 0 (car f)))))))
        (let ((mx (max 1 (seq-max hours))))
          (insert "  ")
          (dotimes (h 24) (insert (string (aref "▁▂▃▄▅▆▇█" (min 7 (floor (* 7.99 (/ (float (aref hours h)) mx))))))))
          (insert "\n  0     6     12    18   23\n")))
      (+usage-flows--heading "What that suggests")
      (let ((said nil))
        (pcase-dolist (`(,chain ,n ,secs) (seq-take chains 3))
          (when (>= n 6)
            (setq said t)
            (insert (format "  ➜ %s ran %d times (%.0f s): one command or a keyboard macro for it (C-x ( … C-x ), then name-last-kbd-macro).\n"
                            (mapconcat #'symbol-name chain " → ") n secs))))
        (when-let* ((d (car detours)) ((>= (cdr d) 5)))
          (setq said t)
          (insert (format "  ➜ %s was undone right after %d times: its key may sit next to the one you meant, or it does more than you expect.\n"
                          (car d) (cdr d))))
        (when (>= (length walks) 10)
          (setq said t)
          (insert (format "  ➜ %d flows walked 15+ moves to their edit: search (/, SPC s s) or avy jumps there in one.\n"
                          (length walks))))
        (unless said (insert "  Nothing yet: it needs a few days of flows.\n"))))
    (goto-char (point-min))))

(defvar-keymap +usage-flows-mode-map :parent special-mode-map "g" #'+usage-flows-refresh)

(define-derived-mode +usage-flows-mode special-mode "Flows"
  "The report on your flows of commands (see `+usage/flows').")

(defun +usage-flows-refresh ()
  "Read the flows again."
  (interactive)
  (+usage-flows--render))

;;;###autoload
(defun +usage/flows ()
  "What you did, in order: the chains you repeat, detours, retries, walks."
  (interactive)
  (+usage-flows-save)
  (with-current-buffer (get-buffer-create "*usage flows*")
    (+usage-flows-mode)
    (+usage-flows--render)
    (pop-to-buffer (current-buffer))))

(provide '+usage-flows)
;;; +usage-flows.el ends here
