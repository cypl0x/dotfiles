;;; lisp/+dired.el --- Dired and dirvish: how long ago, next to when -*- lexical-binding: t; -*-
;;
;; Every file in dired and dirvish also shows its age, "2h 13min ago", as
;; an extra column on the right; the exact timestamp stays where it is.
;; Two units at most (3d 4h, 2y 3mo); "just now" under a minute; future
;; times (clock skew, archives) as "in 5min".  Recent files stand out: under
;; an hour in the accent color, under a day normal, older dimmed.
;;
;; `+dired-age-mode' toggles it (on by default), in dirvish as the attribute
;; `file-age', in plain dired as text after each line.
;;
;; Order: folders first, then newest first, everywhere: `ls' sorts as it lists
;; (-t, --group-directories-first), so nothing is re-sorted after dired opens.
;; /github listings leave -t out (lisp/+gh-fs.el): a time per entry is a call.
;;
;;; Code:

(defvar dired-listing-switches)
(with-eval-after-load 'dired
  (setq dired-listing-switches "-ahlt --group-directories-first"))

(require 'cl-lib)

(defvar dirvish-attributes)
(declare-function dirvish--render-attrs "ext:dirvish" (&optional clear))
(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))
(declare-function dired-move-to-filename "dired" (&optional raise-error eol))

(defgroup +dired nil "Dired, our way." :group 'dired)

(defface +dired-age-recent '((t :inherit font-lock-keyword-face))
  "Age of a file changed within the last hour." :group '+dired)
(defface +dired-age '((t :inherit default))
  "Age of a file changed within the last day." :group '+dired)
(defface +dired-age-old '((t :inherit shadow))
  "Age of an older file." :group '+dired)

(defun +dired-age-string (time &optional now)
  "How long ago TIME was (from NOW): \"2h 13min ago\", \"just now\"."
  (let* ((secs (float-time (time-subtract (or now (current-time)) time)))
         (future (< secs 0))
         (s (abs secs))
         (units '((31536000 . "y") (2592000 . "mo") (604800 . "w") (86400 . "d")
                  (3600 . "h") (60 . "min")))
         (parts nil))
    (if (< s 60) "just now"
      ;; The largest unit that fits, then the next one if it isn't zero.
      (let ((rest (member-if (lambda (u) (>= s (car u))) units)))
        (let ((n (floor s (caar rest))))
          (push (format "%d%s" n (cdar rest)) parts)
          (when-let* ((next (cadr rest))
                      (m (floor (- s (* n (caar rest))) (car next)))
                      ((> m 0)))
            (push (format "%d%s" m (cdr next)) parts))))
      (let ((text (string-join (nreverse parts) " ")))
        (if future (concat "in " text) (concat text " ago"))))))

(defun +dired-age--face (time)
  (let ((secs (float-time (time-subtract nil time))))
    (cond ((< secs 3600) '+dired-age-recent) ((< secs 86400) '+dired-age) (t '+dired-age-old))))

(defconst +dired-age--width 14 "Columns the age takes (\"11mo 30d ago\" and a margin).")

;;;; dirvish

(with-eval-after-load 'dirvish
  (eval
   '(dirvish-define-attribute file-age
      "How long ago the file was modified (an extra column)."
      :right +dired-age--width
      :when (>= win-width 60)
      (when-let* ((time (and f-attrs (file-attribute-modification-time f-attrs))))
        (let ((str (format " %s " (+dired-age-string time))))
          (setq str (string-pad str +dired-age--width nil t))
          (add-face-text-property 0 (length str) (or hl-face (+dired-age--face time)) t str)
          (add-text-properties 0 (length str) `(help-echo ,(format-time-string "%F %T" time)) str)
          `(right . ,str))))
   t))

;;;; plain dired (when dirvish isn't drawing the buffer)

(defun +dired-age--plain-h ()
  "Ages after each file line of this dired buffer."
  (remove-overlays (point-min) (point-max) '+dired-age t)
  (unless (bound-and-true-p dirvish-override-dired-mode)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((file (ignore-errors (dired-get-filename nil t)))
                    (attrs (file-attributes file))
                    (time (file-attribute-modification-time attrs)))
          (let ((ov (make-overlay (line-end-position) (line-end-position))))
            (overlay-put ov '+dired-age t)
            (overlay-put ov 'after-string
                         (propertize (concat "  " (+dired-age-string time)) 'face (+dired-age--face time)))))
        (forward-line 1)))))

;;;; The switch

(define-minor-mode +dired-age-mode
  "Show how long ago each file in dired and dirvish was modified."
  :global t :init-value nil :group '+dired
  (if +dired-age-mode
      (progn
        (add-hook 'dired-after-readin-hook #'+dired-age--plain-h)
        (with-eval-after-load 'dirvish
          (unless (memq 'file-age dirvish-attributes)
            (setq dirvish-attributes (append dirvish-attributes '(file-age))))))
    (remove-hook 'dired-after-readin-hook #'+dired-age--plain-h)
    (when (boundp 'dirvish-attributes)
      (setq dirvish-attributes (delq 'file-age dirvish-attributes)))))

(+dired-age-mode 1)

(provide '+dired)
;;; +dired.el ends here
