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

(require 'cl-lib)
(require 'color)

(declare-function doom--theme-is-colorscheme-p "doom-emacs" (theme))

(defun +themes-only-one-a (theme &optional _no-confirm no-enable)
  "Before `load-theme': disable the other color themes, unless NO-ENABLE.
THEME is the one being loaded.  Also forget each frame's cursor color:
setting it (evil does, per state) writes it into the frame's `cursor'
face, which Doom then read back as the new theme's: the light theme's
black cursor stayed in the dark one."
  (unless no-enable
    ;; Before anything changes: the audit compares with this.
    (+themes--snapshot)
    (dolist (other custom-enabled-themes)
      (when (and (not (eq other theme))
                 (if (fboundp 'doom--theme-is-colorscheme-p)
                     (doom--theme-is-colorscheme-p other)
                   t))
        (disable-theme other)))
    (dolist (frame (frame-list))
      (set-face-attribute 'cursor frame :background 'unspecified))))

(defvar +themes--before nil
  "Each face's colors in the selected frame before the last theme load:
hash FACE → (FOREGROUND . BACKGROUND), for the audit's leftover check.")

(defun +themes--snapshot ()
  "Remember every face's colors in the selected frame."
  (let ((h (make-hash-table :test #'eq :size 2000)))
    (dolist (face (face-list))
      (puthash face (cons (face-attribute face :foreground) (face-attribute face :background)) h))
    (setq +themes--before h)))

(defconst +themes-audit-runtime-faces '(pulse-highlight-face cursor)
  "Faces packages color at run time (pulse.el animates one, evil the cursor).")

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

;;;; Is the theme what it should be?  M-x +themes/audit
;;
;; After a switch nothing of the last theme should be left, and what you
;; read should be readable.  The audit checks both, in this Emacs:
;;   - one color theme enabled; no doom-color palette applied under another
;;     theme; no face in your frames differing from what the theme gives a
;;     new frame (how the cursor kept the last theme's color); colors your
;;     config fixes for every theme;
;;   - the faces you read, at WCAG contrast against what they're drawn on:
;;     under 4.5:1 is a warning, under 3:1 an error.
;; It runs after each theme load too, and only speaks up when it finds
;; something (`+themes-audit-on-load').

(defvar +themes-audit-on-load t "Audit quietly after each theme load.")

;; Doom's vc-gutter (+pretty) clears the diff-hl faces' backgrounds after
;; every theme load: doom themes color the marks by their foreground.
;; Modus colors them by their background, so there the marks fell back to
;; the fringe's foreground: black bars, changed and added and deleted alike.
;; A mark left without a color of its own gets the one the theme meant.
(defun +themes-diff-hl-colors-h ()
  "Give diff-hl's marks the theme's color when only a background had it."
  (dolist (face '(diff-hl-insert diff-hl-delete diff-hl-change))
    (when (facep face)
      (dolist (frame (frame-list))
        (unless (+themes--color-p (face-attribute face :foreground frame))
          (when-let* ((meant (or (+themes--theme-attr face :foreground frame)
                                 (+themes--theme-attr face :background frame)
                                 (+themes--spec-attr face :foreground frame))))
            (set-face-attribute face frame :foreground meant)))))))

(with-eval-after-load 'diff-hl
  ;; After Doom's (depth 0) clears the backgrounds.
  (add-hook 'doom-load-theme-hook #'+themes-diff-hl-colors-h 50)
  (add-hook 'diff-hl-mode-hook #'+themes-diff-hl-colors-h 50))

(defconst +themes-audit-meaning
  '((diff-hl-insert diff-hl-change diff-hl-delete)
    (flycheck-fringe-error flycheck-fringe-warning flycheck-fringe-info)
    (error warning success)
    (org-todo org-done))
  "Groups of faces whose color carries meaning: each needs one of its
own, unlike the text's and unlike the others' in its group.")

(defconst +themes-audit-faces
  '(default mode-line mode-line-inactive minibuffer-prompt header-line
    region hl-line vertico-current corfu-default corfu-current
    font-lock-keyword-face font-lock-string-face font-lock-function-name-face
    font-lock-variable-name-face font-lock-type-face font-lock-constant-face
    font-lock-builtin-face font-lock-comment-face font-lock-doc-face
    line-number line-number-current-line link error warning success shadow
    org-level-1 org-level-2 org-level-3 org-level-4 org-todo org-done
    org-headline-done org-date org-code org-verbatim org-block org-meta-line
    doom-modeline-buffer-path doom-modeline-buffer-file)
  "Faces read all day: their contrast is checked.")

(defun +themes--rgb (color)
  "COLOR (a name or #rrggbb) as (R G B), 0.0-1.0, or nil."
  (if (string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" color)
      ;; Read here: in batch `color-name-to-rgb' reads no hex.
      (mapcar (lambda (i) (/ (string-to-number (match-string i color) 16) 255.0)) '(1 2 3))
    (color-name-to-rgb color)))

(defun +themes--luminance (color)
  (when-let* ((rgb (+themes--rgb color)))
    (cl-destructuring-bind (r g b)
        (mapcar (lambda (c) (if (<= c 0.03928) (/ c 12.92) (expt (/ (+ c 0.055) 1.055) 2.4))) rgb)
      (+ (* 0.2126 r) (* 0.7152 g) (* 0.0722 b)))))

(defun +themes-contrast (fg bg)
  "WCAG contrast ratio of FG on BG (color names or #rrggbb), or nil."
  (let ((a (+themes--luminance fg)) (b (+themes--luminance bg)))
    (and a b (/ (+ (max a b) 0.05) (+ (min a b) 0.05)))))

(defun +themes--color-p (c) (and (stringp c) (not (string-prefix-p "unspecified" c))))

(declare-function doom-blend "doom-themes" (color1 color2 alpha))

(defun +themes-dim (fg bg &optional ratio)
  "FG blended toward BG as far as it stays at RATIO (default 4.5) on BG:
as dim as is still readable, whichever way the theme is (light or dark)."
  (let ((ratio (or ratio 4.5)) (best fg))
    (cl-loop for alpha from 1.0 downto 0.0 by 0.02
             for c = (doom-blend fg bg alpha)
             while (>= (or (+themes-contrast c bg) 0) ratio)
             do (setq best c))
    best))

(defun +themes-tint (color bg fg alpha &optional ratio)
  "BG tinted with COLOR by ALPHA at most, so FG stays at RATIO (4.5) on it."
  (let ((ratio (or ratio 4.5)))
    (or (cl-loop for a from alpha downto 0.0 by 0.02
                 for c = (doom-blend color bg a)
                 when (>= (or (+themes-contrast fg c) 0) ratio) return c)
        bg)))

(defun +themes--theme-attr (face attr frame)
  "ATTR of FACE as the enabled themes give it on FRAME (the first that sets
it), or nil."
  (cl-some (lambda (entry)
             (when (memq (car entry) custom-enabled-themes)
               (let ((v (plist-get (face-spec-choose (cadr entry) frame) attr)))
                 (and v (not (eq v 'unspecified)) v))))
           (get face 'theme-face)))

(defun +themes--spec-attr (face attr frame)
  "ATTR of FACE as its specs give it on FRAME: the first enabled theme's
spec that sets it, else the face's own default spec; nil when none does."
  (or (cl-some (lambda (entry)
                 (when (memq (car entry) custom-enabled-themes)
                   (let ((v (plist-get (face-spec-choose (cadr entry) frame) attr)))
                     (and v (not (eq v 'unspecified)) v))))
               (get face 'theme-face))
      (let ((v (plist-get (face-spec-choose (face-default-spec face) frame) attr)))
        (and v (not (eq v 'unspecified)) v))))

(defun +themes-audit-findings (&optional frame)
  "Problems with the current theme in FRAME: list of (LEVEL WHAT DETAIL)."
  (let* ((frame (or frame (selected-frame))) out
         (themes (seq-filter (lambda (th) (if (fboundp 'doom--theme-is-colorscheme-p)
                                              (doom--theme-is-colorscheme-p th) t))
                             custom-enabled-themes)))
    (when (> (length themes) 1)
      (push (list 'error "several themes on" (format "%s: the later ones' faces leak in" themes)) out))
    ;; Leftovers: faces whose color the last switch didn't change although
    ;; the theme now says another (their specs: the enabled themes' in
    ;; priority order, then the face's own default).
    (dolist (face (and +themes--before (face-list)))
      (dolist (attr '(:foreground :background))
        (let ((here (face-attribute face attr frame))
              (before (funcall (if (eq attr :foreground) #'car #'cdr) (gethash face +themes--before)))
              (want (+themes--spec-attr face attr frame)))
          (when (and (+themes--color-p here) (+themes--color-p want)
                     (equal here before)
                     (not (memq face +themes-audit-runtime-faces))
                     (not (equal (+themes--rgb here) (+themes--rgb want)))
                     ;; Evil colors the cursor per state on purpose.
                     (not (and (eq face 'cursor) (bound-and-true-p evil-local-mode))))
            (push (list 'error (format "%s %s" face attr)
                        (format "%s here, but the theme says %s: left over from an earlier theme" here want))
                  out)))))
    ;; Colors fixed by your config under every theme (the `user' theme).
    (dolist (setting (get 'user 'theme-settings))
      (pcase-let ((`(,kind ,face ,_ ,spec) setting))
        (when (eq kind 'theme-face)
          (let* ((clause (car-safe spec))
                 (plist (if (listp (cadr clause)) (cadr clause) (cdr clause))))
            (dolist (attr '(:foreground :background))
              (let ((c (plist-get (if (listp plist) plist nil) attr)))
                (when (and (stringp c) (string-prefix-p "#" c) (not (+themes-doom-p)))
                  (push (list 'warning (format "%s %s" face attr)
                              (format "fixed to %s by your config, whatever the theme" c))
                        out))))))))
    ;; Meaning: colors that say something (added, changed, deleted; error,
    ;; warning) must differ from the text and from each other.
    (let ((text (face-foreground 'default frame t)))
      (dolist (group +themes-audit-meaning)
        (let ((seen nil))
          (dolist (face group)
            (when (facep face)
              (let ((fg (face-foreground face frame t)))
                (cond ((or (not (+themes--color-p fg)) (equal (+themes--rgb fg) (+themes--rgb text)))
                       (push (list 'error (symbol-name face)
                                   (format "drawn in the text's own color (%s): what it means is lost" fg))
                             out))
                      ((rassoc (+themes--rgb fg) seen)
                       (push (list 'error (symbol-name face)
                                   (format "the same color as %s (%s): they can't be told apart"
                                           (car (rassoc (+themes--rgb fg) seen)) fg))
                             out))
                      (t (push (cons face (+themes--rgb fg)) seen)))))))))
    ;; Readability.
    (let ((default-bg (face-background 'default frame t)))
      (dolist (face +themes-audit-faces)
        (when (facep face)
          (let* ((fg (face-foreground face frame t))
                 (bg (or (face-background face frame t) default-bg))
                 (ratio (and (+themes--color-p fg) (+themes--color-p bg) (+themes-contrast fg bg))))
            (when (and ratio (< ratio 4.5))
              (push (list (if (< ratio 3) 'error 'warning) (symbol-name face)
                          (format "%s on %s: %.1f:1 (readable from 4.5)" fg bg ratio))
                    out))))))
    (nreverse out)))

;;;###autoload
(defun +themes/audit ()
  "Check the theme: nothing left over from another, everything readable."
  (interactive)
  (let ((findings (+themes-audit-findings)) (theme (car custom-enabled-themes)))
    (with-current-buffer (get-buffer-create "*theme audit*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "Theme audit: %s\n\n" theme) 'face 'bold))
        (if (null findings)
            (insert (propertize "All clear: one theme on, nothing left over, everything readable.\n" 'face 'success))
          (pcase-dolist (`(,level ,what ,detail) findings)
            (insert (propertize (if (eq level 'error) "✗ " "! ") 'face (if (eq level 'error) 'error 'warning))
                    (propertize what 'face 'bold) "  " detail "\n")))
        (insert (propertize (format "\n%d faces checked for contrast, %d for leftovers.  g: again\n"
                                    (length +themes-audit-faces) (length (face-list)))
                            'face 'shadow)))
      (special-mode)
      (local-set-key "g" #'+themes/audit)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    findings))

(defun +themes--audit-after-load-h (_theme)
  "After a theme loads: a word in the echo area if the audit finds anything."
  (when +themes-audit-on-load
    (run-with-idle-timer
     1 nil
     (lambda ()
       (when-let* ((findings (+themes-audit-findings))
                   (errors (cl-count 'error findings :key #'car)))
         (message "Theme check: %d problem%s (%d unreadable or left over): M-x +themes/audit"
                  (length findings) (if (cdr findings) "s" "") errors))))))

(add-hook 'enable-theme-functions #'+themes--audit-after-load-h 90)

;;;; One light/dark switch
;;
;; Themes were switched 21 times by name in the log (load-theme 8,
;; vellumory's 13).  SPC t D goes to the other side; each side remembers the
;; theme you used last there.  Vellumory follows by itself (its `tint' and
;; `auto' recolour on `enable-theme-functions').

(defvar +themes-light 'modus-operandi "The light theme SPC t D switches to.")
(defvar +themes-dark 'doom-vibrant "The dark theme SPC t D switches to.")

(defun +themes-dark-p ()
  "Non-nil if the current theme's background is dark."
  (let ((bg (face-background 'default nil t)))
    (and (+themes--color-p bg) (< (or (+themes--luminance bg) 1) 0.2))))

(defun +themes-remember-side-h (theme)
  "The theme just enabled becomes its side's choice for SPC t D."
  (when (eq theme (car custom-enabled-themes))
    (if (+themes-dark-p) (setq +themes-dark theme) (setq +themes-light theme))))

(add-hook 'enable-theme-functions #'+themes-remember-side-h 95)

;;;###autoload
(defun +themes/toggle-dark ()
  "Switch to the other side: the light theme or the dark one."
  (interactive)
  (load-theme (if (+themes-dark-p) +themes-light +themes-dark) t)
  (message "%s" (car custom-enabled-themes)))

(map! :leader :desc "Light / dark theme" "t D" #'+themes/toggle-dark)

(provide '+themes)
;;; +themes.el ends here
