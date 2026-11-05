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

(defun +suggest/next ()
  "The next inline suggestion; ask for some when none shows."
  (interactive)
  (if (bound-and-true-p minuet-active-mode) (minuet-next-suggestion) (minuet-show-suggestion)))

(defun +suggest/previous ()
  "The previous inline suggestion; ask for some when none shows."
  (interactive)
  (if (bound-and-true-p minuet-active-mode) (minuet-previous-suggestion) (minuet-show-suggestion)))

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
                                        (define-key map (kbd "M-n") #'minuet-next-suggestion)
                                        (define-key map (kbd "M-p") #'minuet-previous-suggestion)
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

(defun +suggest-sane-a (args)
  "Filter for `minuet--display-suggestion' ARGS: drop stale and talking ones."
  (let* ((all (seq-filter #'stringp (car args)))
         (items (seq-remove (lambda (s) (string-match-p +suggest-meta-re s)) all))
         (stale (and +suggest--asked (eq (point) (car +suggest--asked))
                     (/= (buffer-chars-modified-tick) (cdr +suggest--asked)))))
    (+suggest--count :talking (- (length all) (length items)))
    (cond ((null all) (+suggest--count :empty))
          (stale (+suggest--count :stale) (setq items nil))
          (items (+suggest--count :shown)))
    (cons items (cdr args))))

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
(provide '+suggest)
;;; +suggest.el ends here
