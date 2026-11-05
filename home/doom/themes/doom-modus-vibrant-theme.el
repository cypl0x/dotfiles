;;; doom-modus-vibrant-theme.el --- doom-vibrant at Modus contrast -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; doom-vibrant (Henrik Lissner, doom-themes), every foreground color moved in
;; lightness, hue and saturation kept, to 7:1 contrast with the background
;; (WCAG AAA, the Modus themes' standard): red, blue, magenta, violet, the
;; greys of comments and line numbers.  Generated from doom-vibrant-theme.el;
;; see modus-vibrant-palette.el.
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
(defconst modus-vibrant-dark-bg "#242730" "doom-vibrant's background, kept.")


;;
;;; Variables

(defgroup doom-modus-vibrant-theme nil
  "Options for the `doom-modus-vibrant' theme."
  :group 'doom-themes)

(defcustom doom-modus-vibrant-brighter-modeline nil
  "If non-nil, more vivid colors will be used to style the mode-line."
  :group 'doom-modus-vibrant-theme
  :type 'boolean)

(defcustom doom-modus-vibrant-brighter-comments nil
  "If non-nil, comments will be highlighted in more vivid colors."
  :group 'doom-modus-vibrant-theme
  :type 'boolean)

(defcustom doom-modus-vibrant-padded-modeline doom-themes-padded-modeline
  "If non-nil, adds a 4px padding to the mode-line.
Can be an integer to determine the exact padding."
  :group 'doom-modus-vibrant-theme
  :type '(choice integer boolean))


;;
;;; Theme definition

(def-doom-theme doom-modus-vibrant
  "A dark theme based off of doom-one with more vibrant colors."
  :family 'doom-one
  :background-mode 'light

  ;; name        gui       256           16
  ((bg         '("#242730" "black"       "black" ))
   (fg         (list (modus-vibrant-aaa "#bbc2cf" modus-vibrant-dark-bg) "#bfbfbf"     "brightwhite" ))

   ;; These are off-color variants of bg/fg, used primarily for `solaire-mode',
   ;; but can also be useful as a basis for subtle highlights (e.g. for hl-line
   ;; or region), especially when paired with the `doom-darken', `doom-lighten',
   ;; and `doom-blend' helper functions.
   (bg-alt     '("#2a2e38" "black"       "black"       ))
   (fg-alt     (list (modus-vibrant-aaa "#5D656B" modus-vibrant-dark-bg) "#5d5d5d"     "white"       ))

   ;; These should represent a spectrum from bg to fg, where base0 is a starker
   ;; bg and base8 is a starker fg. For example, if bg is light grey and fg is
   ;; dark grey, base0 should be white and base8 should be black.
   (base0      '("#1c1f24" "#101010"     "black"       ))
   (base1      '("#1c1f24" "#1e1e1e"     "brightblack" ))
   (base2      '("#21272d" "#21212d"     "brightblack" ))
   (base3      '("#23272e" "#262626"     "brightblack" ))
   (base4      '("#484854" "#5e5e5e"     "brightblack" ))
   (base5      (list (modus-vibrant-aaa "#62686E" modus-vibrant-dark-bg) "#666666"     "brightblack" ))
   (base6      (list (modus-vibrant-aaa "#757B80" modus-vibrant-dark-bg) "#7b7b7b"     "brightblack" ))
   (base7      (list (modus-vibrant-aaa "#9ca0a4" modus-vibrant-dark-bg) "#979797"     "brightblack" ))
   (base8      '("#DFDFDF" "#dfdfdf"     "white"       ))

   (grey       base4)
   (red        (list (modus-vibrant-aaa "#ff665c" modus-vibrant-dark-bg) "#ff6655" "red"             ))
   (orange     (list (modus-vibrant-aaa "#e69055" modus-vibrant-dark-bg) "#dd8844" "brightred"       ))
   (green      (list (modus-vibrant-aaa "#7bc275" modus-vibrant-dark-bg) "#99bb66" "green"           ))
   (teal       (list (modus-vibrant-aaa "#4db5bd" modus-vibrant-dark-bg) "#44b9b1" "brightgreen"     ))
   (yellow     (list (modus-vibrant-aaa "#FCCE7B" modus-vibrant-dark-bg) "#ECBE7B" "yellow"          ))
   (blue       (list (modus-vibrant-aaa "#51afef" modus-vibrant-dark-bg) "#51afef" "brightblue"      ))
   (dark-blue  '("#1f5582" "#2257A0" "blue"            ))
   (magenta    (list (modus-vibrant-aaa "#C57BDB" modus-vibrant-dark-bg) "#c678dd" "brightmagenta"   ))
   (violet     (list (modus-vibrant-aaa "#a991f1" modus-vibrant-dark-bg) "#a9a1e1" "magenta"         )) ;a9a1e1
   (cyan       (list (modus-vibrant-aaa "#5cEfFF" modus-vibrant-dark-bg) "#46D9FF" "brightcyan"      ))
   (dark-cyan  (list (modus-vibrant-aaa "#6A8FBF" modus-vibrant-dark-bg) "#5699AF" "cyan"            ))

   ;; These are the "universal syntax classes" that doom-themes establishes.
   ;; These *must* be included in every doom themes, or your theme will throw an
   ;; error, as they are used in the base theme defined in doom-themes-base.
   (highlight      blue)
   (vertical-bar   base0)
   (selection      dark-blue)
   (builtin        magenta)
   (comments       (if doom-modus-vibrant-brighter-comments dark-cyan base5))
   (doc-comments   (if doom-modus-vibrant-brighter-comments (doom-lighten dark-cyan 0.15) base7))
   (constants      violet)
   (functions      cyan)
   (keywords       blue)
   (methods        violet)
   (operators      magenta)
   (type           yellow)
   (strings        green)
   (variables      (doom-lighten magenta 0.4))
   (numbers        orange)
   (region         "#3d4451")
   (error          red)
   (warning        yellow)
   (success        green)
   (vc-modified    yellow)
   (vc-added       green)
   (vc-deleted     red)

   ;; These are extra color variables used only in this theme; i.e. they aren't
   ;; mandatory for derived themes.
   (modeline-fg             fg)
   (modeline-fg-inactive    base6)
   (modeline-bg             (if doom-modus-vibrant-brighter-modeline
                                `("#383f58" ,@(cdr base1))
                              `(,(doom-darken (car bg) 0.15) ,@(cdr base1))))
   (modeline-bg-alt         (if doom-modus-vibrant-brighter-modeline
                                modeline-bg
                              `(,(car bg-alt) ,@(cdr base0))))
   (modeline-bg-inactive     `(,(doom-darken (car bg-alt) 0.2) ,@(cdr base0)))
   (modeline-bg-alt-inactive (doom-darken bg 0.25))

   (-modeline-pad
    (when doom-modus-vibrant-padded-modeline
      (if (integerp doom-modus-vibrant-padded-modeline) doom-modus-vibrant-padded-modeline 4))))


  ;;;; Base theme face overrides
  (((font-lock-comment-face &override)
    :background (if doom-modus-vibrant-brighter-comments (doom-darken bg-alt 0.095) 'unspecified))
   ((line-number &override) :foreground base4)
   ((line-number-current-line &override) :foreground blue :bold bold)
   (mode-line
    :background modeline-bg :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg)))
   (mode-line-inactive
    :background modeline-bg-inactive :foreground modeline-fg-inactive
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-inactive)))
   (mode-line-emphasis :foreground (if doom-modus-vibrant-brighter-modeline base8 highlight))
   ((org-block &override) :background (doom-darken base3 0.1))

   ;;;; all-the-icons
   ((all-the-icons-dblue &override) :foreground dark-cyan)
   ;;;; centaur-tabs
   (centaur-tabs-unselected :background bg-alt :foreground base6)
   ;;;; css-mode <built-in> / scss-mode
   (css-proprietary-property :foreground orange)
   (css-property             :foreground green)
   (css-selector             :foreground blue)
   ;;;; doom-modeline
   (doom-modeline-bar
    :background (if doom-modus-vibrant-brighter-modeline modeline-bg highlight))
   (doom-modeline-buffer-path
    :foreground (if doom-modus-vibrant-brighter-modeline base8 blue) :bold bold)
   ;;;; elscreen
   (elscreen-tab-other-screen-face :background "#353a42" :foreground "#1e2022")
   ;;;; markdown-mode
   (markdown-header-face :inherit 'bold :foreground red)
   ;;;; solaire-mode
   (solaire-mode-line-face
    :inherit 'mode-line
    :background modeline-bg-alt
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-alt)))
   (solaire-mode-line-inactive-face
    :inherit 'mode-line-inactive
    :background modeline-bg-alt-inactive
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,modeline-bg-alt-inactive)))
   ;;;; whitespace <built-in>
   (whitespace-empty :background base2))

  ;;;; Base theme variable overrides
  ;; ()
  )

;;; doom-modus-vibrant-theme.el ends here
