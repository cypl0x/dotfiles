;;; modus-vibrant-palette.el --- AAA contrast for doom-vibrant's colors -*- lexical-binding: t; -*-
;;
;; doom-vibrant's hues, Modus's legibility: every foreground color keeps its
;; hue and saturation and moves in lightness until it stands at
;; `modus-vibrant-contrast' (7:1, WCAG AAA, as the Modus themes do) against
;; the background.  Used by doom-modus-vibrant (dark) and
;; doom-modus-vibrant-light (Modus Operandi's white).
;;
;;; Code:

(require 'color)
(require 'cl-lib)

(defvar modus-vibrant-contrast 7.0
  "The contrast every foreground color reaches against the background.")

(defun modus-vibrant--rgb (hex)
  "HEX (#rrggbb) as (R G B), 0.0-1.0, without asking the display (in
batch, `color-name-to-rgb' doesn't read hex)."
  (mapcar (lambda (i) (/ (string-to-number (substring hex i (+ i 2)) 16) 255.0)) '(1 3 5)))

(defun modus-vibrant--luminance (hex)
  "WCAG relative luminance of HEX."
  (cl-destructuring-bind (r g b) (modus-vibrant--rgb hex)
    (cl-flet ((lin (c) (if (<= c 0.03928) (/ c 12.92) (expt (/ (+ c 0.055) 1.055) 2.4))))
      (+ (* 0.2126 (lin r)) (* 0.7152 (lin g)) (* 0.0722 (lin b))))))

(defun modus-vibrant-contrast-ratio (a b)
  "WCAG contrast ratio between colors A and B."
  (let ((la (modus-vibrant--luminance a)) (lb (modus-vibrant--luminance b)))
    (/ (+ (max la lb) 0.05) (+ (min la lb) 0.05))))

(defun modus-vibrant-aaa (hex bg &optional target)
  "HEX, lighter or darker (same hue and saturation) until it stands at
TARGET (default `modus-vibrant-contrast') against BG."
  (let ((target (or target modus-vibrant-contrast)))
    (if (>= (modus-vibrant-contrast-ratio hex bg) target)
        hex
      (cl-destructuring-bind (h s l) (apply #'color-rgb-to-hsl (modus-vibrant--rgb hex))
        (let ((step (if (< (modus-vibrant--luminance bg) 0.18) 0.005 -0.005))
              (color hex))
          (while (and (< (modus-vibrant-contrast-ratio color bg) target) (< 0 l 1))
            (setq l (min 1.0 (max 0.0 (+ l step)))
                  color (apply #'color-rgb-to-hex (append (color-hsl-to-rgb h s l) '(2)))))
          color)))))

(provide 'modus-vibrant-palette)
;;; modus-vibrant-palette.el ends here
