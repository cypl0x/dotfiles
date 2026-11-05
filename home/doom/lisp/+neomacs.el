;;; lisp/+neomacs.el --- This config under NEO Emacs (neomacs): what differs -*- lexical-binding: t; -*-
;;
;; neomacs (home/neomacs.nix, the `neomacs' command) runs this same Doom
;; config.  Where it differs from GNU Emacs, here:
;;
;; Zoom   (C-ä, SPC t b …) failed: "No fonts match `-*-Maple Mono NF-…-20-…'".
;;        Not the font (fontconfig has Maple Mono NF): neomacs' `x-list-fonts'
;;        is a stub returning nil in a graphical session (upstream main,
;;        2026-11-05), so resolving any font by name fails, and Doom's zoom
;;        re-applies `doom-font' by name.  Here zoom scales the default face's
;;        :height instead, which neomacs renders (same steps, same reset).
;;
;; Scroll (a mouse wheel) jumped by lines, where GNU Emacs here scrolls
;;        smoothly: GTK gives GNU pixel deltas even for wheels; neomacs
;;        sends wheels as line steps (touchpads as pixels).  ultra-scroll can
;;        only jump lines without pixel data, so under neomacs it gives way
;;        to `pixel-scroll-precision-mode' interpolating each wheel step into
;;        a smooth pixel scroll (neomacs supports those calls, issue #396).
;;
;;; Code:

(defvar +neomacs-p (and (getenv "NEOMACS_DOOM") t)
  "Non-nil when this Emacs is neomacs running this config.")

(defvar +neomacs--initial-height nil "The default face's :height before zooming.")

(defun +neomacs-adjust-font-size-a (_fn increment &optional fixed-size-p _font-alist)
  "Around `doom-adjust-font-size': zoom by face :height (no font lookup).
INCREMENT is in points as there (nil resets); FIXED-SIZE-P makes it the size."
  (let ((height (face-attribute 'default :height nil t)))
    (unless +neomacs--initial-height (setq +neomacs--initial-height height))
    (let ((new (cond ((null increment) +neomacs--initial-height)
                     (fixed-size-p (* 10 increment))
                     (t (+ height (* 10 increment))))))
      (when (<= new 0) (user-error "Can't make the font any smaller"))
      (set-face-attribute 'default nil :height new)
      (unless increment (setq +neomacs--initial-height nil))
      t)))

(defvar pixel-scroll-precision-interpolate-mice)
(defvar pixel-scroll-precision-interpolate-page)
(defvar pixel-scroll-precision-interpolation-total-time)
(declare-function pixel-scroll-precision-mode "pixel-scroll" (&optional arg))
(declare-function ultra-scroll-mode "ext:ultra-scroll" (&optional arg))

(defun +neomacs-smooth-wheel-h (&rest _)
  "Mouse wheels scroll smoothly: interpolated pixel scrolling, not ultra-scroll."
  (when (bound-and-true-p ultra-scroll-mode) (ultra-scroll-mode -1))
  (setq pixel-scroll-precision-interpolate-mice t
        pixel-scroll-precision-interpolate-page t
        pixel-scroll-precision-interpolation-total-time 0.12)
  (pixel-scroll-precision-mode 1))

(when +neomacs-p
  (advice-add 'doom-adjust-font-size :around #'+neomacs-adjust-font-size-a))

(defun +neomacs-ultra-scroll-h ()
  "Doom just turned ultra-scroll on: hand over to interpolated scrolling."
  (when (bound-and-true-p ultra-scroll-mode)
    (run-at-time 0 nil #'+neomacs-smooth-wheel-h)))

(when +neomacs-p
  ;; After Doom turns ultra-scroll on (first input or first file).
  (add-hook 'ultra-scroll-mode-hook #'+neomacs-ultra-scroll-h)
  (with-eval-after-load 'pixel-scroll (+neomacs-smooth-wheel-h)))

(provide '+neomacs)
;;; +neomacs.el ends here
