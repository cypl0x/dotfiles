;;; lisp/+fonts.el --- Font configuration, ligatures, and face tuning -*- lexical-binding: t; -*-
;;
;; Maple Mono NF ligature support, doom font slots, face customization,
;; and diagnostic tooling.
;;
;;; Commentary:
;;
;; Doom provides five font slots: `doom-font', `doom-big-font',
;; `doom-variable-pitch-font', `doom-serif-font', and `doom-symbol-font'.
;; This module configures all of them for Maple Mono NF and provides a
;; comprehensive ligature character-variant table derived from the font's
;; OpenType `calt' feature.
;;
;; Maple Mono NF v7.9 supports ligatures via the `calt' (contextual
;; alternates) OpenType feature plus numerous `cvXX' and `ssXX' stylistic
;; sets.  The `ligature.el' package (used by Doom's `:ui ligatures' module)
;; registers character sequences in `composition-function-table' so that
;; HarfBuzz can compose them into the font's ligature glyphs.
;;
;;; Code:

;;;; Font Slots ──────────────────────────────────────────────────────────────

(setq doom-font                (font-spec :family "Maple Mono NF" :size 16 :weight 'regular)
      doom-big-font            (font-spec :family "Maple Mono NF" :size 20 :weight 'regular)
      doom-variable-pitch-font (font-spec :family "Maple Mono NF" :size 16 :weight 'regular)
      doom-serif-font          (font-spec :family "Maple Mono NF" :size 16 :weight 'regular)
      doom-symbol-font         (font-spec :family "Maple Mono NF"))

;; When a proper variable-pitch font is installed, uncomment to use it for
;; prose (org-mode, markdown).  Candidates: "Inter", "Source Sans 3",
;; "Noto Sans", "IBM Plex Sans".
;; (setq doom-variable-pitch-font (font-spec :family "Inter" :size 15))

;;;; Face Tuning ─────────────────────────────────────────────────────────────

;; Ensure font-lock survives font re-initialization on daemon frames.
(add-hook 'server-after-make-frame-hook
          (lambda ()
            (unless (default-value 'font-lock-mode)
              (global-font-lock-mode 1)))
          90)

(after! doom-themes
  (custom-set-faces!
    ;; Use italic weight for comments — Maple Mono NF has a beautiful italic.
    '(font-lock-comment-face :slant italic)
    '(font-lock-doc-face :slant italic)
    ;; Bold keywords to make control flow pop.
    '(font-lock-keyword-face :weight bold)
    ;; Slightly dimmed line numbers to reduce visual noise.
    `(line-number :foreground ,(doom-darken (doom-color 'fg) 0.6))
    `(line-number-current-line :foreground ,(doom-color 'fg) :weight bold)
    ;; pulse.el's olive #AAAA33 (gptel flashes each answer with it, pulsar's
    ;; generic face inherits it) under the light text: contrast 1.38.  Blue
    ;; blended into the background keeps the flash visible at 5.24 (WCAG AA).
    `(pulse-highlight-start-face :background ,(doom-blend 'blue 'bg 0.25))
    `(pulse-highlight-face :background ,(doom-blend 'blue 'bg 0.25))))

;; *bold* in an Org headline looked like the rest of it: headlines are bold
;; (org-level-N), and so was Org's face for *…*.  Maple Mono NF has SemiBold
;; and ExtraBold: headlines take the first, *bold* markup the second, which
;; tells them apart in headlines and in body text alike.
(defface +org-bold '((t :inherit bold :weight extra-bold))
  "Org's *bold* markup: a step heavier than headlines."
  :group 'org-faces)

(custom-set-faces!
  '((org-level-1 org-level-2 org-level-3 org-level-4
     org-level-5 org-level-6 org-level-7 org-level-8)
    :weight semi-bold))

(after! org
  (setf (alist-get "*" org-emphasis-alist nil nil #'equal) '(+org-bold))
  ;; org-emphasis-alist is compiled into the font-lock regexps.
  (when (fboundp 'org-set-emph-re) (org-set-emph-re 'org-emphasis-alist org-emphasis-alist)))

;;;; Maple Mono NF Ligatures ─────────────────────────────────────────────────

;; Maple Mono NF supports these ligature sequences via its `calt' feature.
;; This table was derived from the font's OpenType GSUB lookup rules and the
;; font's official documentation (https://github.com/subframe7536/maple-font).
;;
;; The `set-ligatures!' macro from Doom's :ui ligatures module registers
;; these in `+ligatures-alist' → `ligature-set-ligatures' → HarfBuzz
;; `composition-function-table'.

(after! ligature
  ;; Comprehensive Maple Mono NF ligature set.
  ;; Grouped by category for maintainability.
  (ligature-set-ligatures
   'prog-mode
   '(;; Equality / comparison
     "==" "!=" "===" "!==" "=/=" ">=" "<=" ">=>" "<=<" "<=>"
     ;; Arrows
     "->" "<-" "=>" "->>" "=>>" "<<-" "<<=" ">>=" "<->" "<--" "-->"
     "<-<" ">->" "-<<" "-<" ">-" "<~" "~>" "<~~" "~~>" "<~>"
     ;; Double arrows
     "==>" "<==" "<<=" "=>>"
     ;; Pipe / composition
     "|>" "<|" "<|>" "||>" "<||" "|||>" "<|||"
     ;; Logic
     "&&" "||" "!!"
     ;; Comments / documentation
     "//" "///" "/*" "*/" "/**" "<!--" "-->"
     ;; Haskell / functional
     "::" ":::" ":=" "=:=" ".." "..." "..<"
     ;; Type theory / math
     "\\/" "/\\" "<*>" "<+>" "<$>" "<$" "$>"
     ;; Brackets / delimiters
     "{|" "|}" "[|" "|]" "#{" "#[" "#(" "#_" "#_(" "#:" "#!" "#="
     ;; Misc operators
     "++" "+++" "**" "***" "??" "???" "?." "?:" ";;" ";;;"
     "~=" "~-" "^=" "%%" "|=" "||=" "&&="
     ;; Bit shifts
     "<<" "<<<" ">>" ">>>"
     ;; Web
     "://" "www"
     ;; Underscore / hash
     "__" "#!" "#=" "#_" "#__" "#_("
     ;; Markup
     "</>")))

;; Maple Mono NF also supports log-level badge ligatures in text modes.
(after! ligature
  (ligature-set-ligatures
   'text-mode
   '("[TRACE]" "[DEBUG]" "[INFO]" "[WARN]" "[ERROR]" "[FATAL]"
     "[TODO]" "[FIXME]" "[NOTE]" "[HACK]" "[MARK]")))

;; Org gets the code ligatures that can't be Org syntax: prose arrows and
;; comparisons read well, and src blocks show most of what their language
;; would (C-c ' edits them with all of it).  Left out because Org writes
;; them: ** (headings, bold), || |> <| |} (table cells), // __ ++ (markup),
;; << >> <<< >>> (targets, noweb), %% (diary sexps), :// www (links), #_ #(
;; #[ (keywords nearby), /* */ (italic around *bold*).
(after! ligature
  (ligature-set-ligatures
   'org-mode
   '("==" "!=" "===" "!==" "=/=" ">=" "<=" "<=>"
     "->" "<-" "=>" "->>" "=>>" "<<-" "<->" "<--" "-->"
     "<~" "~>" "<~~" "~~>" "<~>" "==>" "<=="
     "&&" "::" ":::" ":=" "=:=" ".." "..." "..<"
     "<*>" "<+>" "<$>" "?:" "??" "!!" ";;")))


;; Mathematical letters (𝑓, 𝐱, ℝ's neighbours; U+1D400–U+1D7FF) showed as
;; boxes: no font in the fallback chain draws them (Casual's menus use them,
;; so do Lean and Agda).  DejaVu Math TeX Gyre, installed, does.
(add-hook 'after-setting-font-hook
          (defun +fonts-math-alphanumerics-h ()
            (when (find-font (font-spec :family "DejaVu Math TeX Gyre"))
              (set-fontset-font t '(#x1D400 . #x1D7FF) "DejaVu Math TeX Gyre"))))
;;;; Stylistic Sets ──────────────────────────────────────────────────────────

;; Maple Mono NF offers many character variants (`cv01'–`cv66') and stylistic
;; sets (`ss01'–`ss11').  Enable them via font features.
;;
;; Key stylistic sets:
;;   ss01: Relaxed coding ligatures (alternative arrow styles)
;;   ss02: Alternative >= and <=
;;   ss03: Alternative &
;;   ss04: Alternative @ symbol
;;   ss05: Alternative {} brackets (more rounded)
;;
;; Enable desired sets by uncommenting/editing:

(defun +fonts/apply-maple-features ()
  "Apply Maple Mono NF OpenType feature settings."
  (interactive)
  (set-face-attribute 'default nil
                      :font (font-spec :family "Maple Mono NF"
                                       :size 14
                                       ;; Enable slashed zero and contextual alternates.
                                       :otf '(latn dflt (calt zero)))))

;;;; Diagnostics ─────────────────────────────────────────────────────────────

(defun +fonts/ligature-showcase ()
  "Open a buffer showing all configured ligatures rendered with the current font.
Useful for verifying which ligatures the font actually supports."
  (interactive)
  (let ((buf (get-buffer-create "*Ligature Showcase*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Ligature Showcase — Maple Mono NF\n"
                            'face '(:height 1.5 :weight bold))
                (propertize "If ligatures work, multi-char sequences render as single glyphs.\n\n"
                            'face 'font-lock-comment-face)
                (propertize "═══ Arrows ═══\n" 'face '(:weight bold))
                "->  =>  <-  <-  -->  ==>  <->  <=>  ->>  =>>  <<-  <<=\n"
                "~>  <~  ~~>  <~~  <~>  |>  <|  <|>  ||>  <||  |||>\n\n"
                (propertize "═══ Equality & Comparison ═══\n" 'face '(:weight bold))
                "==  !=  ===  !==  =/=  >=  <=  >=>\n\n"
                (propertize "═══ Logic & Operators ═══\n" 'face '(:weight bold))
                "&&  ||  !!  ++  +++  **  ***  ??  ?:  ?.\n\n"
                (propertize "═══ Haskell / Functional ═══\n" 'face '(:weight bold))
                "::  :::  :=  =:=  ..  ...  ..<  <*>  <+>  <$>\n\n"
                (propertize "═══ Comments ═══\n" 'face '(:weight bold))
                "//  ///  /*  */  /**  <!--  -->\n\n"
                (propertize "═══ Brackets ═══\n" 'face '(:weight bold))
                "{|  |}  [|  |]  #{  #[  #(  #_  #_(  #:  #!  #=\n\n"
                (propertize "═══ Misc ═══\n" 'face '(:weight bold))
                "www  ://  __  %%  ^=  ~=  |=  ||=  &&=  ;;\n\n"
                (propertize "═══ Type Theory / Math ═══\n" 'face '(:weight bold))
                "\\/  /\\  <*>  <+>  <$>  <$  $>\n"))
      (goto-char (point-min))
      (prog-mode)
      (view-mode 1))
    (pop-to-buffer buf)))

(defun +fonts/font-info ()
  "Show detailed information about the current frame's font configuration."
  (interactive)
  (let ((buf (get-buffer-create "*Font Info*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Font Configuration\n" 'face '(:height 1.5 :weight bold))
                "\n"
                (format "doom-font:            %s\n" doom-font)
                (format "doom-big-font:        %s\n" doom-big-font)
                (format "doom-variable-pitch:  %s\n" doom-variable-pitch-font)
                (format "doom-serif-font:      %s\n" doom-serif-font)
                (format "doom-symbol-font:     %s\n" doom-symbol-font)
                "\n"
                (propertize "Active Face\n" 'face '(:weight bold))
                (format "Family:  %s\n" (face-attribute 'default :family))
                (format "Height:  %s\n" (face-attribute 'default :height))
                (format "Weight:  %s\n" (face-attribute 'default :weight))
                "\n"
                (propertize "System\n" 'face '(:weight bold))
                (format "HarfBuzz: %s\n"
                        (if (string-match-p "HARFBUZZ" system-configuration-features) "yes" "no"))
                (format "Ligature mode: %s\n" (bound-and-true-p global-ligature-mode))
                (format "Composite:     %s\n" (featurep 'composite))))
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

(map! :leader
      (:prefix ("F" . "fonts")
       :desc "Ligature showcase"  "l" #'+fonts/ligature-showcase
       :desc "Font info"          "i" #'+fonts/font-info
       :desc "Apply Maple features" "a" #'+fonts/apply-maple-features))

(provide '+fonts)
;;; +fonts.el ends here
