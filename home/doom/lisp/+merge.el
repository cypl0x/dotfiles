;;; lisp/+merge.el --- Keep your unsaved edits AND what changed on disk -*- lexical-binding: t; -*-
;;
;; You edit a file; something else (an agent, git, another editor) writes
;; it underneath.  Emacs then asks "changed on disk; really edit/save?"
;; and either answer loses one side.  Here Emacs remembers the file as it
;; last read or saved it (the common ancestor), so it can do a real
;; three-way merge, `diff3 -m', of
;;
;;     ancestor  →  your buffer
;;     ancestor  →  the file on disk
;;
;; When the two sides touched different places (the usual case) the merge
;; is clean: the disk's changes land in your buffer, your edits stay
;; unsaved, point stays put, and the prompt never comes.  When they
;; overlap you get ediff with the ancestor (`ediff-merge-buffers-with-ancestor').
;;
;; It happens on its own when you start editing a stale buffer, when you
;; save one, and when you come back to one.  By hand: SPC f M.
;;
;; For agents: `+merge-edit-file' edits a file through its buffer, so a
;; file you're editing is never written behind your back:
;;   emacsclient -e '(+merge-edit-file "~/vault/mess.org" (lambda () ...))'
;;
;;; Code:

(require 'cl-lib)

(defvar ediff-buffer-C)

(defvar +merge-max-size (* 4 1024 1024)
  "Files bigger than this (bytes) keep no ancestor and aren't merged.")

(defvar-local +merge--ancestor nil
  "The file's text when this buffer last read or saved it.")

(defun +merge-remember-h ()
  "Remember the file as read or saved: the ancestor of the next merge."
  (when (and buffer-file-name (< (buffer-size) +merge-max-size)
             (not (file-remote-p buffer-file-name)))
    (setq +merge--ancestor
          (save-restriction (widen) (buffer-substring-no-properties (point-min) (point-max))))))

(defun +merge--disk-text (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun +merge--stale-p ()
  "Non-nil if this buffer's file changed on disk since it was read or saved."
  (and buffer-file-name (file-exists-p buffer-file-name)
       (not (verify-visited-file-modtime (current-buffer)))))

(defun +merge--diff3 (mine ancestor theirs)
  "Merge MINE and THEIRS from ANCESTOR (strings): (CLEAN-P . TEXT)."
  (let ((files (mapcar (lambda (text)
                         (let ((f (make-temp-file "emacs-merge-")))
                           (let ((coding-system-for-write 'utf-8-unix))
                             (write-region text nil f nil 'silent))
                           f))
                       (list mine ancestor theirs))))
    (unwind-protect
        (with-temp-buffer
          (let* ((coding-system-for-read 'utf-8-unix)
                 (status (apply #'call-process "diff3" nil t nil "-m"
                                "-L" "your edits" "-L" "as last read" "-L" "on disk" files)))
            (unless (memq status '(0 1))
              (error "diff3 failed (%s): %s" status (buffer-string)))
            (cons (zerop status) (buffer-string))))
      (mapc #'delete-file files))))

(defun +merge--replace (text)
  "Make the buffer TEXT with minimal edits, so point, marks and folds survive."
  (save-restriction
    (widen)
    (let ((source (generate-new-buffer " *merge*")))
      (unwind-protect
          (progn (with-current-buffer source (insert text))
                 (replace-region-contents (point-min) (point-max) source 1.0))
        (kill-buffer source)))))

(defun +merge--adopt-disk (theirs)
  "The disk's text THEIRS becomes the ancestor; the buffer no longer stale."
  (setq +merge--ancestor theirs)
  (set-visited-file-modtime))

;;;###autoload
(defun +merge/disk-into-buffer (&optional quiet)
  "Merge what changed on disk into this buffer, keeping your unsaved edits.
Clean merges just happen; overlapping edits open ediff with the ancestor.
QUIET: don't complain when there's nothing to do; return t if merged."
  (interactive)
  (cond
   ((not (+merge--stale-p))
    (unless quiet (message "%s hasn't changed on disk" (buffer-name))) nil)
   ((not (buffer-modified-p))           ; nothing of yours to keep
    (revert-buffer t t t) (unless quiet (message "Reverted %s (no edits of yours)" (buffer-name))) t)
   (t
    (let* ((mine (save-restriction (widen) (buffer-substring-no-properties (point-min) (point-max))))
           (theirs (+merge--disk-text buffer-file-name)))
      (cond
       ((equal mine theirs) (+merge--adopt-disk theirs) t)
       ((null +merge--ancestor)         ; no ancestor: you choose, side by side
        (+merge--ediff mine theirs nil) nil)
       (t
        (pcase-let ((`(,clean . ,merged) (+merge--diff3 mine +merge--ancestor theirs)))
          (if (not clean)
              (progn (+merge--ediff mine theirs +merge--ancestor) nil)
            (+merge--replace merged)
            (+merge--adopt-disk theirs)
            (message "Merged the changes on disk into your edits (still unsaved): %s" (buffer-name))
            t))))))))

(defun +merge--ediff (mine theirs ancestor)
  "Hand overlapping edits to ediff; the result replaces this buffer when you quit."
  (let* ((target (current-buffer))
         (name (buffer-name))
         (a (generate-new-buffer (format "*%s: your edits*" name)))
         (b (generate-new-buffer (format "*%s: on disk*" name)))
         (c (and ancestor (generate-new-buffer (format "*%s: as last read*" name)))))
    (with-current-buffer a (insert mine))
    (with-current-buffer b (insert theirs))
    (when c (with-current-buffer c (insert ancestor)))
    (message "Your edits and the disk's overlap: merge them, then q (the result goes into %s)" name)
    (let ((startup (list (lambda ()
                           (add-hook 'ediff-quit-hook
                                     (lambda ()
                                       (let ((merged (with-current-buffer ediff-buffer-C (buffer-string))))
                                         (with-current-buffer target
                                           (+merge--replace merged)
                                           (+merge--adopt-disk theirs)))
                                       (mapc (lambda (b) (when (buffer-live-p b) (kill-buffer b))) (list a b c)))
                                     nil t)))))
      (if c
          (ediff-merge-buffers-with-ancestor a b c startup)
        (ediff-merge-buffers a b startup)))))

;;;; When it happens on its own

(defun +merge-supersession-a (fn &rest args)
  "First edit of a stale buffer: merge (just after, outside the change
hooks) instead of asking; the edit itself counts as one of yours."
  (if (not +merge--ancestor)
      (apply fn args)
    (let ((buf (current-buffer)))
      (run-at-time 0 nil (lambda () (when (buffer-live-p buf)
                                      (with-current-buffer buf (+merge/disk-into-buffer t))))))))

(defun +merge-save-a (&rest _)
  "Saving a stale buffer: merge first, so the save keeps both sides.
\(Before `basic-save-buffer', whose \"changed on disk\" question comes
before `before-save-hook'.)"
  (when (and buffer-file-name (buffer-modified-p) +merge--ancestor (+merge--stale-p))
    (unless (+merge/disk-into-buffer t)
      (user-error "Not saved: merge the overlapping edits first (ediff is open)"))))

(defun +merge-check-h (&optional frame)
  "Coming back to a stale buffer you've edited: merge now."
  (with-current-buffer (window-buffer (frame-selected-window frame))
    (when (and (buffer-modified-p) +merge--ancestor (+merge--stale-p))
      (+merge/disk-into-buffer t))))

;;;; For agents

;;;###autoload
(defun +merge-edit-file (file fn)
  "Edit FILE through its buffer: call FN there (point at the start, widened).
Saves if the buffer had no unsaved edits; otherwise the change stays in
the buffer next to them and your own save keeps both.  Returns `saved' or
`in-buffer'."
  (let ((buf (or (find-buffer-visiting file) (find-file-noselect file))))
    (with-current-buffer buf
      (when (+merge--stale-p) (+merge/disk-into-buffer t))
      (let ((had-edits (buffer-modified-p)))
        (save-excursion (save-restriction (widen) (goto-char (point-min)) (funcall fn)))
        (if had-edits 'in-buffer
          (save-buffer) 'saved)))))

(add-hook 'find-file-hook #'+merge-remember-h)
(add-hook 'after-save-hook #'+merge-remember-h)
(add-hook 'after-revert-hook #'+merge-remember-h)
(advice-add 'basic-save-buffer :before #'+merge-save-a)
(add-hook 'window-buffer-change-functions #'+merge-check-h)
(defun +merge-focus-h ()
  (when (frame-focus-state) (+merge-check-h)))
(add-function :after after-focus-change-function #'+merge-focus-h)
(advice-add 'ask-user-about-supersession-threat :around #'+merge-supersession-a)

;; Buffers open before this loaded: while the file is unchanged on disk, the
;; disk holds exactly what they last read or saved.
(dolist (buf (buffer-list))
  (with-current-buffer buf
    (when (and buffer-file-name (not +merge--ancestor) (not (file-remote-p buffer-file-name))
               (file-exists-p buffer-file-name) (not (+merge--stale-p))
               (< (or (file-attribute-size (file-attributes buffer-file-name)) 0) +merge-max-size))
      (setq +merge--ancestor (+merge--disk-text buffer-file-name)))))

(map! :leader :desc "Merge disk changes into buffer" "f M" #'+merge/disk-into-buffer)

(provide '+merge)
;;; +merge.el ends here
