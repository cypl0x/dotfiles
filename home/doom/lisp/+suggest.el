;;; lisp/+suggest.el --- Copilot-like inline suggestions (minuet, Claude) -*- lexical-binding: t; -*-
;;
;; As you pause typing code, a suggestion for what comes next shows as ghost
;; text after point: the rest of the line or a whole block.  minuet-ai.el
;; does it, with Claude (the fast model, the API key gptel already uses).
;;
;;   TAB     take the whole suggestion
;;   M-RET   take its first line (C-u N M-RET: N lines)
;;   M-]  M-[   next / previous suggestion
;;   C-g     dismiss
;;   M-p     none showing: the last one that went away, back (no request);
;;           M-p again the one before, M-n newer.  M-n: ask for one
;;
;; In code buffers and in Org and Markdown (see Prose below); M-x minuet-show-suggestion
;; anywhere else.  With corfu's popup open too, TAB is corfu's (its map
;; comes first); once it's closed, TAB takes the suggestion.
;; Each pause is a request: debounce and throttle keep them few.
;;
;;; Code:

(declare-function gptel-api-key-from-auth-source "gptel" (&optional host user))

(defvar +suggest--key nil "The Anthropic API key, looked up once.")

(defun +suggest-api-key ()
  "The Anthropic key from auth-source, as gptel finds it (cached: minuet
asks before every request)."
  (or +suggest--key
      (setq +suggest--key (gptel-api-key-from-auth-source "api.anthropic.com"))))

(use-package! minuet
  :hook (prog-mode . minuet-auto-suggestion-mode)
  :config
  ;; Fast enough to see while you pause (measured 13:25: three continuations
  ;; took ~2 s and one request 15 s, past the 3 s timeout): one
  ;; continuation as you pause (M-] asks for more), half the context, 0.4 s
  ;; debounce, a 5 s timeout.
  (setq minuet-provider 'claude
        minuet-n-completions 1
        minuet-context-window 8000
        minuet-request-timeout 5
        minuet-auto-suggestion-debounce-delay 0.4
        minuet-auto-suggestion-throttle-delay 1.0)
  (plist-put minuet-claude-options :api-key #'+suggest-api-key)
  (map! :map minuet-active-mode-map
        "TAB"   #'minuet-accept-suggestion
        [tab]   #'minuet-accept-suggestion
        "M-RET" #'minuet-accept-suggestion-line
        "M-]"   #'minuet-next-suggestion
        "M-["   #'minuet-previous-suggestion
        "C-g"   #'minuet-dismiss-suggestion))


;;;; Prose: Org and Markdown ─────────────────────────────────────────────────

;; In Org and Markdown too, the way VS Code's Copilot suggests inline: the
;; rest of the sentence, the paragraph, a list item, a table row, the body
;; of a src block.  M-n / M-p in insert state cycle through the suggestions
;; (asking for some if none shows; nothing used those keys in Org's insert
;; state).  TAB takes one, C-g dismisses it.  M-RET stays Org's (a new item
;; or heading), not "take the first line".
(defvar minuet-claude-options)
(defvar minuet-active-mode-map)
(declare-function minuet-show-suggestion "ext:minuet" ())
(declare-function minuet-next-suggestion "ext:minuet" ())
(declare-function minuet-previous-suggestion "ext:minuet" ())

(defconst +suggest-prose-prompt
  "You complete writing in an Emacs buffer (Org or Markdown), like an inline \
suggestion in an editor.  Continue from the cursor with what the writer most \
likely writes next, in their language, voice and terminology: the rest of the \
sentence, or the rest of the paragraph; in a list, the item; in a table, the \
row in the table's columns; in a src block, the code in that block's language; \
on an empty heading line, a heading.  Keep the document's markup.

Input markers:
- `<contextAfterCursor>`: Context after cursor
- `<cursorPosition>`: Current cursor location
- `<contextBeforeCursor>`: Context before cursor

The user input is given in **reverse** order: first the context after the \
cursor, then the context before it.
"
  "What minuet tells the model in prose buffers.")

(defconst +suggest-prose-guidelines
  "Guidelines:
1. Continue exactly at `<cursorPosition>`; start with a space only if one is needed.
2. Offer the most likely continuation first; when asked for several, also a \
longer one (finish the paragraph or block) and one taking another direction.
3. Return completions separated by the marker <endCompletion>.
4. No comments, no code fences, no quotes around the text.
5. Never repeat text that is already before or after the cursor.
6. Output only the text to insert: never explain, never think aloud, never mention the cursor or these markers."
  "minuet's guidelines in prose buffers.")

(defun +suggest-prose-h ()
  "Inline suggestions in this prose buffer, asked for prose."
  (when (and (require 'minuet nil t) (boundp 'minuet-claude-options))
    (setq-local minuet-claude-options
                (plist-put (copy-tree minuet-claude-options) :system
                           (list :template 'minuet-default-system-template
                                 :prompt +suggest-prose-prompt
                                 :guidelines +suggest-prose-guidelines
                                 :n-completions-template 'minuet-default-n-completion-template)))
    (setq-local minuet-auto-suggestion-block-predicates
                (cons #'+suggest-prose-mid-line-p (default-value 'minuet-auto-suggestion-block-predicates)))
    (minuet-auto-suggestion-mode 1)))

(add-hook! '(org-mode-hook markdown-mode-hook) #'+suggest-prose-h)

(map! :after org :map org-mode-map :i "M-n" #'+suggest/next :i "M-p" #'+suggest/previous)
(map! :after markdown-mode :map markdown-mode-map :i "M-n" #'+suggest/next :i "M-p" #'+suggest/previous)

;; M-RET in Org is a new item or heading, also while a suggestion shows.
(declare-function minuet-dismiss-suggestion "ext:minuet" ())
(declare-function org-meta-return "org" (&optional arg))
(defun +suggest/org-meta-return (&optional arg)
  "Dismiss the suggestion, then Org's M-RET (ARG as there)."
  (interactive "P")
  (minuet-dismiss-suggestion)
  (org-meta-return arg))

(add-hook 'minuet-active-mode-hook
          (defun +suggest-org-keep-m-ret-h ()
            (when (derived-mode-p 'org-mode)
              (setq-local minor-mode-overriding-map-alist
                          (cons (cons 'minuet-active-mode
                                      (let ((map (make-sparse-keymap)))
                                        (set-keymap-parent map minuet-active-mode-map)
                                        (define-key map (kbd "M-RET") #'+suggest/org-meta-return)
                                        (define-key map (kbd "M-n") #'+suggest/next)
                                        (define-key map (kbd "M-p") #'+suggest/previous)
                                        map))
                                minor-mode-overriding-map-alist)))))

;; minuet trims every suggestion (right for code), so "I want to" got
;; "start…" glued on: "tostart".  In prose, a space comes back when the
;; cursor sits right after a word or punctuation and the suggestion starts
;; with a word.
(defun +suggest-prose-space-a (args)
  "Filter for `minuet--display-suggestion' ARGS: spaces before prose."
  (if (and (derived-mode-p 'text-mode)
           (memq (char-syntax (or (char-before) ?\s)) '(?w ?_ ?.))
           (not (memq (char-before) '(?\( ?\[ ?\" ?' ?/ ?- ?~ ?=))))
      (cons (mapcar (lambda (s) (if (and (stringp s) (string-match-p "\\`[[:alnum:]([\"'“„*/=~]" s))
                                     (concat " " s)
                                   s))
                    (car args))
            (cdr args))
    args))


(defun +suggest-prose-mid-line-p ()
  "Non-nil when text follows point on this line: a suggestion there would
push it sideways, so in prose only M-n asks for one."
  (save-excursion (skip-chars-forward " \t.,;:!?)\\]}\"'”*/=~") (not (eolp))))

;; A suggestion is wrong when the model thinks aloud ("Wait, the cursor
;; sits…") or echoes the prompt's markers, and stale when the buffer changed
;; under an unmoved point while it was coming (a revert, an agent's edit):
;; minuet only checks that point is the same number.
(defconst +suggest-meta-re
  (concat "\\`[ \t\n]*\\(?:Wait\\b\\|Hmm\\b\\|Let me\\b\\|Okay, \\|The cursor\\b\\|The user\\b\\)"
          "\\|\\bcursor\\(?:Position\\| position\\| sits\\| is at\\)"
          "\\|</?\\(?:cursorPosition\\|contextAfterCursor\\|contextBeforeCursor\\|endCompletion\\)>")
  "Suggestions matching this are the model talking, not text to insert.")

(defvar-local +suggest--asked nil
  "(POINT . `buffer-chars-modified-tick') when suggestions were last asked for.")

(defun +suggest-ask-a (&rest _)
  "Remember where and on what text suggestions were asked for."
  (+suggest--count :asked)
  (setq +suggest--asked (cons (point) (buffer-chars-modified-tick))))

(defvar +suggest--stats (list :asked 0 :shown 0 :empty 0 :talking 0 :stale 0)
  "Since Emacs started: suggestions asked for, shown, and dropped by reason.")

(defun +suggest--count (key &optional n)
  (setq +suggest--stats (plist-put +suggest--stats key (+ (or n 1) (plist-get +suggest--stats key)))))

(defvar +suggest--recalling nil
  "Non-nil while a suggestion that went away is shown again (`+suggest/again').")

(defun +suggest-sane-a (args)
  "Filter for `minuet--display-suggestion' ARGS: drop stale and talking ones.
One brought back (`+suggest/again') was checked when it first came."
  (if +suggest--recalling args
    (setq +suggest--recalled nil)       ; a fresh one: M-n/M-p cycle it
    (let* ((all (seq-filter #'stringp (car args)))
           (items (seq-remove (lambda (s) (string-match-p +suggest-meta-re s)) all))
           (stale (and +suggest--asked (eq (point) (car +suggest--asked))
                       (/= (buffer-chars-modified-tick) (cdr +suggest--asked)))))
      (+suggest--count :talking (- (length all) (length items)))
      (cond ((null all) (+suggest--count :empty))
            (stale (+suggest--count :stale) (setq items nil))
            (items (+suggest--count :shown)))
      (cons items (cdr args)))))

(defun +suggest/stats ()
  "How inline suggestions fared since Emacs started, in the echo area."
  (interactive)
  (message "Suggestions: %d asked, %d shown; dropped: %d empty, %d stale (text changed meanwhile), %d talking.  Not answered in %ss or answered after you moved on: the rest."
           (plist-get +suggest--stats :asked) (plist-get +suggest--stats :shown)
           (plist-get +suggest--stats :empty) (plist-get +suggest--stats :stale)
           (plist-get +suggest--stats :talking)
           (bound-and-true-p minuet-request-timeout)))
(with-eval-after-load 'minuet
  (advice-add 'minuet-show-suggestion :before #'+suggest-ask-a)
  (advice-add 'minuet--display-suggestion :filter-args #'+suggest-sane-a)
  (advice-add 'minuet--display-suggestion :filter-args #'+suggest-prose-space-a))


;;;; Bring back a suggestion that went away ───────────────────────────────

;; A suggestion goes when you move or type something it doesn't start with,
;; and asking again gives another one: the good one noticed a second too
;; late was gone.  Each one that goes (unless taken) is kept here, with
;; where it stood and the text around it.  M-p with none showing brings
;; the last back, without asking the model: where you are if you typed its
;; start (the rest shows), else where it stood, the cursor back there,
;; while the text around is unchanged.  M-p again: the one before; M-n:
;; newer.  M-n with none showing asks for a new one, as before.
(defvar +suggest-recall-size 10 "How many suggestions that went away are kept per buffer.")

(defvar-local +suggest--recall nil
  "Suggestions that went away, newest first: plists (:marker :before :after
:suggestions :index).")

(defvar-local +suggest--recalled nil
  "Index in `+suggest--recall' of the suggestion brought back now, or nil.")

(defvar +suggest--taking nil "Non-nil while a suggestion is being taken (not kept).")

(defvar minuet--current-overlay)
(defvar minuet--current-suggestions)
(defvar minuet--current-suggestion-index)
(declare-function minuet--display-suggestion "ext:minuet" (suggestions &optional index))

(defconst +suggest--recall-context 60
  "Characters before and after a suggestion that must be unchanged to bring it back.")

(defun +suggest--keep-a (&rest _)
  "Before minuet removes a suggestion: keep it, unless it is being taken."
  (when-let* (((not (or +suggest--taking +suggest--recalling)))
              (ov minuet--current-overlay)
              ((overlay-buffer ov))
              (suggestions (seq-filter #'stringp minuet--current-suggestions)))
    (with-current-buffer (overlay-buffer ov)
      (let ((pos (overlay-start ov)))
        ;; The same one again (cycled, redrawn, brought back): moved to the front.
        (setq +suggest--recall
              (cl-remove-if (lambda (e) (and (eql (marker-position (plist-get e :marker)) pos)
                                             (equal (plist-get e :suggestions) suggestions)
                                             (progn (set-marker (plist-get e :marker) nil) t)))
                            +suggest--recall))
        (push (list :marker (copy-marker pos)
                      :before (buffer-substring-no-properties
                               (max (point-min) (- pos +suggest--recall-context)) pos)
                      :after (buffer-substring-no-properties
                              pos (min (point-max) (+ pos +suggest--recall-context)))
                      :suggestions suggestions
                      :index minuet--current-suggestion-index)
              +suggest--recall)
        (when (nthcdr +suggest-recall-size +suggest--recall)
          (set-marker (plist-get (car (last +suggest--recall)) :marker) nil)
          (setq +suggest--recall (butlast +suggest--recall)))))))

(defun +suggest--taking-a (fn &rest args)
  "Around minuet's take commands (FN with ARGS): the suggestion isn't kept."
  (let ((+suggest--taking t)) (apply fn args)))

(defun +suggest--recall-fit (entry)
  "Where and what ENTRY can show now: (POS SUGGESTIONS INDEX), or nil.
Where you are, when the text since its place is what it starts with;
else at its place, when the text around that is unchanged."
  (let* ((pos (marker-position (plist-get entry :marker)))
         (before (plist-get entry :before))
         (after (plist-get entry :after))
         (suggestions (plist-get entry :suggestions))
         (index (or (plist-get entry :index) 0)))
    (when (and pos (>= (- pos (point-min)) (length before))
               (equal (buffer-substring-no-properties (- pos (length before)) pos) before))
      (let* ((typed (and (> (point) pos) (<= (- (point) pos) 200)
                         (buffer-substring-no-properties pos (point))))
             (rest (and typed
                        (delq nil (mapcar (lambda (s) (and (string-prefix-p typed s)
                                                           (length> s (length typed))
                                                           (substring s (length typed))))
                                          suggestions)))))
        (cond (rest (list (point) rest 0))
              ((and (<= (+ pos (length after)) (point-max))
                    (equal (buffer-substring-no-properties pos (+ pos (length after))) after))
               (list pos suggestions index)))))))

(defun +suggest--recall-show (from step)
  "Show the first kept suggestion that fits, from index FROM going STEP.
Non-nil when one showed."
  (cl-loop for i = from then (+ i step)
           while (and (>= i 0) (< i (length +suggest--recall)))
           for fit = (+suggest--recall-fit (nth i +suggest--recall))
           when fit
           return (pcase-let ((`(,pos ,suggestions ,index) fit))
                    (goto-char pos)
                    (let ((+suggest--recalling t))   ; not kept twice, not "stale"
                      (minuet--display-suggestion suggestions index))
                    (setq +suggest--recalled i)
                    (message "Brought back (%d of %d kept)%s" (1+ i) (length +suggest--recall)
                             (if (< (1+ i) (length +suggest--recall)) ": M-p the one before" ""))
                    t)))

(defun +suggest--recalled-showing-p ()
  "Non-nil when the suggestion showing is one brought back."
  (and +suggest--recalled (bound-and-true-p minuet-active-mode)
       (memq last-command '(+suggest/again +suggest/next +suggest/previous))))

(defun +suggest/again ()
  "Bring back the last suggestion that went away, without asking the model."
  (interactive)
  (unless (+suggest--recall-show 0 1)
    (user-error "No suggestion to bring back here (none kept, or the text around it changed)")))

(defun +suggest/next ()
  "The next inline suggestion; ask for some when none shows.
Showing one brought back (\\[+suggest/previous]): the newer kept one."
  (interactive)
  (cond ((+suggest--recalled-showing-p)
         (unless (+suggest--recall-show (1- +suggest--recalled) -1)
           (message "No newer one kept")))
        ((bound-and-true-p minuet-active-mode) (minuet-next-suggestion))
        (t (minuet-show-suggestion))))

(defun +suggest/previous ()
  "The previous inline suggestion.  None showing: bring back the last that
went away (no request), or ask for one when none is kept for here.
Showing one brought back: the one kept before it."
  (interactive)
  (cond ((+suggest--recalled-showing-p)
         (unless (+suggest--recall-show (1+ +suggest--recalled) 1)
           (message "No older one kept")))
        ((bound-and-true-p minuet-active-mode) (minuet-previous-suggestion))
        ((+suggest--recall-show 0 1))
        (t (minuet-show-suggestion))))

(with-eval-after-load 'minuet
  (advice-add 'minuet--cleanup-suggestion :before #'+suggest--keep-a)
  (dolist (take '(minuet-accept-suggestion minuet-accept-suggestion-line minuet-accept-suggestion-word))
    (advice-add take :around #'+suggest--taking-a)))

;; Code buffers too: M-n / M-p in insert state, also while one shows.
(map! :after minuet :map minuet-active-mode-map "M-n" #'+suggest/next "M-p" #'+suggest/previous)
(map! :map prog-mode-map :i "M-n" #'+suggest/next :i "M-p" #'+suggest/previous)
;;;; Narrowed buffers (Org capture): minuet's context counted from 1

;; `minuet--get-context' (minuet 2026-10-09, still so upstream) takes the
;; characters before point as `point' itself, not (- point (point-min)).
;; In a narrowed buffer far into its file (an Org capture at the end of
;; inbox.org) it then reached before the narrowing: args-out-of-range from
;; its debounce timer at every pause, 109 times one evening.  The same
;; function, counting from `point-min'.
(defvar minuet-context-window)
(defvar minuet-context-ratio)
(declare-function minuet--add-language-comment "ext:minuet" ())
(declare-function minuet--add-tab-comment "ext:minuet" ())

(defun +suggest--get-context ()
  "`minuet--get-context', right in narrowed buffers too."
  (let* ((point (point))
         (n-chars-before (- point (point-min)))
         (point-max (point-max))
         (n-chars-after (- point-max point))
         (before-start (point-min))
         (after-end point-max)
         (is-incomplete-before nil)
         (is-incomplete-after nil))
    (when (>= (+ n-chars-before n-chars-after) minuet-context-window)
      (cond ((< n-chars-before (* minuet-context-ratio minuet-context-window))
             (setq after-end (+ point (- minuet-context-window n-chars-before))
                   is-incomplete-after t))
            ((< n-chars-after (* (- 1 minuet-context-ratio) minuet-context-window))
             (setq before-start (- point (- minuet-context-window n-chars-after))
                   is-incomplete-before t))
            (t
             (setq is-incomplete-before t
                   is-incomplete-after t
                   after-end (+ point (floor (* minuet-context-window (- 1 minuet-context-ratio))))
                   before-start (+ (point-min)
                                   (max 0 (- n-chars-before
                                             (floor (* minuet-context-window minuet-context-ratio)))))))))
    `(:before-cursor ,(buffer-substring-no-properties before-start point)
      :after-cursor ,(buffer-substring-no-properties point after-end)
      :language-and-tab ,(format "%s\n%s" (minuet--add-language-comment) (minuet--add-tab-comment))
      :is-incomplete-before ,is-incomplete-before
      :is-incomplete-after ,is-incomplete-after)))

(with-eval-after-load 'minuet
  (advice-add 'minuet--get-context :override #'+suggest--get-context))

(provide '+suggest)
;;; +suggest.el ends here
