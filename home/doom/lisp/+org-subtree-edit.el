;;; lisp/+org-subtree-edit.el --- C-c ' on a heading: edit the subtree on its own -*- lexical-binding: t; -*-
;;
;; Org edits a src block, a table formula or a footnote in a buffer of its
;; own (C-c ', `org-edit-special').  On a heading it had nothing to offer.
;; Now it opens the subtree alone, as the top of its own Org buffer:
;;
;;   - the subtree promoted to level 1 (a level-4 heading reads as level 1:
;;     folding, SPC c f, C-RET all work as at the top of a file), in a
;;     window below the original;
;;   - C-c ' or C-c C-c: back into the original, at its old level, as one
;;     undo step; C-c C-k: drop the edits;
;;   - if the original subtree changed meanwhile it refuses (and says so)
;;     rather than overwrite either version.
;;
;; Everywhere else C-c ' does what it did.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-end-of-subtree "org" (&optional invisible-ok to-heading element))
(declare-function org-current-level "org" ())
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-element-at-point "org-element" (&optional epom cached-only))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))

(defvar-local +org-subtree-edit--origin nil
  "(BEG-MARKER END-MARKER LEVEL ORIGINAL-TEXT) of the subtree being edited.")

(defvar +org-subtree-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c '") #'+org-subtree-edit-finish)
    (define-key map (kbd "C-c C-c") #'+org-subtree-edit-finish)
    (define-key map (kbd "C-c C-k") #'+org-subtree-edit-abort)
    map))

(define-minor-mode +org-subtree-edit-mode
  "Editing one Org subtree on its own: C-c ' writes it back, C-c C-k drops it."
  :lighter " Subtree"
  (when +org-subtree-edit-mode
    (setq-local header-line-format
                (substitute-command-keys
                 "  Subtree on its own: \\<+org-subtree-edit-mode-map>\\[+org-subtree-edit-finish] writes it back · \\[+org-subtree-edit-abort] drops the edits"))))

(defun +org-subtree-edit--shift (text delta)
  "TEXT with every heading's level changed by DELTA stars (not below 1)."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (while (re-search-forward "^\\(\\*+\\) " nil t)
      (let ((n (max 1 (+ (length (match-string 1)) delta))))
        (replace-match (make-string n ?*) t t nil 1)))
    (buffer-string)))

;;;###autoload
(defun +org-subtree-edit ()
  "Edit the subtree at point in a buffer of its own (see the file)."
  (interactive)
  (pop-to-buffer
   (save-excursion
    (org-back-to-heading t)
    (let* ((beg (point))
           (level (org-current-level))
           (end (save-excursion (org-end-of-subtree t t) (point)))
           (text (buffer-substring-no-properties beg end))
           (source (current-buffer))
           ;; Markers in the source (made inside the edit buffer they pointed there).
           (beg-marker (copy-marker beg))
           (end-marker (copy-marker end t))
           (title (org-get-heading t t t t))
           (buf (generate-new-buffer (format "*Org Subtree: %s*" (truncate-string-to-width title 40 nil nil "…")))))
      (with-current-buffer buf
        (insert (+org-subtree-edit--shift text (- 1 level)))
        (org-mode)
        (setq +org-subtree-edit--origin
              (list beg-marker end-marker level text source))
        (+org-subtree-edit-mode 1)
        (set-buffer-modified-p nil)
        (goto-char (point-min)))
      buf))
   '((display-buffer-below-selected) (window-height . 0.5))))

(defun +org-subtree-edit-finish ()
  "Write the subtree back into its file, at its old level."
  (interactive)
  (pcase-let ((`(,beg ,end ,level ,original ,source) +org-subtree-edit--origin)
              (edited (buffer-string)))
    (unless (buffer-live-p source) (user-error "The original buffer is gone"))
    (with-current-buffer source
      (unless (equal (buffer-substring-no-properties beg end) original)
        (user-error "The subtree changed in %s meanwhile; copy what you need, then C-c C-k"
                    (buffer-name source)))
      (save-excursion
        (goto-char beg)
        (let ((new (+org-subtree-edit--shift edited (- level 1))))
          (unless (string-suffix-p "\n" new) (setq new (concat new "\n")))
          (delete-region beg end)
          (insert new))))
    (+org-subtree-edit--close source)
    (message "Subtree written back")))

(defun +org-subtree-edit-abort ()
  "Close without writing the subtree back."
  (interactive)
  (when (or (not (buffer-modified-p)) (y-or-n-p "Drop your edits of this subtree? "))
    (+org-subtree-edit--close (nth 4 +org-subtree-edit--origin))))

(defun +org-subtree-edit--close (source)
  (let ((buf (current-buffer)) (origin +org-subtree-edit--origin))
    (set-marker (nth 0 origin) nil) (set-marker (nth 1 origin) nil)
    (set-buffer-modified-p nil)
    (quit-window t (get-buffer-window buf))
    (when (buffer-live-p source)
      (when-let* ((w (get-buffer-window source))) (select-window w)))))

(defun +org-subtree-edit-special-a (fn &rest args)
  "`org-edit-special' on a heading line edits the subtree; elsewhere as before."
  (if (and (derived-mode-p 'org-mode) (org-at-heading-p)
           (eq (org-element-type (org-element-at-point)) 'headline))
      (+org-subtree-edit)
    (apply fn args)))

(with-eval-after-load 'org
  (advice-add 'org-edit-special :around #'+org-subtree-edit-special-a))

(provide '+org-subtree-edit)
;;; +org-subtree-edit.el ends here
