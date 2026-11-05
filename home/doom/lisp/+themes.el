;;; lisp/+themes.el --- One theme at a time -*- lexical-binding: t; -*-
;;
;; `load-theme' adds a theme on top of those enabled; it doesn't replace
;; them.  After doom-vibrant, loading modus-operandi left both enabled
;; (modus-operandi doom-vibrant), and what modus doesn't define came from
;; doom-vibrant: solaire's faces among them, which the minibuffer and echo
;; area are remapped to, so the echo area stayed black.  Now loading a color
;; theme disables the other color themes first, whichever way it's loaded
;; (M-x load-theme, consult-theme, SPC h t).  M-x doom/reload-theme reapplies
;; the current one cleanly.
;;
;;; Code:

(declare-function doom--theme-is-colorscheme-p "doom-emacs" (theme))

(defun +themes-only-one-a (theme &optional _no-confirm no-enable)
  "Before `load-theme': disable the other color themes, unless NO-ENABLE.
THEME is the one being loaded.  Also forget each frame's cursor color:
setting it (evil does, per state) writes it into the frame's `cursor'
face, which Doom then read back as the new theme's: the light theme's
black cursor stayed in the dark one."
  (unless no-enable
    (dolist (other custom-enabled-themes)
      (when (and (not (eq other theme))
                 (if (fboundp 'doom--theme-is-colorscheme-p)
                     (doom--theme-is-colorscheme-p other)
                   t))
        (disable-theme other)))
    (dolist (frame (frame-list))
      (set-face-attribute 'cursor frame :background 'unspecified))))

(defun +themes-doom-p ()
  "Whether a doom-themes theme is the one enabled.
`doom-color' answers from the last doom theme loaded, even under another
(modus-operandi after doom-modus-vibrant: a black completion popup), so
colors from it apply only while a doom theme is on."
  (let ((theme (car custom-enabled-themes)))
    (and theme (string-prefix-p "doom-" (symbol-name theme)))))

(advice-add 'load-theme :before #'+themes-only-one-a)

(defun +themes-cursor-h (_theme)
  "After a theme is enabled: each frame's cursor face from the themes'
specs again, before Doom reads it for evil (`doom-enable-theme-h', depth
-90): the frame's own setting (the last theme's color) won otherwise."
  (dolist (frame (frame-list))
    (face-spec-recalc 'cursor frame)))

(add-hook 'enable-theme-functions #'+themes-cursor-h -95)

(provide '+themes)
;;; +themes.el ends here
