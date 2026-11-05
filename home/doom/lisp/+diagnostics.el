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

(provide '+diagnostics)
;;; +diagnostics.el ends here
