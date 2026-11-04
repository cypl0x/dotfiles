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
One list without duplicates (`cape-capf-super' keeps a word once per source)."
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

(defun +completion--prose ()
  (list #'+completion-prose-capf))

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
  "Completion functions for CONTEXT (default: `+completion-context')."
  (pcase (or context (+completion-context))
    ('org-link (delq nil (list (and (fboundp 'org-roam-complete-link-at-point)
                                    #'org-roam-complete-link-at-point)
                               #'cape-file)))
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
(map! :i "C-SPC" #'+completion/dwim
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
(custom-set-faces!
  `(corfu-current :background ,(doom-blend 'blue 'bg 0.3) :foreground ,(doom-color 'fg)
                  :weight bold :extend t))

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

(defun +minibuffer--remember (entry)
  "Put ENTRY first in `+minibuffer--ring', once."
  (when entry
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

(map! :leader :desc "Reopen last minibuffer" "'" #'+minibuffer/resume
      :map minibuffer-local-map
      "C-'" #'+minibuffer/older
      "C-\"" #'+minibuffer/newer)

(provide '+completion)
;;; +completion.el ends here
