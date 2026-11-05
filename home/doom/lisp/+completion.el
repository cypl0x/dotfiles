;;; lisp/+completion.el --- C-SPC completes for where you are -*- lexical-binding: t; -*-
;;
;; C-SPC in insert state (it fell through to `set-mark-command') completes
;; with sources picked by context, shown by corfu as usual:
;;
;;   Org link after [[        org-roam nodes, then files
;;   Org #+keyword, :tags:    Org's own (pcomplete): keywords, tags, properties
;;   Org src block            the block's code (cape-elisp-block for elisp)
;;   prose: Org/Markdown/text, comments, strings
;;                            dictionary (English + German) and buffer words
;;   code                     the mode's own (eglot, elisp), buffer words, files
;;
;; The dictionaries are plain word lists built from the hunspell ones jinx
;; uses (home/emacs-deps.nix); `cape-dict-file' pointed at
;; /usr/share/dict/words, which NixOS doesn't have.
;;
;;; Code:

(declare-function cape-dict "ext:cape" (&optional interactive))
(declare-function cape-dabbrev "ext:cape" (&optional interactive))
(declare-function cape-file "ext:cape" (&optional interactive))
(declare-function cape-elisp-block "ext:cape" (&optional interactive))
(declare-function cape-capf-super "ext:cape" (&rest capfs))
(declare-function org-in-src-block-p "org" (&optional inside element))
(declare-function +org-slash-empty-capf "+org-slash" ())
(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(declare-function org-roam-complete-link-at-point "ext:org-roam-mode" ())
(declare-function pcomplete-completions-at-point "pcomplete" ())
(require 'map)
(declare-function doom-color "ext:doom-themes" (name &optional type))
(declare-function doom-blend "ext:doom-themes" (color1 color2 alpha))
(defvar cape-dict-file)
(defvar cape-dabbrev-buffer-function)
(declare-function cape--dabbrev-list "ext:cape" (input))
(declare-function cape--dict-list "ext:cape" (input))

(defvar +completion-dict-files
  (seq-filter #'file-exists-p
              (mapcan (lambda (dir)
                        (list (expand-file-name "words-en" dir)
                              (expand-file-name "words-en-gb" dir)
                              (expand-file-name "words-de" dir)))
                      (list (expand-file-name "dict" (or (getenv "XDG_DATA_HOME") "~/.local/share")))))
  "Word lists for `cape-dict' (home/emacs-deps.nix: dict-words).")

(with-eval-after-load 'cape
  (when +completion-dict-files
    (setq cape-dict-file +completion-dict-files)))

(defun +completion--word-buffers ()
  "Buffers whose words prose completion offers.
From the minibuffer, the buffers on screen: the M-ß prompt asks about them."
  (if (minibufferp)
      (delete-dups (mapcar #'window-buffer
                           (window-list (window-frame (minibuffer-selected-window)) 'nomini)))
    (ensure-list (funcall cape-dabbrev-buffer-function))))

(defun +completion--words (input)
  "Words starting with INPUT: from buffers first, then the dictionaries.
One list without duplicates (`cape-capf-super' keeps a word once per source).
The word lists are cape's own, not autoloaded: cape is loaded first (after a
restart nothing had, and M-ß's prompt failed: void cape--dabbrev-list)."
  (require 'cape)
  (let ((buffers (+completion--word-buffers))
        (case-fold-search nil))
    (seq-filter
     ;; Prose words only: dabbrev also brings code tokens (Work*, WordMap).
     (lambda (w) (string-match-p "\\`[[:alpha:]]\\(?:[[:lower:]'-]*\\|[[:upper:]]*\\)\\'" w))
     (delete-dups
      (append (cdr (dlet ((cape-dabbrev-buffer-function (lambda () buffers)))
                     (cape--dabbrev-list input)))
              (cdr (cape--dict-list input)))))))

(defun +completion-prose-capf ()
  "Complete words in prose (Org/Markdown/text, comments, strings, prompts).
Recomputed as the input grows, so a longer prefix still finds words past
the dictionaries' first `cape-dict-limit' matches.  The words are looked up
for the text typed, not the string the completion style asks with:
orderless asks with \"\", and dabbrev took 30 s collecting every word of
every Org buffer (11,448 of them, duplicate check quadratic)."
  (when (or (minibufferp) (eq (+completion-context) 'prose))
    (when-let* ((bounds (bounds-of-thing-at-point 'word))
                ((<= (+ (car bounds) 2) (point))))
      (let ((beg (copy-marker (car bounds))) input words)
        (list beg (point)
              (lambda (string pred action)
                (let ((typed (with-current-buffer (marker-buffer beg)
                               (buffer-substring-no-properties beg (max beg (point))))))
                  (unless (equal typed input)
                    (setq input typed
                          words (and (length> typed 1) (+completion--words typed))))
                  (complete-with-action action words string pred)))
              :exclusive 'no
              :company-kind (lambda (_) 'text))))))

(defvar +completion-next-word-limit 400000
  "Characters of text (this buffer first, then others of its mode) read
for `+completion-next-word-capf'.")

(defun +completion--next-words (prev)
  "Words that followed PREV in this buffer and others of its mode, as
\(WORD . COUNT), most frequent first."
  (let ((counts (make-hash-table :test #'equal))
        (re (concat "\\_<" (regexp-quote prev) "[[:space:]]+\\([[:alpha:]][[:alpha:]'’-]+\\)"))
        (budget +completion-next-word-limit)
        (mode major-mode)
        (case-fold-search t))
    (dolist (buf (cons (current-buffer) (remq (current-buffer) (buffer-list))))
      (when (and (> budget 0) (eq (buffer-local-value 'major-mode buf) mode))
        (with-current-buffer buf
          (save-excursion
            (save-restriction
              (widen)
              (goto-char (point-min))
              (let ((limit (min (point-max) (+ (point-min) budget))))
                (while (re-search-forward re limit t)
                  (cl-incf (gethash (downcase (match-string-no-properties 1)) counts 0)))
                (setq budget (- budget (- limit (point-min))))))))))
    (let (out)
      (maphash (lambda (w n) (push (cons w n) out)) counts)
      (sort out (lambda (a b) (> (cdr a) (cdr b)))))))

(defun +completion-next-word-capf ()
  "With nothing typed yet: the words that followed the previous word
elsewhere (in this buffer and the others of its mode), most frequent
first, each with its count.  C-SPC after a space offered nothing before."
  (when (and (or (minibufferp) (eq (+completion-context) 'prose))
             (not (looking-back "[[:alpha:]]" (1- (point)))))
    (let* ((prev (save-excursion
                   (skip-chars-backward " \t")
                   (and (looking-back "\\b\\([[:alpha:]][[:alpha:]'’-]*\\)" (line-beginning-position))
                        (match-string-no-properties 1))))
           (found (and prev (+completion--next-words prev)))
           (cands (mapcar (lambda (e) (propertize (car e) '+count (cdr e))) found)))
      (when cands
        (list (point) (point)
              (lambda (string pred action)
                (if (eq action 'metadata)
                    '(metadata (display-sort-function . identity) (cycle-sort-function . identity))
                  (complete-with-action action cands string pred)))
              :annotation-function
              (lambda (c) (format "  after “%s” ×%d" prev (or (cdr (assoc (substring-no-properties c) found)) 0)))
              :exclusive 'no
              :company-kind (lambda (_) 'text))))))

(defun +completion-path-capf ()
  "Complete a file or directory name before point, recognized by its
shape (~/…, /…, ./…, ../…, file:…) after a space or an Org/Markdown
markup character: in =verbatim=, ~code~, links, prose and prompts alike.
\"~/dotfiles/ho\" had looked like the start of ~code~ and got Lisp names;
an unclosed \"=~/va\" like prose and got words."
  (let ((start (save-excursion
                 (skip-chars-backward "^ \t\n=~[(\"'`<" (line-beginning-position))
                 ;; "~/x": the ~ belongs to the path, not to markup.
                 (when (and (eq (char-before) ?~) (eq (char-after) ?/)) (backward-char))
                 (point))))
    (when (let ((pt (point)))
            (save-excursion
              (goto-char start)
              (and (looking-at "\\(?:file:\\)?\\(?:~\\|\\.\\.?\\)?/[^ \t\n]*")
                   (= (match-end 0) pt))))
      (let ((beg (if (save-excursion (goto-char start) (looking-at "file:")) (+ start 5) start)))
        (list beg (point) #'read-file-name-internal
              :exclusive 'no
              :annotation-function (lambda (c) (if (string-suffix-p "/" c) "  dir" ""))
              :company-kind (lambda (c) (if (string-suffix-p "/" c) 'folder 'file)))))))

(defun +completion--prose ()
  (list #'+completion-prose-capf #'+completion-next-word-capf))

;; corfu completes as you type, but in Org nothing offered words: Org's
;; capfs are keywords, tags and src blocks only.
(add-hook 'text-mode-hook
          (defun +completion-prose-h ()
            (add-hook 'completion-at-point-functions #'+completion-prose-capf 90 t)
            (add-hook 'completion-at-point-functions #'+completion-code-capf 80 t)))

;; Inline code in prose, Org ~code~ / =verbatim= or Markdown `code`, is
;; mostly Emacs Lisp names here: complete those, commands first.
(defvar cape--elisp-symbol-properties)

(defun +completion--inline-code-start ()
  "Where the inline code being typed at point starts (after its opener), or nil.
Org: ~ or = after a space or line start, followed by text, not closed yet
\(\"~ 5 min\", \"x = 1\" are prose).  Markdown: after an odd number of
backticks on the line."
  (cond ((derived-mode-p 'org-mode)
         (save-excursion
           (when (re-search-backward "\\(?:^\\|[[:space:]({\"']\\)\\([~=]\\)[^~=\n[:space:]][^~=\n]*\\="
                                     (line-beginning-position) t)
             (match-end 1))))
        ((derived-mode-p 'markdown-mode)
         (when (cl-oddp (how-many "`" (line-beginning-position) (point)))
           (save-excursion (search-backward "`" (line-beginning-position)) (1+ (point)))))))

(defun +completion--code-sort (cands)
  "Commands first, then other functions, then the rest; shorter first."
  (let ((rank (lambda (c) (let ((s (intern-soft c)))
                            (cond ((commandp s) 0) ((fboundp s) 1) (t 2))))))
    (sort cands (lambda (a b)
                  (let ((ra (funcall rank a)) (rb (funcall rank b)))
                    (if (= ra rb) (< (length a) (length b)) (< ra rb)))))))

(defun +completion-code-capf ()
  "Complete Emacs Lisp names in Org/Markdown inline code; close it on exit."
  (when-let* ((start (+completion--inline-code-start)))
    (require 'cape)
    (let ((closer (char-before start))
          (chars "[:alnum:]-_/*+<>!?:"))
      `(,(save-excursion (skip-chars-backward chars start) (point))
        ,(save-excursion (skip-chars-forward chars) (point))
        ,obarray
        :exit-function
        ,(lambda (_sym status)
           (unless (or (eq status 'exact) (eq (char-after) closer))
             (insert closer)))
        :display-sort-function +completion--code-sort
        ,@(cl-loop for (k v) on cape--elisp-symbol-properties by #'cddr
                   unless (memq k '(:exit-function :exclusive)) nconc (list k v))
        :exclusive no))))

(defun +completion-context ()
  "What point is in, for choosing completion sources: a symbol."
  (cond ((derived-mode-p 'org-mode)
         (cond ((looking-back "\\[\\[[^]\n]*" (line-beginning-position)) 'org-link)
               ;; Nothing typed: what fits here (lisp/+org-slash.el).
               ((and (or (bolp) (memq (char-before) '(?\s ?\t)))
                     (not (org-in-src-block-p t)))
                'org-empty)
               ((looking-back "^[ \t]*#\\+[[:alnum:]_]*" (line-beginning-position)) 'org-keyword)
               ((and (org-at-heading-p)
                     (looking-back ":[[:alnum:]_@#%:]*" (line-beginning-position)))
                'org-tag)
               ((org-in-src-block-p t) 'org-src)
               ((+completion--inline-code-start) 'inline-code)
               (t 'prose)))
        ((and (derived-mode-p 'markdown-mode) (+completion--inline-code-start)) 'inline-code)
        ((derived-mode-p 'text-mode) 'prose)
        ((nth 8 (syntax-ppss)) 'prose)          ; in a comment or string
        (t 'code)))

(defun +completion-capfs (&optional context)
  "Completion functions for CONTEXT (default: `+completion-context'),
after the path completion, which recognizes a path wherever it is."
  (cons #'+completion-path-capf (+completion--capfs-for context)))

(defun +completion--capfs-for (context)
  (pcase (or context (+completion-context))
    ('org-link (delq nil (list (and (fboundp 'org-roam-complete-link-at-point)
                                    #'org-roam-complete-link-at-point)
                               #'cape-file)))
    ('org-empty (list #'+org-slash-empty-capf))
    ((or 'org-keyword 'org-tag) (list #'pcomplete-completions-at-point))
    ('org-src (list #'cape-elisp-block #'cape-dabbrev))
    ('inline-code (list #'+completion-code-capf))
    ('prose (+completion--prose))
    (_ (append (remq t completion-at-point-functions)
               (list #'cape-dabbrev #'cape-file)))))

;;;###autoload
(defun +completion/dwim ()
  "Complete at point with sources for where point is."
  (interactive)
  (require 'cape)
  (let ((completion-at-point-functions (+completion-capfs)))
    (completion-at-point)))

;; Doom's corfu module binds C-SPC to plain `completion-at-point' in
;; corfu-mode-map's insert state, which wins over a global binding.
(defun +completion/dwim-from-normal ()
  "From normal state: insert state at point, then complete what fits there."
  (interactive)
  (when (fboundp 'evil-insert-state) (evil-insert-state))
  (+completion/dwim))

;; In normal state C-SPC was `set-mark-command': nothing showed, and it
;; looked as if completion did nothing (evil selects with visual state).
(map! :i "C-SPC" #'+completion/dwim
      :n "C-SPC" #'+completion/dwim-from-normal
      :after corfu :map corfu-mode-map :i "C-SPC" #'+completion/dwim)

;; Typing in the minibuffer (M-x, M-ß, find-file) is insert-like: the same
;; bar cursor as evil's insert state, not the frame's box (evil isn't
;; active there, `evil-want-minibuffer' is nil).
(add-hook 'minibuffer-setup-hook
          (defun +minibuffer-bar-cursor-h ()
            (setq-local cursor-type 'bar)))

;; The selected candidate in corfu's popup was the editor background, one
;; shade off the popup's own (#242730 on #2a2e38): barely visible.  Now the
;; theme's blue, 30% into the background, and bold; the text stays at WCAG AA
;; contrast (4.8:1 with doom-vibrant).
;;
;; The popup itself was bg-alt (#2a2e38), the background solaire gives every
;; buffer that isn't a file, so there it melted into the text; then a grey
;; shade with a blue-grey border, which looked grey and boxed.  Now: a
;; surface of its own, the theme's blue 10% into the background (distinct
;; from both editor backgrounds, text at AAA contrast), no border line (its
;; width is 4 px of padding in the popup's color), roomier margins, the
;; selection in blue, a blue scroll bar, quiet annotations; the
;; documentation window the same.  Colors follow the theme.
(defvar corfu-border-width) (defvar corfu-left-margin-width) (defvar corfu-right-margin-width)
(defvar corfu-bar-width) (defvar corfu-min-width) (defvar corfu-max-width) (defvar corfu-count)
(setq corfu-border-width 4
      corfu-left-margin-width 1.0
      corfu-right-margin-width 1.0
      corfu-bar-width 0.35
      corfu-min-width 24
      corfu-max-width 90
      corfu-count 12)

;; Colors from doom-color only under a doom theme (lisp/+themes.el): after
;; doom-modus-vibrant, modus-operandi's popup came out its dark navy.
(declare-function +themes-doom-p "+themes" ())
(declare-function +themes-tint "+themes" (color bg fg alpha &optional ratio))
(defmacro +completion--doom (&rest attrs)
  "ATTRS (a plist) while a doom theme is on, else nothing."
  `(and (+themes-doom-p) (list ,@attrs)))
(custom-set-faces!
  `(corfu-default ,@(+completion--doom :background (doom-blend 'blue 'bg 0.10) :foreground (doom-color 'fg)))
  `(corfu-border ,@(+completion--doom :background (doom-blend 'blue 'bg 0.10)))
  ;; As much blue as keeps the text at 4.5:1 (32% left 4.3:1 in a dark theme).
  `(corfu-current ,@(+completion--doom :background (+themes-tint (doom-color 'blue) (doom-color 'bg) (doom-color 'fg) 0.32)
                                       :foreground (doom-color 'fg))
                  :weight bold :extend t)
  `(corfu-bar ,@(+completion--doom :background (doom-color 'blue)))
  `(corfu-annotations ,@(+completion--doom :foreground (doom-color 'base7)) :slant italic)
  `(corfu-deprecated :strike-through t ,@(+completion--doom :foreground (doom-color 'base6)))
  `(corfu-popupinfo :inherit corfu-default))

;; The theme gives orderless's match faces a background, so in the selected
;; row the matched part kept the popup's color while the rest turned blue.
;; They keep their colors (foreground) and lose the background, after each
;; theme load (a `custom-set-faces!' spec would replace the theme's).
(defun +completion-match-faces-h ()
  (dolist (face '(orderless-match-face-0 orderless-match-face-1
                  orderless-match-face-2 orderless-match-face-3))
    (when (facep face) (set-face-attribute face nil :background 'unspecified))))
(add-hook 'doom-load-theme-hook #'+completion-match-faces-h)
(with-eval-after-load 'orderless (+completion-match-faces-h))

;; SPC ': reopen the last minibuffer with what was in it.  `vertico-repeat'
;; did that for completion sessions only; M-ß's prompt (a plain
;; read-string) and other prompts were gone after C-g.  In a minibuffer,
;; C-' goes on to the one closed before it and C-" back, the way
;; `+popup/other' cycles through popups.
(defvar +minibuffer-ring-size 30
  "How many closed minibuffers `+minibuffer/resume' can go back through.")

(defvar +minibuffer--ring nil
  "Minibuffers closed, newest first: plists (:command CMD :input TEXT :session S).
S is the `vertico-repeat' session of a completion session (candidate too).")

(defvar-local +minibuffer--index nil
  "Where in `+minibuffer--ring' the minibuffer reopened from; nil if new.")

(defvar +minibuffer--leaving nil
  "Non-nil while C-' / C-\" swap minibuffers: the one left isn't remembered.")

(defvar vertico-repeat-history)
(declare-function vertico-repeat--run "ext:vertico-repeat" (session))

(defun +minibuffer--entry ()
  "The minibuffer being closed, as a `+minibuffer--ring' entry, or nil."
  (let ((cmd current-minibuffer-command))
    (when (and (symbolp cmd) (commandp cmd)
               (not (memq cmd '(+minibuffer/resume vertico-repeat vertico-repeat-last
                                vertico-repeat-previous vertico-repeat-select))))
      ;; vertico-repeat saved its session first (a local exit hook).
      (let ((session (car-safe (bound-and-true-p vertico-repeat-history))))
        (list :command cmd
              :input (minibuffer-contents-no-properties)
              :session (and (bound-and-true-p vertico--input)
                            (eq (car-safe session) cmd)
                            session))))))

(defvar +minibuffer--closed-at nil
  "When a minibuffer was last remembered (`float-time'), for `+resume/last'.")

(defun +minibuffer--remember (entry)
  "Put ENTRY first in `+minibuffer--ring', once."
  (when entry
    (setq +minibuffer--closed-at (float-time))
    (setq +minibuffer--ring
          (seq-take (cons entry
                          (seq-remove (lambda (e)
                                        (and (eq (plist-get e :command) (plist-get entry :command))
                                             (equal (plist-get e :input) (plist-get entry :input))))
                                      +minibuffer--ring))
                    +minibuffer-ring-size))))

(defun +minibuffer-remember-h ()
  "Remember the minibuffer being closed, for `+minibuffer/resume'."
  (unless +minibuffer--leaving
    (+minibuffer--remember (+minibuffer--entry))))
(add-hook 'minibuffer-exit-hook #'+minibuffer-remember-h)

(defun +minibuffer--open (index)
  "Reopen entry INDEX of `+minibuffer--ring' with its input.
Completion sessions through `vertico-repeat' (candidate position too);
others (M-ß's prompt, plain prompts) by running their command again with
the input put back."
  (setq +minibuffer--leaving nil)
  (pcase-let (((map :command :input :session) (nth index +minibuffer--ring))
              (inhibit-quit nil))       ; from a timer: C-g must still quit
    (minibuffer-with-setup-hook
        (lambda ()
          (setq +minibuffer--index index)
          (unless session (delete-minibuffer-contents) (insert input)))
      (setq this-command command)
      (if (and session (or (fboundp 'vertico-repeat--run) (require 'vertico-repeat nil t)))
          (vertico-repeat--run session)
        (call-interactively command)))))

(defun +minibuffer/resume ()
  "Reopen the last minibuffer with its input.
In it, \\`C-'' goes back to the one before, \\`C-\"' forward again."
  (interactive)
  (unless +minibuffer--ring (user-error "No minibuffer to reopen yet"))
  (+minibuffer--open 0))

(defun +minibuffer--swap-index (step)
  "The ring position STEP away from the current minibuffer, or nil.
A minibuffer not reopened is remembered first, so it can be come back to;
a reopened one keeps its edits."
  (let* ((entry (+minibuffer--entry))
         (base (cond (+minibuffer--index
                      (when entry (setf (nth +minibuffer--index +minibuffer--ring) entry))
                      +minibuffer--index)
                     (entry (+minibuffer--remember entry) 0)
                     (t -1)))
         (next (+ base step)))
    (and (<= 0 next) (< next (length +minibuffer--ring)) next)))

(defun +minibuffer--swap (step)
  (let ((next (or (+minibuffer--swap-index step)
                  (user-error "No %s minibuffer" (if (> step 0) "older" "newer")))))
    (setq +minibuffer--leaving t)
    (run-at-time 0 nil #'+minibuffer--open next)
    (abort-recursive-edit)))

(defun +minibuffer/older ()
  "Swap this minibuffer for the one closed before it (`+minibuffer/resume')."
  (interactive)
  (+minibuffer--swap 1))

(defun +minibuffer/newer ()
  "Swap this minibuffer for the one closed after it."
  (interactive)
  (+minibuffer--swap -1))

(map!
      :map minibuffer-local-map
      "C-'" #'+minibuffer/older
      "C-\"" #'+minibuffer/newer)


;;;; Files: newest first, and live (SPC f f)
;;
;; SPC f f seemed to show "cached" files: a new screenshot wasn't there.  It
;; was, but sorted by history, length and name it sat somewhere among the
;; old ones, and a file made while the prompt is open never appeared
;; (vertico recomputes when the input changes).  In file prompts now:
;; directories first, then newest first; and the directory being completed
;; is watched, so new files show up at the top as they come.  C-c C-r
;; reads it again by hand.  Remote and handled directories (TRAMP, /github)
;; keep the default order: a time per file would be a round trip each.

(defvar +completion-files-newest-max 2000
  "Directories with more entries keep the default order (a stat each).")

(defvar-local +completion--mtimes nil "This prompt's file → time cache.")
(defvar-local +completion--watch nil "(DIRECTORY . WATCH) for this prompt.")
(defvar vertico--input)
(declare-function vertico--exhibit "ext:vertico" ())
(declare-function vertico-sort-history-length-alpha "ext:vertico" (list))
(declare-function file-notify-add-watch "filenotify" (file flags callback))
(declare-function file-notify-rm-watch "filenotify" (descriptor))

(defun +completion--file-dir ()
  "The local directory this file prompt completes in, or nil."
  (when minibuffer-completing-file-name
    (let ((dir (file-name-directory
                (expand-file-name (substitute-in-file-name (minibuffer-contents-no-properties))))))
      (and dir (not (file-remote-p dir))
           (not (find-file-name-handler dir 'file-attributes))
           (file-directory-p dir)
           dir))))

(defvar +completion-directory-first nil
  "Non-nil: the directory itself (./) first, for prompts where a directory
is a valid answer (Org's file links: RET on ~/vault/ took its newest file).")

(defun +completion--directory-first-a (fn &rest args)
  "Around `org-link-complete-file' (FN, ARGS): the directory first; a
directory taken as ./ (~/Pictures/./) without its /./."
  (let* ((+completion-directory-first t)
         (link (apply fn args)))
    (if (stringp link) (replace-regexp-in-string "\\([^:]\\)/\\./\\'" "\\1/" link) link)))

(with-eval-after-load 'ol
  (advice-add 'org-link-complete-file :around #'+completion--directory-first-a))

(defun +completion-sort-files-newest (files)
  "FILES (a file prompt's candidates): directories first, newest first."
  (let ((dir (+completion--file-dir)))
    (if (or (null dir) (> (length files) +completion-files-newest-max))
        (vertico-sort-history-length-alpha files)
      (let* ((cache (or +completion--mtimes (setq +completion--mtimes (make-hash-table :test #'equal))))
             (time (lambda (f)
                     (let ((path (expand-file-name f dir)))
                       (or (gethash path cache)
                           (puthash path (float-time (or (file-attribute-modification-time
                                                          (file-attributes path))
                                                         0))
                                    cache)))))
             (dot (lambda (f) (member f '("./" "../")))))
        (sort (copy-sequence files)
              (lambda (a b)
                (cond ((and +completion-directory-first (equal a "./")) t)
                      ((and +completion-directory-first (equal b "./")) nil)
                      ((funcall dot a) nil) ((funcall dot b) t)
                      ((and (string-suffix-p "/" a) (not (string-suffix-p "/" b))) t)
                      ((and (string-suffix-p "/" b) (not (string-suffix-p "/" a))) nil)
                      (t (> (funcall time a) (funcall time b))))))))))

(defun +completion/refresh-files ()
  "Read the directory of this file prompt again."
  (interactive)
  (setq +completion--mtimes nil)
  (when (boundp 'vertico--input)
    (setq vertico--input t)
    (vertico--exhibit)))

(defun +completion--watch-h ()
  "In a file prompt: watch the directory being completed, refresh on change."
  (let ((dir (+completion--file-dir)))
    (unless (equal dir (car +completion--watch))
      (when (cdr +completion--watch) (ignore-errors (file-notify-rm-watch (cdr +completion--watch))))
      (setq +completion--watch
            (cons dir
                  (and dir
                       (let ((buf (current-buffer)) timer)
                         (ignore-errors
                           (file-notify-add-watch
                            dir '(change)
                            (lambda (_event)
                              ;; A burst of changes (a download): one refresh.
                              (when timer (cancel-timer timer))
                              (setq timer
                                    (run-at-time 0.2 nil
                                                 (lambda ()
                                                   (when (buffer-live-p buf)
                                                     (with-current-buffer buf
                                                       (+completion/refresh-files))))))))))))))))

(defun +completion--unwatch-h ()
  (when (cdr +completion--watch) (ignore-errors (file-notify-rm-watch (cdr +completion--watch))))
  (setq +completion--watch nil))

(add-hook 'minibuffer-setup-hook
          (defun +completion-files-setup-h ()
            (when minibuffer-completing-file-name
              (add-hook 'post-command-hook #'+completion--watch-h nil t)
              (add-hook 'minibuffer-exit-hook #'+completion--unwatch-h nil t)
              (+completion--watch-h))))

(with-eval-after-load 'vertico-multiform
  (defvar vertico-multiform-categories)
  (setf (alist-get 'file vertico-multiform-categories)
        (cons '(vertico-sort-function . +completion-sort-files-newest)
              (assq-delete-all 'vertico-sort-function
                               (copy-sequence (alist-get 'file vertico-multiform-categories))))))
;; C-SPC in a file prompt (C-c C-l's file: too): the selected file in a side
;; window, images as images, without leaving the prompt; it follows the
;; selection until C-SPC again.  Doom's C-SPC (embark's default action)
;; opened the file in the window you came from.  Other prompts keep Doom's.
(defvar-local +completion--preview nil "Whether this file prompt previews.")
(defvar-local +completion--previewed nil "Buffers opened only for the preview.")
(defvar-local +completion--preview-last nil "The file last previewed.")
(defvar-local +completion--preview-window nil "The side window the preview shows in.")
(declare-function vertico--candidate "ext:vertico" (&optional hl))
(declare-function +vertico/embark-preview "ext:vertico" ())

(defun +completion--preview-show ()
  "Show the selected file of this prompt in the side window."
  (let ((file (ignore-errors (expand-file-name (substitute-in-file-name (vertico--candidate))))))
    (when (and file (not (equal file +completion--preview-last)) (file-exists-p file)
               (not (file-remote-p file))
               ;; Not huge files (a 2 GB log would hang the prompt).
               (< (or (file-attribute-size (file-attributes file)) 0) (* 20 1024 1024)))
      (setq +completion--preview-last file)
      (let* ((existing (find-buffer-visiting file))
             (buf (or existing
                      (if (file-directory-p file)
                          (let ((default-directory file)) (dired-noselect file))
                        (let ((inhibit-message t) (large-file-warning-threshold nil))
                          (find-file-noselect file t))))))
        (unless existing (push buf +completion--previewed))
        (setq +completion--preview-window
              (display-buffer buf '((display-buffer-in-side-window)
                              (side . right) (window-width . 0.45)
                                    (window-parameters (no-delete-other-windows . t)))))))))

(defun +completion/preview-dwim ()
  "In a file prompt: preview the selected file, and follow the selection
until called again.  Elsewhere: Doom's preview."
  (interactive)
  (if (not minibuffer-completing-file-name)
      (+vertico/embark-preview)
    (setq +completion--preview (not +completion--preview))
    (if +completion--preview
        (progn (add-hook 'post-command-hook #'+completion--preview-follow-h nil t)
               (add-hook 'minibuffer-exit-hook #'+completion--preview-cleanup-h nil t)
               (+completion--preview-show))
      (remove-hook 'post-command-hook #'+completion--preview-follow-h t)
      (+completion--preview-cleanup-h))))

(defun +completion--preview-follow-h ()
  (when +completion--preview (+completion--preview-show)))

(defun +completion--preview-cleanup-h ()
  "Close the preview: its window, and buffers opened only for it."
  (let ((buffers +completion--previewed) (win +completion--preview-window))
    (setq +completion--previewed nil +completion--preview-last nil +completion--preview-window nil)
    (when (and (window-live-p win) (window-parameter win 'window-side)) (delete-window win))
    (dolist (b buffers)
      (when (and (buffer-live-p b) (not (buffer-modified-p b)) (not (get-buffer-window b t)))
        (kill-buffer b)))))

(with-eval-after-load 'vertico
  (defvar vertico-map)
  (define-key vertico-map (kbd "C-c C-r") #'+completion/refresh-files)
  (define-key vertico-map (kbd "C-SPC") #'+completion/preview-dwim))


;;;; Unicode

;; \omega in prose completes to ω, the character shown next to each name in
;; the popup: `cape-tex', the table of the TeX input method.  Backslash
;; names only (its ^ and _ forms would fire on Org's _underline_ and x^2),
;; and not where \omega is meant: LaTeX buffers, Org's math and src blocks.
(declare-function cape-tex "ext:cape-char" (&optional interactive))
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))

(defun +completion--count (regexp string)
  "How many times REGEXP matches in STRING."
  (let ((n 0) (start 0))
    (while (string-match regexp string start)
      (setq n (1+ n) start (match-end 0)))
    n))

(defun +completion--org-math-p ()
  "Whether point is in Org math: \\(...\\), \\[...\\], $...$ or a LaTeX environment,
closed or still being typed.  (A bare \\name parses as a LaTeX fragment too.)"
  (let ((before (buffer-substring-no-properties (line-beginning-position) (point))))
    (or (> (+completion--count "\\\\[([]" before) (+completion--count "\\\\[])]" before))
        (cl-oddp (+completion--count "\\$" before))
        (eq (org-element-type (org-element-context)) 'latex-environment))))

(defun +completion-tex-capf ()
  "Complete a Unicode character from its TeX name (\\omega → ω) in prose."
  (when (and (looking-back "\\\\[[:alpha:]]+" (line-beginning-position))
             (not (derived-mode-p 'tex-mode 'latex-mode 'LaTeX-mode))
             (not (and (derived-mode-p 'org-mode)
                       (or (+completion--org-math-p) (org-in-src-block-p t)))))
    (require 'cape-char)
    (cape-tex)))

(add-hook 'text-mode-hook
          (defun +completion-tex-h ()
            (add-hook 'completion-at-point-functions #'+completion-tex-capf 70 t)))

;; SPC i u: every Unicode character by name, the character first, like
;; `nerd-icons-insert' (`insert-char' showed names only).  Recently
;; inserted ones come first (history); C-x 8 RET is still `insert-char'.
(defvar +unicode-history nil "Characters inserted with `+unicode/insert'.")
(defvar +unicode--candidates nil "Cached candidates of `+unicode/insert'.")

(defun +unicode--candidates ()
  "\"C  NAME  U+XXXX\" for each named character, built once."
  (or +unicode--candidates
      (setq +unicode--candidates
            (let (cands)
              (maphash (lambda (name char)
                         (push (format "%s%s  %s  U+%04X"
                                       ;; A combining mark needs a base to show.
                                       (if (memq (get-char-code-property char 'general-category)
                                                 '(Mn Me))
                                           "◌" "")
                                       (char-to-string char) name char)
                               cands))
                       (ucs-names))
              cands))))

(defun +unicode--char (cand)
  "The character of candidate CAND."
  (and (string-match "U\\+\\([[:xdigit:]]+\\)\\'" cand)
       (string-to-number (match-string 1 cand) 16)))

(defun +unicode/insert (char &optional count)
  "Insert CHAR (COUNT times), picked by name with the character shown."
  (interactive
   (let ((cands (+unicode--candidates)))
     (list (or (+unicode--char
                (completing-read
                 "Unicode: "
                 (lambda (str pred action)
                   (if (eq action 'metadata)
                       `(metadata (category . unicode-char)
                                  (annotation-function
                                   . ,(lambda (c)
                                        (when-let* ((ch (+unicode--char c))
                                                    (script (aref char-script-table ch)))
                                          (format "   %s" script)))))
                     (complete-with-action action cands str pred)))
                 nil t nil '+unicode-history))
               (user-error "No character"))
           (prefix-numeric-value current-prefix-arg))))
  (insert (make-string (or count 1) char)))

(map! :leader :desc "Unicode (char shown)" "i u" #'+unicode/insert)

(provide '+completion)
;;; +completion.el ends here
