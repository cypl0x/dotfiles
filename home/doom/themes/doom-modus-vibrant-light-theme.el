;;; doom-modus-vibrant-light-theme.el --- doom-vibrant's colors, Modus Operandi's white -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Modus Operandi's legibility with doom-vibrant's hues: a white background,
;; doom-one-light's structure (Henrik Lissner, doom-themes), and every
;; foreground color doom-vibrant's, darkened (hue and saturation kept) to
;; 7:1 contrast (WCAG AAA).  See modus-vibrant-palette.el.
;;
;;; Code:

(require 'doom-themes)
;; load-theme evaluates the theme without load-file-name; find the palette
;; where load-theme found this file (custom-theme--load-path).
(load (or (and (or load-file-name buffer-file-name)
               (expand-file-name "modus-vibrant-palette"
                                 (file-name-directory (or load-file-name buffer-file-name))))
          (locate-file "modus-vibrant-palette" (custom-theme--load-path) '(".el" ".elc")))
      nil t)
(defconst modus-vibrant-light-bg "#ffffff" "Modus Operandi's background.")


;;
;;; Variables

(defgroup doom-modus-vibrant-light-theme nil
  "Options for the `doom-modus-vibrant-light' theme."
  :group 'doom-themes)

(defcustom doom-modus-vibrant-light-brighter-modeline nil
  "If non-nil, more vivid colors will be used to style the mode-line."
  :group 'doom-modus-vibrant-light-theme
  :type 'boolean)

(defcustom doom-modus-vibrant-light-brighter-comments nil
  "If non-nil, comments will be highlighted in more vivid colors."
  :group 'doom-modus-vibrant-light-theme
  :type 'boolean)

(defcustom doom-modus-vibrant-light-padded-modeline doom-themes-padded-modeline
  "If non-nil, adds a 4px padding to the mode-line.
Can be an integer to determine the exact padding."
  :group 'doom-modus-vibrant-light-theme
  :type '(choice integer boolean))


;;
;;; Theme definition

(def-doom-theme doom-modus-vibrant-light
  "A light theme inspired by Atom One Light."
  :family 'doom-one
  :background-mode 'light

  ;; name        default   256       16
  ((bg         '("#ffffff" "white"   "white"        ))
   (fg         (list (modus-vibrant-aaa "#383a42" modus-vibrant-light-bg) "#424242" "black"        ))

   ;; These are off-color variants of bg/fg, used primarily for `solaire-mode',
   ;; but can also be useful as a basis for subtle highlights (e.g. for hl-line
   ;; or region), especially when paired with the `doom-darken', `doom-lighten',
   ;; and `doom-blend' helper functions.
   (bg-alt     '("#f0f0f0" "white"   "white"        ))
   (fg-alt     (list (modus-vibrant-aaa "#c6c7c7" modus-vibrant-light-bg) "#c7c7c7" "brightblack"  ))

   ;; These should represent a spectrum from bg to fg, where base0 is a starker
   ;; bg and base8 is a starker fg. For example, if bg is light grey and fg is
   ;; dark grey, base0 should be white and base8 should be black.
   (base0      '("#f0f0f0" "#f0f0f0" "white"        ))
   (base1      '("#e7e7e7" "#e7e7e7" "brightblack"  ))
   (base2      '("#dfdfdf" "#dfdfdf" "brightblack"  ))
   (base3      '("#c6c7c7" "#c6c7c7" "brightblack"  ))
   (base4      '("#9ca0a4" "#9ca0a4" "brightblack"  ))
   (base5      '("#383a42" "#424242" "brightblack"  ))
   (base6      '("#202328" "#2e2e2e" "brightblack"  ))
   (base7      '("#1c1f24" "#1e1e1e" "brightblack"  ))
   (base8      '("#1b2229" "black"   "black"        ))

   (grey       base4)
   (red        (list (modus-vibrant-aaa "#ff665c" modus-vibrant-light-bg) "#e45649" "red"          ))
   (orange     (list (modus-vibrant-aaa "#e69055" modus-vibrant-light-bg) "#dd8844" "brightred"    ))
   (green      (list (modus-vibrant-aaa "#7bc275" modus-vibrant-light-bg) "#50a14f" "green"        ))
   (teal       (list (modus-vibrant-aaa "#4db5bd" modus-vibrant-light-bg) "#44b9b1" "brightgreen"  ))
   (yellow     (list (modus-vibrant-aaa "#FCCE7B" modus-vibrant-light-bg) "#986801" "yellow"       ))
   (blue       (list (modus-vibrant-aaa "#51afef" modus-vibrant-light-bg) "#4078f2" "brightblue"   ))
   (dark-blue  '("#a0bcf8" "#a0bcf8" "blue"         ))
   (magenta    (list (modus-vibrant-aaa "#C57BDB" modus-vibrant-light-bg) "#a626a4" "magenta"      ))
   (violet     (list (modus-vibrant-aaa "#a991f1" modus-vibrant-light-bg) "#b751b6" "brightmagenta"))
   (cyan       (list (modus-vibrant-aaa "#5cEfFF" modus-vibrant-light-bg) "#0184bc" "brightcyan"   ))
   (dark-cyan  (list (modus-vibrant-aaa "#6A8FBF" modus-vibrant-light-bg) "#005478" "cyan"         ))

   ;; These are the "universal syntax classes" that doom-themes establishes.
   ;; These *must* be included in every doom themes, or your theme will throw an
   ;; error, as they are used in the base theme defined in doom-themes-base.
   (highlight      blue)
   (vertical-bar   (doom-darken base2 0.1))
   (selection      dark-blue)
   (builtin        magenta)
   (comments       (if doom-modus-vibrant-light-brighter-comments cyan
                     (list (modus-vibrant-aaa "#9ca0a4" modus-vibrant-light-bg) "#9ca0a4" "brightblack")))
   (doc-comments   (doom-darken comments 0.15))
   (constants      violet)
   (functions      magenta)
   (keywords       red)
   (methods        cyan)
   (operators      blue)
   (type           yellow)
   (strings        green)
   (variables      (doom-darken magenta 0.36))
   (numbers        orange)
   (region         `(,(doom-darken (car bg-alt) 0.1) ,@(doom-darken (cdr base0) 0.3)))
   (error          red)
   (warning        yellow)
   (success        green)
   (vc-modified    orange)
   (vc-added       green)
   (vc-deleted     red)

   ;; These are extra color variables used only in this theme; i.e. they aren't
   ;; mandatory for derived themes.
   (modeline-fg              fg)
   (modeline-fg-alt          (doom-blend
                              violet base4
                              (if doom-modus-vibrant-light-brighter-modeline 0.5 0.2)))
   (modeline-bg              (if doom-modus-vibrant-light-brighter-modeline
                                 (doom-darken base2 0.05)
                               base1))
   (modeline-bg-alt          (if doom-modus-vibrant-light-brighter-modeline
                                 (doom-darken base2 0.1)
                               base2))
   (modeline-bg-inactive     (doom-darken bg 0.1))
   (modeline-bg-alt-inactive `(,(doom-darken (car bg-alt) 0.05) ,@(cdr base1)))

   (-modeline-pad
    (when doom-modus-vibrant-light-padded-modeline
      (if (integerp doom-modus-vibrant-light-padded-modeline) doom-modus-vibrant-light-padded-modeline 4))))

  ;;;; Base theme face overrides
  (;; AAA here too: doom-one-light's shadow (base4) stood at 2.6:1.
   (shadow :foreground fg-alt)
   ((font-lock-comment-face &override)
    :background (if doom-modus-vibrant-light-brighter-comments base0 'unspecified))
   ((font-lock-doc-face &override) :slant 'italic)
   ((line-number &override) :foreground (doom-lighten base4 0.15))
   ((line-number-current-line &override) :foreground base8)
   (mode-line
    :background modeline-bg :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg)))
   (mode-line-inactive
    :background modeline-bg-inactive :foreground modeline-fg-alt
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-inactive)))
   (mode-line-emphasis
    :foreground (if doom-modus-vibrant-light-brighter-modeline base8 highlight))
   (shadow :foreground base4)
   (tooltip :background base1 :foreground fg)

   ;;;; centaur-tabs
   (centaur-tabs-unselected :background bg-alt :foreground base4)
   ;;;; css-mode <built-in> / scss-mode
   (css-proprietary-property :foreground orange)
   (css-property             :foreground green)
   (css-selector             :foreground blue)
   ;;;; doom-modeline
   (doom-modeline-bar :background (if doom-modus-vibrant-light-brighter-modeline modeline-bg highlight))
   ;;;; ediff <built-in>
   (ediff-current-diff-A        :foreground red   :background (doom-lighten red 0.8))
   (ediff-current-diff-B        :foreground green :background (doom-lighten green 0.8))
   (ediff-current-diff-C        :foreground blue  :background (doom-lighten blue 0.8))
   (ediff-current-diff-Ancestor :foreground teal  :background (doom-lighten teal 0.8))
   ;;;; helm
   (helm-candidate-number :background blue :foreground bg)
   ;;;; lsp-mode
   (lsp-ui-doc-background      :background base0)
   ;;;; magit
   (magit-blame-heading     :foreground orange :background bg-alt)
   (magit-diff-removed :foreground (doom-darken red 0.2) :background (doom-blend red bg 0.1))
   (magit-diff-removed-highlight :foreground red :background (doom-blend red bg 0.2) :bold bold)
   ;;;; markdown-mode
   (markdown-markup-face     :foreground base5)
   (markdown-header-face     :inherit 'bold :foreground red)
   ((markdown-code-face &override)       :background base1)
   (mmm-default-submode-face :background base1)
   ;;;; outline <built-in>
   ((outline-1 &override) :foreground red)
   ((outline-2 &override) :foreground orange)
   ;;;; org <built-in>
   ((org-block &override) :background base1)
   ((org-block-begin-line &override) :foreground fg :slant 'italic)
   (org-ellipsis :underline nil :background bg     :foreground red)
   ((org-quote &override) :background base1)
   ;;;; posframe
   (ivy-posframe               :background base0)
   ;;;; selectrum
   (selectrum-current-candidate :background base2)
   ;;;; vertico
   (vertico-current :background base2)
   ;;;; solaire-mode
   (solaire-mode-line-face
    :inherit 'mode-line
    :background modeline-bg-alt
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-alt)))
   (solaire-mode-line-inactive-face
    :inherit 'mode-line-inactive
    :background modeline-bg-alt-inactive
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-alt-inactive)))
   ;;;; web-mode
   (web-mode-current-element-highlight-face :background dark-blue :foreground bg)
   ;;;; wgrep <built-in>
   (wgrep-face :background base1)
   ;;;; whitespace
   ((whitespace-tab &override)         :background (if (not (default-value 'indent-tabs-mode)) base0 'unspecified))
   ((whitespace-indentation &override) :background (if (default-value 'indent-tabs-mode) base0 'unspecified)))

  ;;;; Base theme variable overrides-
  ()
  )

;;; doom-modus-vibrant-light-theme.el ends here
