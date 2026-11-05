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
;; Scroll  one trackpad gesture kept scrolling for 20+ s and felt sluggish.
;;        neomacs scrolls in its compositor only when pre-command-hook holds
;;        nothing but a few whitelisted functions (display/neo/scroll.rs);
;;        Doom always has more (Evil, which-key, magit …), so every scroll
;;        event goes through the evaluator, one by one, and a gesture's 60–120
;;        events a second pile up.  Here the scroll command folds every scroll
;;        event already waiting (same direction) into one: deltas summed,
;;        one scroll per batch, no backlog.
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

(defun +neomacs--wheel-p (event)
  (memq (event-basic-type event) '(wheel-up wheel-down wheel-left wheel-right)))

(defun +neomacs--merge-wheel (event next)
  "EVENT with NEXT's scroll added (same direction): pixels and line counts summed."
  (let* ((a (nth 4 event)) (b (nth 4 next))
         (pixels (cond ((and (consp a) (consp b)) (cons (+ (car a) (car b)) (+ (cdr a) (cdr b))))
                       (t a))))
    (list (car event) (nth 1 event) (or (nth 2 event) 1)
          (+ (or (nth 3 event) 1) (or (nth 3 next) 1))
          pixels)))

(defvar +neomacs-scroll-speed 2.5
  "Trackpad scroll distance, relative to what neomacs reports.
GNU Emacs (pgtk) scrolls GTK's smooth delta x 100 pixels, and GTK divides
Wayland's axis values by 10 (pgtkterm.c, gdkdevice-wayland.c); neomacs
scrolls winit's pixel delta as is, so the same gesture goes a shorter way.")

(defun +neomacs--speed-up (event)
  "EVENT with its pixel delta scaled by `+neomacs-scroll-speed'."
  (let ((pixels (nth 4 event)))
    (if (and (consp pixels) (numberp (car pixels)) (numberp (cdr pixels)))
        (append (take 4 event)
                (list (cons (* (car pixels) +neomacs-scroll-speed)
                            (* (cdr pixels) +neomacs-scroll-speed)))
                (nthcdr 5 event))
      event)))

(defun +neomacs-coalesce-wheel-a (args)
  "Filter for the scroll command's ARGS: fold in every scroll event already
waiting in the same direction, so one gesture is one scroll, not hundreds;
then scale it by `+neomacs-scroll-speed'."
  (let ((event (car args)))
    (when (and (consp event) (+neomacs--wheel-p event))
      (catch 'done
        (while (input-pending-p)
          (let ((next (read-event nil nil 0)))
            (cond ((null next) (throw 'done nil))
                  ((and (consp next) (eq (car next) (car event)))
                   (setq event (+neomacs--merge-wheel event next)))
                  (t (push next unread-command-events) (throw 'done nil))))))
      (setq event (+neomacs--speed-up event)))
    (cons event (cdr args))))

(when +neomacs-p
  (advice-add 'doom-adjust-font-size :around #'+neomacs-adjust-font-size-a)
  (advice-add 'ultra-scroll :filter-args #'+neomacs-coalesce-wheel-a)
  (advice-add 'mwheel-scroll :filter-args #'+neomacs-coalesce-wheel-a))

(provide '+neomacs)
;;; +neomacs.el ends here
