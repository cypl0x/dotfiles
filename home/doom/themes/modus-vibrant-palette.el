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

;;;; Vivid: the same contrast, darkened in OKLCH
;;
;; Darkening in HSL kept the hue's name but not how colorful it looks: at
;; 7:1 on white, doom-vibrant's green, yellow and violet all came out a dull
;; dark brown-grey, and the light theme's colors looked alike.  OKLCH
;; (Björn Ottosson's perceptual space) separates lightness from chroma, so
;; here only the lightness goes down, the hue stays, and the chroma stays
;; as high as sRGB can show at that lightness: Modus Operandi's way of
;; being both legible and colorful.

(defun modus-vibrant--srgb->linear (c)
  (if (<= c 0.04045) (/ c 12.92) (expt (/ (+ c 0.055) 1.055) 2.4)))

(defun modus-vibrant--linear->srgb (c)
  (if (<= c 0.0031308) (* 12.92 c) (- (* 1.055 (expt c (/ 1 2.4))) 0.055)))

(defun modus-vibrant--oklch (hex)
  "HEX as (L C H): OKLCH, H in radians."
  (cl-destructuring-bind (r g b) (mapcar #'modus-vibrant--srgb->linear (modus-vibrant--rgb hex))
    (let* ((l (expt (+ (* 0.4122214708 r) (* 0.5363325363 g) (* 0.0514459929 b)) (/ 1.0 3)))
           (m (expt (+ (* 0.2119034982 r) (* 0.6806995451 g) (* 0.1073969566 b)) (/ 1.0 3)))
           (s (expt (+ (* 0.0883024619 r) (* 0.2817188376 g) (* 0.6299787005 b)) (/ 1.0 3)))
           (L (+ (* 0.2104542553 l) (* 0.7936177850 m) (* -0.0040720468 s)))
           (A (+ (* 1.9779984951 l) (* -2.4285922050 m) (* 0.4505937099 s)))
           (B (+ (* 0.0259040371 l) (* 0.7827717662 m) (* -0.8086757660 s))))
      (list L (sqrt (+ (* A A) (* B B))) (atan B A)))))

(defun modus-vibrant--oklch->rgb (L C H)
  "OKLCH L C H as linear-then-gamma sRGB (R G B), possibly out of 0-1."
  (let* ((A (* C (cos H))) (B (* C (sin H)))
         (l (expt (+ L (* 0.3963377774 A) (* 0.2158037573 B)) 3))
         (m (expt (- L (* 0.1055613458 A) (* 0.0638541728 B)) 3))
         (s (expt (- L (* 0.0894841775 A) (* 1.2914855480 B)) 3)))
    (mapcar (lambda (c) (if (< c 0) -1.0 (modus-vibrant--linear->srgb c)))
            (list (+ (* 4.0767416621 l) (* -3.3077115913 m) (* 0.2309699292 s))
                  (+ (* -1.2684380046 l) (* 2.6097574011 m) (* -0.3413193965 s))
                  (+ (* -0.0041960863 l) (* -0.7034186147 m) (* 1.7076147010 s))))))

(defun modus-vibrant--in-gamut-p (rgb)
  (cl-every (lambda (c) (<= -1e-6 c 1.000001)) rgb))

(defun modus-vibrant--oklch->hex (L C H)
  "OKLCH as #rrggbb, chroma lowered until sRGB can show it."
  (let ((lo 0.0) (hi C))
    (unless (modus-vibrant--in-gamut-p (modus-vibrant--oklch->rgb L C H))
      (dotimes (_ 24)
        (let ((mid (/ (+ lo hi) 2)))
          (if (modus-vibrant--in-gamut-p (modus-vibrant--oklch->rgb L mid H)) (setq lo mid) (setq hi mid))))
      (setq C lo))
    (apply #'format "#%02x%02x%02x"
           (mapcar (lambda (c) (round (* 255 (min 1.0 (max 0.0 c))))) (modus-vibrant--oklch->rgb L C H)))))

(defun modus-vibrant-aaa-vivid (hex bg &optional target)
  "HEX at TARGET contrast (default `modus-vibrant-contrast') against BG,
by its OKLCH lightness alone: hue kept, chroma kept as far as sRGB allows."
  (let ((target (or target modus-vibrant-contrast)))
    (if (>= (modus-vibrant-contrast-ratio hex bg) target)
        hex
      (cl-destructuring-bind (L C H) (modus-vibrant--oklch hex)
        ;; The lightness that just reaches TARGET: lower on a light
        ;; background, higher on a dark one.
        (let* ((darker (> (modus-vibrant--luminance bg) 0.18))
               (lo (if darker 0.0 L)) (hi (if darker L 1.0)))
          (dotimes (_ 30)
            (let* ((mid (/ (+ lo hi) 2))
                   (ok (>= (modus-vibrant-contrast-ratio (modus-vibrant--oklch->hex mid C H) bg) target)))
              (if darker
                  (if ok (setq lo mid) (setq hi mid))
                (if ok (setq hi mid) (setq lo mid)))))
          (modus-vibrant--oklch->hex (if darker lo hi) C H))))))

(provide 'modus-vibrant-palette)
;;; modus-vibrant-palette.el ends here
