;;; lisp/+diagnostics.el --- Diagnostics at point, in a popup that fits -*- lexical-binding: t; -*-
;;
;; flycheck's message at point showed through flycheck-popup-tip (popup.el,
;; drawn with overlays in the buffer's own lines): a long message, such as
;; an org-lint finding, wrapped in odd places and the popup jumped above the
;; cursor with a gap.  Now it shows in the echo area (`+diagnostics-where',
;; default), or in a child frame right under the line at the error's column:
;;   - one block per diagnostic: a colored mark for its level, the message
;;     wrapped at word boundaries to fit the window, the checker and rule
;;     dimmed after it
;;   - the completion popup's colors and border, so popups look alike
;;   - gone at the next key; shown only in normal state (Doom's rule: it
;;     mustn't get in the way of typing or a selection)
;;
;;; Code:

(require 'cl-lib)
(require 'color)

(declare-function posframe-show "ext:posframe" (buffer-or-name &rest args))
(declare-function posframe-hide "ext:posframe" (buffer-or-name))
(declare-function posframe-poshandler-point-bottom-left-corner "ext:posframe" (info))
(declare-function flycheck-error-message "ext:flycheck" (err))
(declare-function flycheck-error-level "ext:flycheck" (err))
(declare-function flycheck-error-checker "ext:flycheck" (err))
(declare-function flycheck-error-id "ext:flycheck" (err))
(declare-function flycheck-error-pos "ext:flycheck" (err))
(declare-function evil-normal-state-p "ext:evil" (&optional state))
(declare-function evil-emacs-state-p "ext:evil" (&optional state))
(declare-function flycheck-popup-tip-mode "ext:flycheck-popup-tip" (&optional arg))
(defvar flycheck-display-errors-function)
(defvar flycheck-clear-displayed-errors-function)
(defvar corfu--index)

(defvar +diagnostics-buffer " *+diagnostics*")

(defun +diagnostics--level-face (level)
  (pcase level ('error 'error) ('warning 'warning) (_ 'success)))

(defun +diagnostics--width ()
  "Columns for the text: the window's width from the cursor, at least 40,
at most 90."
  (max 40 (min 90 (- (window-body-width) (current-column) 4))))

(defun +diagnostics--format (errors width)
  (with-temp-buffer
    (let ((fill-column width) (first t))
      (dolist (err errors)
        (unless first (insert "\n"))
        (setq first nil)
        (let ((beg (point)))
          (insert (propertize "● " 'face (+diagnostics--level-face (flycheck-error-level err)))
                  (string-trim (flycheck-error-message err)))
          (let ((source (string-join (delq nil (list (and (flycheck-error-checker err)
                                                          (symbol-name (flycheck-error-checker err)))
                                                     (flycheck-error-id err)
                                                     ;; well-formed fixes every finding
                                                     (and (eq (flycheck-error-checker err) 'well-formed)
                                                          "SPC P x fixes")))
                                     " · ")))
            (unless (string-empty-p source)
              (insert "  " (propertize source 'face 'shadow))))
          ;; Wrap at words, continuation lines under the text, not the mark.
          (let ((fill-prefix "  ") (adaptive-fill-mode nil))
            (fill-region beg (point))))))
    (buffer-string)))

(defcustom +diagnostics-where 'echo
  "Where diagnostics at point show: `echo' (the echo area, as you asked for
2026-11-05: text where the eye already goes for messages) or `popup' (a
child frame under the line)."
  :type '(choice (const echo) (const popup)) :group 'flycheck)

(defun +diagnostics-show (errors)
  "Show ERRORS (flycheck's at point) where `+diagnostics-where' says."
  (when (and errors
             ;; Doom's rule: not while typing, selecting or completing.
             (if (and (bound-and-true-p evil-local-mode) (not (evil-emacs-state-p)))
                 (evil-normal-state-p)
               (and (not (region-active-p))
                    (not (ignore-errors (>= corfu--index 0))))))
    (if (or (eq +diagnostics-where 'echo) (not (display-graphic-p)) (not (require 'posframe nil t)))
        ;; The echo area: as wide as the frame, wrapped there; eldoc waits.
        (let ((message-log-max nil))
          (message "%s" (+diagnostics--format errors (max 40 (- (frame-width) 4)))))
      (let ((text (+diagnostics--format errors (+diagnostics--width))))
        (posframe-show +diagnostics-buffer
                       :string text
                       :position (point)
                       :poshandler #'posframe-poshandler-point-bottom-left-corner
                       :background-color (face-attribute 'corfu-default :background nil 'default)
                       :foreground-color (face-attribute 'default :foreground)
                       :border-width 1
                       :border-color (face-attribute 'corfu-border :background nil 'default)
                       :left-fringe 6 :right-fringe 6
                       :lines-truncate t
                       :accept-focus nil)
        (add-hook 'pre-command-hook #'+diagnostics-hide)))))

(defun +diagnostics-hide ()
  "Hide the diagnostics popup."
  (remove-hook 'pre-command-hook #'+diagnostics-hide)
  (when (fboundp 'posframe-hide)
    (posframe-hide +diagnostics-buffer)))

(with-eval-after-load 'flycheck
  ;; In place of Doom's flycheck-popup-tip.
  (remove-hook 'flycheck-mode-hook '+syntax-init-popups-h)
  (setq-default flycheck-display-errors-function #'+diagnostics-show
                flycheck-clear-displayed-errors-function #'+diagnostics-hide)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p flycheck-popup-tip-mode)
        (funcall 'flycheck-popup-tip-mode -1))
      (kill-local-variable 'flycheck-display-errors-function)
      (kill-local-variable 'flycheck-clear-displayed-errors-function))))


;;;; The look: a tint, not a squiggle

;; Squiggles (wave underlines) are loud, and they sit under the text, so
;; dozens of prose findings make a page look broken.  Each diagnosed piece
;; of text gets a faint tint of its severity's color instead: errors red,
;; warnings amber, suggestions blue (green reads as "fine"), spelling as an
;; error.  The same colors everywhere: flycheck, flymake (eglot), jinx,
;; the fringe.  Hover or move onto it: the message is in the echo area.

(defcustom +diagnostics-style 'tint
  "How diagnosed text looks: `tint' (a faint background in the severity's
color), `line' (a straight underline), or `wave' (the classic squiggle)."
  :type '(choice (const tint) (const line) (const wave)) :group 'flycheck)

(defcustom +diagnostics-tint 0.16
  "How strong the tint is: the share of the severity color in the background."
  :type 'number :group 'flycheck)

(defun +diagnostics--color (face attr fallback)
  (let ((c (face-attribute face attr nil t)))
    (if (and (stringp c) (not (string-prefix-p "unspecified" c))) c fallback)))

(defun +diagnostics--blend (color background alpha)
  "COLOR over BACKGROUND at ALPHA, as #rrggbb."
  (let ((a (color-name-to-rgb color)) (b (color-name-to-rgb background)))
    (if (not (and a b)) color
      (apply #'color-rgb-to-hex
             (append (cl-mapcar (lambda (x y) (+ (* alpha x) (* (- 1 alpha) y))) a b) '(2))))))

(defun +diagnostics-colors ()
  "The severity colors: (ERROR WARNING INFO), from the theme."
  (list (+diagnostics--color 'error :foreground "#ff665c")
        (+diagnostics--color 'warning :foreground "#FCCE7B")
        (+diagnostics--color 'font-lock-function-name-face :foreground "#51afef")))

(defun +diagnostics--spec (color)
  (pcase +diagnostics-style
    ('tint (list :background (+diagnostics--blend color (+diagnostics--color 'default :background "#242730")
                                                  +diagnostics-tint)
                 :underline nil))
    ('line (list :underline (list :color color :style 'line :position t) :background 'unspecified))
    (_ (list :underline (list :color color :style 'wave) :background 'unspecified))))

(defun +diagnostics-apply-look-h (&rest _)
  "Give every diagnostics face the look of `+diagnostics-style'."
  (pcase-let ((`(,err ,warn ,info) (+diagnostics-colors)))
    (dolist (pair `((flycheck-error . ,err) (flycheck-warning . ,warn) (flycheck-info . ,info)
                    (flymake-error . ,err) (flymake-warning . ,warn) (flymake-note . ,info)
                    (jinx-misspelled . ,err)))
      (when (facep (car pair))
        (apply #'set-face-attribute (car pair) nil (+diagnostics--spec (cdr pair)))))
    ;; The fringe marks in the same three colors.
    (dolist (pair `((flycheck-fringe-error . ,err) (flycheck-fringe-warning . ,warn) (flycheck-fringe-info . ,info)))
      (when (facep (car pair)) (set-face-attribute (car pair) nil :foreground (cdr pair))))))

(add-hook 'doom-load-theme-hook #'+diagnostics-apply-look-h 90)
(with-eval-after-load 'flycheck (+diagnostics-apply-look-h))
(with-eval-after-load 'flymake (+diagnostics-apply-look-h))
(with-eval-after-load 'jinx (+diagnostics-apply-look-h))

;;;; Calm: suggestions only where you are

;; In prose a page can hold a hundred suggestions (info level).  With
;; `+diagnostics-calm-mode' (on in text buffers) they are tinted only in the
;; paragraph at point; elsewhere only the fringe shows them.  Errors and
;; warnings stay visible everywhere.

(defface +diagnostics-calm '((t))
  "Suggestions away from point: nothing (the fringe still marks them)."
  :group (quote flycheck))

(defvar-local +diagnostics--calm-region nil "(BEG . END) where suggestions show now.")
(defvar +diagnostics-calm-mode)

(defun +diagnostics--paragraph ()
  (save-excursion
    (cons (progn (backward-paragraph) (point)) (progn (forward-paragraph 1) (point)))))

(defun +diagnostics--calm-overlay-p (ov)
  (and (overlay-get ov 'flycheck-overlay)
       (memq (overlay-get ov 'category) '(flycheck-info-overlay))))

(defun +diagnostics-calm-update (&rest _)
  "Show suggestions in the paragraph at point, calm them elsewhere."
  (when +diagnostics-calm-mode
    (let ((here (+diagnostics--paragraph)))
      (unless (equal here +diagnostics--calm-region)
        (setq +diagnostics--calm-region here)
        (dolist (ov (overlays-in (point-min) (point-max)))
          (when (+diagnostics--calm-overlay-p ov)
            (overlay-put ov 'face (unless (and (< (overlay-start ov) (cdr here))
                                               (> (overlay-end ov) (car here)))
                                    '+diagnostics-calm))))))))

(defun +diagnostics-calm-recheck-h ()
  "New overlays after a check: calm them too."
  (setq +diagnostics--calm-region nil)
  (+diagnostics-calm-update))

(define-minor-mode +diagnostics-calm-mode
  "Prose suggestions tinted only in the paragraph at point."
  :lighter nil
  (if +diagnostics-calm-mode
      (progn (add-hook 'post-command-hook #'+diagnostics-calm-update nil t)
             (add-hook 'flycheck-after-syntax-check-hook #'+diagnostics-calm-recheck-h nil t)
             (+diagnostics-calm-recheck-h))
    (remove-hook 'post-command-hook #'+diagnostics-calm-update t)
    (remove-hook 'flycheck-after-syntax-check-hook #'+diagnostics-calm-recheck-h t)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (+diagnostics--calm-overlay-p ov) (overlay-put ov 'face nil)))
    (setq +diagnostics--calm-region nil)))

(add-hook 'text-mode-hook #'+diagnostics-calm-mode)

;;;; Read-only buffers: no diagnostics

;; The lock in the mode line means the buffer is read-only (a file you may
;; not write, a manual, a buffer put in read-only or view mode): there is
;; nothing to fix, so the checkers, the spelling and the AI review pause
;; there, and come back when it becomes writable (C-x C-q).

(defvar-local +diagnostics--paused nil "Modes paused here because the buffer is read-only.")

(defconst +diagnostics-pausable '(flycheck-mode flymake-mode jinx-mode)
  "Diagnostics modes that pause in read-only buffers.")

(defun +diagnostics-read-only-h (&rest _)
  "Pause diagnostics while this buffer is read-only; resume when writable."
  (cond
   ((and buffer-read-only (not +diagnostics--paused))
    (dolist (mode +diagnostics-pausable)
      (when (and (boundp mode) (symbol-value mode))
        (push mode +diagnostics--paused)
        (funcall mode -1))))
   ((and (not buffer-read-only) +diagnostics--paused)
    (let ((modes +diagnostics--paused))
      (setq +diagnostics--paused nil)
      (dolist (mode modes) (funcall mode 1))))))

(add-hook 'read-only-mode-hook #'+diagnostics-read-only-h)
(add-hook 'view-mode-hook #'+diagnostics-read-only-h)
(add-hook 'find-file-hook #'+diagnostics-read-only-h 90)
;; Global modes turn themselves on after a major mode starts; pause again.
(defun +diagnostics-read-only-later-h ()
  "A diagnostics mode came on in a read-only buffer: pause it, after this hook."
  (when (and buffer-read-only (not +diagnostics--paused))
    (let ((buf (current-buffer)))
      (run-at-time 0 nil (lambda () (when (buffer-live-p buf)
                                      (with-current-buffer buf (+diagnostics-read-only-h))))))))
(dolist (hook '(flycheck-mode-hook jinx-mode-hook flymake-mode-hook))
  (add-hook hook #'+diagnostics-read-only-later-h))
(provide '+diagnostics)
;;; +diagnostics.el ends here
