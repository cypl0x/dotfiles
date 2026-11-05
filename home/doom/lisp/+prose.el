;;; lisp/+prose.el --- Writing and prose tools -*- lexical-binding: t; -*-
;;
;; jinx spellchecking, mixed-pitch, enhanced text statistics,
;; writing-mode composition, and prose linting.
;;
;;; Code:

;;;; jinx — Fast spellchecker ────────────────────────────────────────────────

;; jinx — fast spellchecker (enchant-2 backend).
;;
;; NixOS problem: jinx compiles jinx-mod.so at runtime.  It calls
;; `pkg-config --cflags --libs enchant-2' but NixOS has `pkgconf' (not
;; `pkg-config') and enchant headers live in a `-dev' store path that
;; isn't on PKG_CONFIG_PATH.  We solve this by finding enchant's dev
;; output and setting PKG_CONFIG_PATH before jinx loads.

(defvar +prose/jinx-ready nil
  "Whether jinx native module is available or was compiled successfully.")

(defun +prose/jinx--setup-nix-env ()
  "Set up environment for jinx-mod.so compilation on NixOS.
Bypasses pkg-config — enchant-2.pc has transitive glib deps that
NixOS can't resolve without full dev closure.  Instead, create a
shim pkg-config script returning direct -I/-L/-l flags."
  (unless (or +prose/jinx-ready
              (locate-library (file-name-with-extension "jinx-mod" module-file-suffix) t))
    (let* ((enchant-h (car (file-expand-wildcards
                            "/nix/store/*-enchant-*-dev/include/enchant-2/enchant.h")))
           (enchant-so (car (file-expand-wildcards
                             "/nix/store/*-enchant-2*/lib/libenchant-2.so"))))
      (when (and enchant-h enchant-so)
        (let* ((inc-dir (file-name-directory (directory-file-name
                                              (file-name-directory enchant-h))))
               (lib-dir (file-name-directory enchant-so))
               (flags (format "-I%senchant-2 -L%s -lenchant-2" inc-dir lib-dir))
               (wrapper-dir (expand-file-name ".local/bin" "~"))
               (wrapper (expand-file-name "pkg-config" wrapper-dir)))
          (make-directory wrapper-dir t)
          (with-temp-file wrapper
            (insert (format "#!/bin/sh\necho '%s'\n" flags)))
          (set-file-modes wrapper #o755)
          ;; Add to both PATH (for shell-command) and exec-path (for process-lines).
          (unless (string-match-p (regexp-quote wrapper-dir) (or (getenv "PATH") ""))
            (setenv "PATH" (concat wrapper-dir ":" (getenv "PATH"))))
          (unless (member wrapper-dir exec-path)
            (push wrapper-dir exec-path)))))))

(use-package! jinx
  :defer t
  :init
  (+prose/jinx--setup-nix-env)
  :config
  (setq jinx-languages "en_US en_GB de_DE")
  (setq +prose/jinx-ready t)
  (custom-set-faces!
    '(jinx-misspelled :underline (:style wave :color "#ff6c6b"))))

;; Safe hook: wrap jinx-mode to swallow compilation failure.
(defun +prose/jinx-mode-safe ()
  "Enable `jinx-mode' only if jinx-mod.so loads successfully."
  (condition-case nil
      (jinx-mode 1)
    (error nil)))

(add-hook 'text-mode-hook #'+prose/jinx-mode-safe)
(add-hook 'org-mode-hook #'+prose/jinx-mode-safe)
(add-hook 'markdown-mode-hook #'+prose/jinx-mode-safe)
;; Code too: jinx checks only comments, strings and docstrings there
;; (`jinx-include-faces').  It replaced Doom's :checkers spell (flyspell),
;; which ran on top of it in text buffers.
(add-hook 'prog-mode-hook #'+prose/jinx-mode-safe)
(global-set-key [remap ispell-word] #'jinx-correct)   ; z=, M-$
(map! :m "]s" #'jinx-next              ; also ä s / ö s
      :m "[s" #'jinx-previous)


;;;; autocorrect — typos you corrected with jinx get fixed as you type ───────

;; tecosaur's package, wired to jinx as in his config but for jinx 2.11:
;; `jinx--word-valid-p' takes the word itself now, and the exclusion tests
;; are jinx's own predicates (faces, regexps, properties) at the word.  A
;; correction becomes automatic after 3 corrections of the same typo over
;; time (2 in one session); M-x autocorrect-list shows and edits them.
(declare-function jinx--face-excluded-p "ext:jinx" (pos))
(declare-function jinx--regexp-excluded-p "ext:jinx" (pos))
(declare-function jinx--property-excluded-p "ext:jinx" (pos))
(declare-function jinx--word-valid-p "ext:jinx" (word))
(declare-function autocorrect-record-correction "ext:autocorrect" (misspelling corrected))

(defun +prose-autocorrect-record-a (overlay corrected)
  "Before jinx replaces OVERLAY with CORRECTED: tell autocorrect."
  (autocorrect-record-correction
   (buffer-substring-no-properties (overlay-start overlay) (overlay-end overlay))
   corrected))

(defun +prose-autocorrect-here-p (pos)
  "Whether jinx would check the word that ends at POS.
Case-sensitive like jinx: its \"[A-Z]+\\\\>\" (all-caps words) matched \"teh\"."
  (let ((pos (max (point-min) (1- pos)))
        (case-fold-search nil))
    (not (or (jinx--face-excluded-p pos)
             (jinx--regexp-excluded-p (save-excursion (goto-char pos) (backward-word) (point)))
             (jinx--property-excluded-p pos)))))

(use-package! autocorrect
  :after jinx
  :config
  (setq autocorrect-check-spelling-function #'jinx--word-valid-p)
  (add-to-list 'autocorrect-predicates #'+prose-autocorrect-here-p)
  (advice-add 'jinx--correct-replace :before #'+prose-autocorrect-record-a)
  (run-with-idle-timer 0.5 nil #'autocorrect-setup))

;; Corrections are abbrevs.  Not in Coq: Proof General defines 328 that
;; would start expanding.  Autocorrect keeps its own file; nothing is
;; written to abbrev_defs.
(setq save-abbrevs nil)
(add-hook! '(text-mode-hook prog-mode-hook)
  (defun +prose-abbrev-mode-h ()
    (unless (derived-mode-p 'coq-mode) (abbrev-mode 1))))


;;;; mixed-pitch — Variable-pitch prose, fixed-pitch code ────────────────────

(use-package! mixed-pitch
  :hook ((org-mode . mixed-pitch-mode)
         (markdown-mode . mixed-pitch-mode))
  :config
  ;; The variable-pitch font is set via doom-variable-pitch-font.
  ;; When Maple Mono NF is used for both, mixed-pitch effectively does nothing
  ;; but the hook is ready for when a proper variable-pitch font is configured.
  ;;
  ;; No fixed height: with one, mixed-pitch remapped `default' in Org and
  ;; Markdown to the size current when the buffer opened (:height 136), so
  ;; C-ä / C-ö / C-ü (doom/increase-font-size …) changed every other text,
  ;; the minibuffer included, but not those buffers.
  (setq mixed-pitch-set-height nil))

;;;; Text Statistics — Enhanced ──────────────────────────────────────────────

(defun +prose/text-stats ()
  "Show comprehensive text statistics for the current buffer or region.
Displays word count, character count, line count, sentence count,
paragraph count, reading time, and writing time in a popup buffer."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg end))
         (words (count-words beg end))
         (chars (- end beg))
         (chars-no-space (with-temp-buffer
                           (insert text)
                           (goto-char (point-min))
                           (let ((n 0))
                             (while (not (eobp))
                               (unless (looking-at-p "\\s-")
                                 (cl-incf n))
                               (forward-char 1))
                             n)))
         (lines (count-lines beg end))
         (sentences (with-temp-buffer
                      (insert text)
                      (goto-char (point-min))
                      (let ((n 0))
                        (while (re-search-forward "[.!?]+\\(?:\\s-\\|$\\)" nil t)
                          (cl-incf n))
                        n)))
         (paragraphs (with-temp-buffer
                       (insert text)
                       (goto-char (point-min))
                       (let ((n 1))
                         (while (re-search-forward "\n\\s-*\n" nil t)
                           (cl-incf n))
                         n)))
         (read-wpm 238)
         (write-wpm 40)
         (speak-wpm 150)
         (read-min (/ (float words) read-wpm))
         (write-min (/ (float words) write-wpm))
         (speak-min (/ (float words) speak-wpm))
         (scope (if (use-region-p) "Region" "Buffer")))
    (message
     (concat
      (propertize (format "%s Statistics" scope) 'face 'bold)
      (format "\n  %d words · %d chars (%d non-space) · %d lines"
              words chars chars-no-space lines)
      (format "\n  %d sentences · %d paragraphs"
              sentences paragraphs)
      (format "\n  ~%.1f min read · ~%.1f min write · ~%.1f min speak"
              read-min write-min speak-min)))))

;;;; Writing mode — composition ──────────────────────────────────────────────

(defvar +prose/writing-mode-enabled nil
  "Whether the writing composition mode is active.")

(define-minor-mode +prose/writing-mode
  "A distraction-free writing composition mode.
Combines visual-line-mode, line spacing, centered text, dimmed modeline,
mixed-pitch, jinx, and org-modern for a focused writing experience."
  :lighter " ✍"
  :global nil
  (if +prose/writing-mode
      (progn
        (setq-local +prose/writing-mode-enabled t)
        ;; Visual
        (visual-line-mode 1)
        (setq-local line-spacing 4)
        (setq-local left-margin-width 8)
        (setq-local right-margin-width 8)
        (set-window-buffer (selected-window) (current-buffer))
        ;; Disable distractions
        (display-line-numbers-mode -1)
        (hl-line-mode -1)
        ;; Enable prose tools
        (when (fboundp 'jinx-mode) (jinx-mode 1))
        (when (fboundp 'mixed-pitch-mode) (mixed-pitch-mode 1))
        (when (fboundp 'org-modern-mode)
          (when (derived-mode-p 'org-mode) (org-modern-mode 1)))
        (message "Writing mode ON"))
    ;; Restore
    (setq-local +prose/writing-mode-enabled nil)
    (visual-line-mode -1)
    (setq-local line-spacing nil)
    (setq-local left-margin-width 0)
    (setq-local right-margin-width 0)
    (set-window-buffer (selected-window) (current-buffer))
    (display-line-numbers-mode 1)
    (hl-line-mode 1)
    (message "Writing mode OFF")))

;;;; Word frequency analysis ─────────────────────────────────────────────────

(defun +prose/word-frequency ()
  "Show word frequency analysis for the current buffer or region."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (downcase (buffer-substring-no-properties beg end)))
         (words (split-string text "[^[:alpha:]]+" t))
         (freq (make-hash-table :test 'equal)))
    (dolist (w words)
      (puthash w (1+ (gethash w freq 0)) freq))
    (let ((sorted (sort (hash-table-keys freq)
                        (lambda (a b) (> (gethash a freq) (gethash b freq)))))
          (buf (get-buffer-create "*Word Frequency*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize "Word Frequency Analysis\n\n"
                              'face '(:height 1.3 :weight bold))
                  (format "Total unique words: %d\n\n" (length sorted))
                  (propertize (format "%-6s  %s\n" "Count" "Word")
                              'face '(:weight bold))
                  (propertize (make-string 40 ?─) 'face 'shadow) "\n")
          (dolist (w (seq-take sorted 100))
            (insert (format "%-6d  %s\n" (gethash w freq) w))))
        (goto-char (point-min))
        (view-mode 1))
      (pop-to-buffer buf))))

;;;; Readability metrics ─────────────────────────────────────────────────────

(defun +prose/readability ()
  "Calculate readability metrics for the current buffer or region.
Shows Flesch Reading Ease, Flesch-Kincaid Grade Level, and Coleman-Liau Index."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg end))
         (words-list (split-string text "[^[:alpha:]]+" t))
         (words (float (length words-list)))
         (sentences (float (max 1 (with-temp-buffer
                                    (insert text)
                                    (goto-char (point-min))
                                    (let ((n 0))
                                      (while (re-search-forward "[.!?]+" nil t)
                                        (cl-incf n))
                                      n)))))
         (syllables (cl-reduce #'+ words-list
                               :key (lambda (w)
                                      (max 1 (length (split-string
                                                       (replace-regexp-in-string
                                                        "[^aeiouy]+" " "
                                                        (downcase w))
                                                       " " t))))))
         (asl (/ words sentences))
         (asw (/ (float syllables) words))
         ;; Flesch Reading Ease
         (fre (- 206.835 (* 1.015 asl) (* 84.6 asw)))
         ;; Flesch-Kincaid Grade Level
         (fkgl (+ (* 0.39 asl) (* 11.8 asw) -15.59))
         ;; Grade description
         (grade (cond ((>= fre 90) "Very Easy (5th grade)")
                      ((>= fre 80) "Easy (6th grade)")
                      ((>= fre 70) "Fairly Easy (7th grade)")
                      ((>= fre 60) "Standard (8-9th grade)")
                      ((>= fre 50) "Fairly Difficult (10-12th)")
                      ((>= fre 30) "Difficult (College)")
                      (t "Very Difficult (Graduate)"))))
    (message
     (format "Readability: FRE %.1f (%s) · FK Grade %.1f · %.0f words · %.0f sentences"
             fre grade fkgl words sentences))))

;;;; Keybindings ─────────────────────────────────────────────────────────────

;;;; leo.el — Fix umlaut/multibyte rendering ─────────────────────────────────

;; `leo--parse-xml' parses the response as raw bytes: `url-retrieve' leaves
;; the body unibyte (text/xml; charset=utf-8), leo.el's FIXME toggles
;; multibyte twice (a no-op), and its cache path never decodes either, so
;; "hören" shows as "h\303\266ren". It's an `aio-defun', so an :around
;; advice with `cl-letf' doesn't help: the body runs after `aio-await',
;; when the binding is long gone. Replace it with one that decodes.
(after! leo
  (aio-defun +prose--leo-parse-xml-a (url)
    "Parse the XML retrieved from URL, decoded as UTF-8."
    (let ((url-user-agent leo-user-agent))
      (if (url-is-cached url)
          (with-current-buffer (url-fetch-from-cache url)
            (set-buffer-multibyte nil)
            (let ((start (goto-char (re-search-forward "\n\n"))))
              (zlib-decompress-region start (point-max))
              (+prose--leo-decode start)))
        (let ((response (aio-await (aio-url-retrieve url))))
          (with-current-buffer (cdr response)
            (goto-char (point-min))
            (+prose--leo-decode (search-forward "\n\n")))))))

  (defun +prose--leo-decode (start)
    "Decode the unibyte UTF-8 body from START to the end, then parse it."
    (set-buffer-multibyte t)
    (decode-coding-region start (point-max) 'utf-8)
    (xml-parse-region start (point-max)))

  (advice-add #'leo--parse-xml :override #'+prose--leo-parse-xml-a))

;;;; org-reading-mode — Distraction-free reading ─────────────────────────────

(define-minor-mode +prose/reading-mode
  "Hide inline diagnostics, spelling, and lint overlays for distraction-free reading.
Disables flycheck, flymake, flyspell, jinx, eglot inlay hints, and sideline;
off turns jinx back on."
  :lighter " 📖"
  :global nil
  (if +prose/reading-mode
      (progn
        (when (bound-and-true-p flycheck-mode) (flycheck-mode -1))
        (when (bound-and-true-p flymake-mode) (flymake-mode -1))
        (when (bound-and-true-p flyspell-mode) (flyspell-mode -1))
        (when (bound-and-true-p jinx-mode) (jinx-mode -1))
        (when (bound-and-true-p sideline-mode) (sideline-mode -1))
        (when (bound-and-true-p eglot--managed-mode)
          (eglot-inlay-hints-mode -1))
        (when (bound-and-true-p display-line-numbers-mode)
          (display-line-numbers-mode -1))
        (message "Reading mode ON — diagnostics hidden"))
    (when (bound-and-true-p flycheck-mode) (flycheck-mode 1))
    (when (derived-mode-p 'prog-mode) (flymake-mode 1))
    (when (derived-mode-p 'text-mode 'prog-mode) (+prose/jinx-mode-safe))
    (display-line-numbers-mode 1)
    (message "Reading mode OFF")))

;;;; Keybindings ─────────────────────────────────────────────────────────────

;;;; Spell correction at point — RET and mouse click ─────────────────────────

;; Make RET on misspelled word trigger correction (jinx or flyspell).
(defun +prose/correct-at-point ()
  "Correct spelling at point using jinx (preferred) or flyspell."
  (interactive)
  (cond
   ((and (bound-and-true-p jinx-mode)
         (jinx--get-overlays (point) (1+ (point))))
    (jinx-correct))
   ((and (bound-and-true-p flyspell-mode)
         (flyspell-overlay-p (car (overlays-at (point)))))
    (flyspell-correct-at-point))
   (t (message "No misspelling at point"))))

;; Mouse click on misspelled word → correct
(defun +prose/mouse-correct (event)
  "Correct spelling at mouse click position."
  (interactive "e")
  (mouse-set-point event)
  (+prose/correct-at-point))

;; Bind RET in normal mode on jinx overlays
(after! jinx
  (define-key jinx-overlay-map (kbd "RET") #'+prose/correct-at-point)
  (define-key jinx-overlay-map [mouse-1] #'+prose/mouse-correct))

;; Bind for flyspell too
(after! flyspell
  (define-key flyspell-mouse-map [mouse-1] #'+prose/mouse-correct)
  (define-key flyspell-mouse-map (kbd "RET") #'+prose/correct-at-point))

;;;; Review — the text as a writing assistant sees it ─────────────────────────

;; SPC P v is well-formed's report (lisp/well-formed/): scores per category,
;; readability, tone, sentence plots, findings by rule, and jinx's
;; misspellings.  It replaced a review built on LanguageTool (ltex-ls-plus
;; through eglot: 2.8 GB of Java per project, 30 s to start, and capture
;; buffers waiting on it).

(defalias '+prose/review #'well-formed-report)

;;;; Improve — a sentence rewritten, the change shown word by word ────────────

;; SPC P i: the region, or the sentence at point, rewritten toward a goal
;; you pick (grammar only, clearer, shorter, ...) by familiar's smart tier.
;; The proposal shows before and after with the changed words marked (smerge's
;; word refinement); C-c C-c applies it as one undoable change, g asks again,
;; q keeps yours.  The language stays (German stays German), and so do the
;; meaning, voice and Org/Markdown markup.

(declare-function familiar-request "familiar" (prompt &rest args))
(declare-function smerge-refine-regions "smerge-mode" (beg1 end1 beg2 end2 props-c &optional preproc props-r props-a))

(defconst +prose-improve-goals
  '("fix grammar and spelling only"
    "make it clearer"
    "make it shorter"
    "make it more formal"
    "make it friendlier"
    "use simpler words")
  "Goals offered by `+prose/improve' (any other text works too).")

(defconst +prose--improve-system
  "You edit prose. Rewrite the given text toward the goal. Keep its language \
(German stays German), its meaning, its voice, and any Org or Markdown markup \
and links. Change only what the goal asks for. Reply with only the rewritten \
text: no quotes, no explanation.")

(defvar-local +prose--improve nil "(BUFFER BEG END GOAL ORIGINAL PROPOSAL) shown here.")

(defun +prose--improve-bounds ()
  (if (use-region-p)
      (cons (region-beginning) (region-end))
    (save-excursion
      (let ((end (progn (forward-sentence) (point)))
            (beg (progn (backward-sentence) (point))))
        (cons beg end)))))

(defun +prose--improve-show (state)
  "Show STATE's original and proposal, the changes marked."
  (with-current-buffer (get-buffer-create "*prose improve*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (remove-overlays)
      (pcase-let ((`(,_buf ,_beg ,_end ,goal ,original ,proposal) state))
        (insert (propertize (format "Goal: %s\n\n" goal) 'face 'bold)
                (propertize "Before\n" 'face 'font-lock-comment-face))
        (let ((b1 (point)))
          (insert original)
          (let ((e1 (point)))
            (insert "\n\n" (propertize "After\n" 'face 'font-lock-comment-face))
            (let ((b2 (point)))
              (insert proposal)
              (smerge-refine-regions b1 e1 b2 (point) nil nil
                                     '((face . smerge-refined-removed))
                                     '((face . smerge-refined-added))))))
        (insert (substitute-command-keys
                 "\n\n\\<+prose-improve-mode-map>\\[+prose-improve-apply] apply · \\[+prose-improve-again] try again · \\[quit-window] keep yours\n"))))
    (+prose-improve-mode)                ; (it resets buffer-local variables)
    (setq +prose--improve state)
    (goto-char (point-min))
    (display-buffer (current-buffer))))

(defun +prose--improve-ask (buf beg end goal)
  (let ((original (with-current-buffer buf (buffer-substring-no-properties beg end))))
    (message "Rewriting (%s)…" goal)
    (familiar-request
     (format "Goal: %s\n\nText:\n%s" goal original)
     :task 'fix :system +prose--improve-system
     :callback
     (lambda (response _info)
       (when (stringp response)
         (+prose--improve-show
          (list buf beg end goal original (string-trim response))))))))

;;;###autoload
(defun +prose/improve (goal)
  "Rewrite the region or the sentence at point toward GOAL; show the change."
  (interactive (list (completing-read "Improve: " +prose-improve-goals nil nil nil nil
                                      (car +prose-improve-goals))))
  (pcase-let ((`(,beg . ,end) (+prose--improve-bounds)))
    (deactivate-mark)
    (+prose--improve-ask (current-buffer) (copy-marker beg) (copy-marker end t) goal)))

(defun +prose-improve-apply ()
  "Put the proposal in place of the original (one undo takes it back)."
  (interactive)
  (pcase-let ((`(,buf ,beg ,end ,_goal ,original ,proposal) +prose--improve))
    (with-current-buffer buf
      (unless (equal (buffer-substring-no-properties beg end) original)
        (user-error "The text changed meanwhile; ask again (g)"))
      (save-excursion
        (goto-char beg)
        (delete-region beg end)
        (insert proposal)))
    (quit-window t)
    (message "Applied (undo takes it back)")))

(defun +prose-improve-again ()
  "Ask for another proposal."
  (interactive)
  (pcase-let ((`(,buf ,beg ,end ,goal . ,_) +prose--improve))
    (+prose--improve-ask buf beg end goal)))

(defvar +prose-improve-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'+prose-improve-apply)
    (define-key map "g" #'+prose-improve-again)
    (define-key map "q" #'quit-window)
    map))

(define-derived-mode +prose-improve-mode special-mode "Improve"
  "A rewrite proposal: C-c C-c applies it, g asks again, q keeps yours.")

(map! :leader
      (:prefix ("P" . "prose")
       :desc "Writing mode"      "w" #'+prose/writing-mode
       :desc "Reading mode"      "r" #'+prose/reading-mode
       :desc "Text stats"        "s" #'+prose/text-stats
       :desc "Word frequency"    "f" #'+prose/word-frequency
       :desc "Readability"       "R" #'+prose/readability
       :desc "Review the text"   "v" #'+prose/review
       :desc "Improve sentence"  "i" #'+prose/improve
       :desc "Jinx correct"      "j" #'jinx-correct
       :desc "Jinx correct all"  "J" #'jinx-correct-all
       :desc "Leo translate"     "l" #'leo-translate-word))

(provide '+prose)
;;; +prose.el ends here
