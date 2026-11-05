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
THEME is the one being loaded."
  (unless no-enable
    (dolist (other custom-enabled-themes)
      (when (and (not (eq other theme))
                 (if (fboundp 'doom--theme-is-colorscheme-p)
                     (doom--theme-is-colorscheme-p other)
                   t))
        (disable-theme other)))))

(advice-add 'load-theme :before #'+themes-only-one-a)

(provide '+themes)
;;; +themes.el ends here
