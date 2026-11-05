;;; well-formed.el --- A writing assistant made of rules, not models -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; Version: 0.1
;; Package-Requires: ((emacs "30.1"))
;; Keywords: wp, convenience
;;
;;; Commentary:
;;
;; Grammarly's ground floor, as Emacs Lisp: correctness, clarity, engagement,
;; delivery and consistency, checked by rules, word lists and statistics;
;; no server, no Java, no network.  An AI layer may build on it (it reports
;; through the same findings), but nothing here asks a model.
;;
;; How it stays out of the way of typing:
;;   - only prose is read: Org and Markdown markup, code, links, tables,
;;     drawers and blocks are masked out first (same length, so positions
;;     hold); in code buffers only comments;
;;   - the text is cut into paragraphs, each checked once and cached by its
;;     text: an edit re-checks the paragraph it touched, nothing else;
;;   - checking runs on idle and inside `while-no-input': a key pressed
;;     mid-check abandons it.
;;
;; English and German, decided per paragraph (#+language: or the buffer's
;; majority for short ones).  Styles (general, academic, technical, business,
;; casual, creative) tune thresholds and which rules speak; a document picks
;; one with "#+well_formed: academic" (Org), "well_formed: academic"
;; (Markdown front matter) or the file-local `well-formed-style'.
;;
;; Findings go to flycheck (checker `well-formed', chained after the mode's
;; own checker) or flymake (`well-formed-flymake').  Commands:
;;   well-formed-fix        apply the suggestion at point (choose if several)
;;   well-formed-fix-all    walk the buffer's findings of one rule, y/n each
;;   well-formed-ignore     this occurrence, this rule here, this rule everywhere
;;   well-formed-explain    what the rule at point is about, with examples
;;   well-formed-list       every finding, grouped, with preview
;;   well-formed-report     scores, readability, tone, statistics, plots
;;   well-formed-menu       all of the above in one transient
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup well-formed nil
  "A rule-based writing assistant."
  :group 'wp
  :prefix "well-formed-")

;;;; Options

(defcustom well-formed-style 'general
  "The default writing style.  A document can choose its own (see Commentary)."
  :type '(choice (const general) (const academic) (const technical)
                 (const business) (const casual) (const creative))
  :safe #'symbolp)

(defcustom well-formed-language nil
  "Force a language (\"en\" or \"de\"); nil detects it per paragraph."
  :type '(choice (const nil) string)
  :safe (lambda (v) (or (null v) (stringp v))))

(defcustom well-formed-disabled-rules nil
  "Rules never reported, anywhere."
  :type '(repeat symbol))

(defcustom well-formed-disabled-categories nil
  "Categories never reported: correctness, clarity, engagement, delivery,
consistency."
  :type '(repeat symbol))

(defcustom well-formed-check-quotes nil
  "Whether quote blocks are checked.  Off: what you quote isn't your
writing (and pasted logs or mail land there)."
  :type 'boolean)

(defcustom well-formed-idle-delay 0.6
  "Seconds of idle time before re-checking (flymake; flycheck has its own)."
  :type 'number)

(defcustom well-formed-max-buffer-size 2000000
  "Larger buffers aren't checked."
  :type 'integer)

(defcustom well-formed-ignore-file
  (expand-file-name "well-formed.eld"
                    (if (boundp 'doom-data-dir) (symbol-value 'doom-data-dir) user-emacs-directory))
  "Where ignored occurrences and rules are kept."
  :type 'file)

(defvar well-formed-styles
  '((general   :sentence 30 :off (contraction first-person conjunction-start))
    (academic  :sentence 40 :off (conjunction-start-off)
               :level ((passive . info) (contraction . warning) (informal . warning)
                       (weasel . warning) (first-person . info)))
    (technical :sentence 30 :off (contraction first-person conjunction-start)
               :level ((passive . info) (hedge . warning) (weasel . warning)))
    (business  :sentence 25 :off (first-person conjunction-start)
               :level ((jargon . warning) (hedge . warning) (contraction . info)))
    (casual    :sentence 45 :off (contraction first-person conjunction-start informal
                                  complex-word jargon passive hedge)
               :level ((wordy . info)))
    (creative  :sentence 0 :off (contraction first-person conjunction-start informal
                                 complex-word passive long-sentence)
               :level ((cliche . warning) (adverb . info))))
  "Styles: per style, the sentence length limit (0: none), rules :off, and
rule levels overridden (error, warning, info).")

;;;; Rules

(cl-defstruct (well-formed-rule (:constructor well-formed--make-rule))
  id category level langs doc examples function)

(defvar well-formed--rules nil "Registered rules, in order.")

(defmacro well-formed-define-rule (id &rest props)
  "Define rule ID.  PROPS: :category :level :langs :doc :examples :function.
The function gets a paragraph (`well-formed-para') and returns findings
\(BEG END MESSAGE FIXES), offsets into the paragraph's text; FIXES are
replacement strings (\"\" deletes)."
  (declare (indent 1))
  `(progn
     (setq well-formed--rules
           (cons (well-formed--make-rule
                  :id ',id
                  :category ,(plist-get props :category)
                  :level ,(or (plist-get props :level) ''warning)
                  :langs ,(or (plist-get props :langs) ''("en" "de"))
                  :doc ,(plist-get props :doc)
                  :examples ,(plist-get props :examples)
                  :function ,(plist-get props :function))
                 (cl-remove ',id well-formed--rules :key #'well-formed-rule-id)))
     ',id))

(defun well-formed--rule (id)
  (cl-find id well-formed--rules :key #'well-formed-rule-id))

;;;; Paragraphs

(cl-defstruct (well-formed-para (:constructor well-formed--make-para))
  beg            ; buffer position of the text's first character
  text           ; the masked text: markup and code are \0
  kind           ; prose, heading or item
  lang           ; "en" or "de"
  style          ; the style's plist
  sentences)     ; ((BEG . END) ...), offsets into text

(defconst well-formed--mask ?\0 "What masked characters become.")

(defvar well-formed--syntax-table
  (let ((table (make-syntax-table text-mode-syntax-table)))
    (modify-syntax-entry ?\0 "." table)
    (modify-syntax-entry ?’ "w" table)
    (modify-syntax-entry ?_ "." table)
    table)
  "Word syntax for the rules: apostrophes inside words, \\0 apart.")

(defun well-formed--mask-region (beg end)
  "Replace BEG..END of the current (scratch) buffer with mask characters,
keeping newlines."
  (when (< beg end)
    (save-excursion
      (let ((masked (replace-regexp-in-string "[^\n]" (string well-formed--mask)
                                              (buffer-substring-no-properties beg end) t t)))
        (goto-char beg)
        (delete-region beg end)
        (insert masked)))))

(defun well-formed--mask-matches (regexp &rest groups)
  "Mask every match of REGEXP (or of its GROUPS) from point-min."
  (goto-char (point-min))
  (while (re-search-forward regexp nil t)
    (let ((start (match-beginning 0)) (end (match-end 0)))
      (dolist (g (or groups '(0)))
        (when (match-beginning g)
          (well-formed--mask-region (match-beginning g) (match-end g))))
      (goto-char (max end (1+ start))))))

(defun well-formed--mask-lines-between (open close)
  "Mask whole lines from a line matching OPEN through one matching CLOSE."
  (goto-char (point-min))
  (let ((case-fold-search t))
    (while (re-search-forward open nil t)
      (let ((b (line-beginning-position)))
        (if (re-search-forward close nil t)
            (well-formed--mask-region b (line-end-position))
          (well-formed--mask-region b (point-max)))))))

(defun well-formed--mask-org ()
  (let ((case-fold-search t))
    ;; Blocks, except the prose ones (verse, center; quote when
    ;; `well-formed-check-quotes').
    (well-formed--mask-lines-between
     (concat "^[ \t]*#\\+begin_\\(src\\|example\\|export\\|comment\\|latex\\|html\\|ascii\\|dynamic"
             (if well-formed-check-quotes "" "\\|quote") "\\)")
     "^[ \t]*#\\+end_")
    (well-formed--mask-lines-between "^[ \t]*:[A-Za-z_]+:[ \t]*$" "^[ \t]*:end:[ \t]*$")
    (well-formed--mask-lines-between "^[ \t]*\\\\begin{" "^[ \t]*\\\\end{")
    ;; Whole lines that aren't prose: keywords and block delimiters, comments,
    ;; tables, fixed width, planning and clocks.
    (well-formed--mask-matches
     "^[ \t]*\\(?:#\\+.*\\|# .*\\|#$\\||.*\\|: .*\\|:$\\|\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\|CLOCK\\):.*\\)$")
    ;; Headings: stars, keyword, priority, tags, statistics cookies.
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (while (re-search-forward
              "^\\(\\*+ +\\(?:\\(?:TODO\\|DONE\\|NEXT\\|WAIT\\|HOLD\\|PROJ\\|STRT\\|KILL\\|LOOP\\|IDEA\\|OKAY\\|YES\\|NO\\)\\b \\)?\\(?:\\[#.\\] \\)?\\)"
              nil t)
        (well-formed--mask-region (match-beginning 1) (match-end 1))
        (when (re-search-forward "[ \t]+\\(:[[:alnum:]_@#%:]+:\\)[ \t]*$" (line-end-position) t)
          (well-formed--mask-region (match-beginning 1) (match-end 1)))))
    (well-formed--mask-matches "\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]")
    ;; Inline: links (the description stays), code, verbatim, math, footnote
    ;; references, timestamps, inline src, export snippets, macros, targets.
    (well-formed--mask-matches "\\(\\[\\[[^]\n]*\\]\\[\\)[^]\n]*\\(\\]\\]\\)" 1 2)
    (well-formed--mask-matches "\\[\\[[^]\n]*\\]\\]")
    (well-formed--mask-matches "\\(?:^\\|[[:space:](\"'{]\\)\\(\\([~=]\\)[^ \t\n]\\(?:[^\n]*?[^ \t\n]\\)?\\2\\)\\(?:[[:space:].,:!?;'\")}-]\\|$\\)" 1)
    (well-formed--mask-matches "\\$\\$[^$]+\\$\\$\\|\\$[^ $\n][^$\n]*\\$\\|\\\\(.*?\\\\)\\|\\\\\\[.*?\\\\\\]")
    (well-formed--mask-matches "\\[fn:[^]\n]*\\]")
    (well-formed--mask-matches "[<[][0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}[^]>\n]*[]>]")
    (well-formed--mask-matches "src_[a-z-]+\\(?:\\[[^]\n]*\\]\\)?{[^}\n]*}")
    (well-formed--mask-matches "@@[^@\n]*@@\\|{{{[^}\n]*}}}\\|<<[^>\n]*>>")
    (well-formed--mask-matches "\\\\[a-zA-Z]+\\(?:{[^}\n]*}\\)?")
    ;; Lists: bullets, counters, checkboxes.
    (well-formed--mask-matches "^[ \t]*\\(\\(?:[-+]\\|[ \t]+\\*\\|[0-9]+[.)]\\|[a-z][.)]\\) \\(?:\\[[ X-]\\] \\)?\\)" 1)
    ;; Emphasis markers: *b* /i/ _u_ +s+ (the words inside stay).
    (goto-char (point-min))
    (while (re-search-forward
            "\\(?:^\\|[[:space:](\"'{\0]\\)\\([*/_+]\\)[^ \t\n]\\(?:[^\n]*?[^ \t\n]\\)?\\(\\1\\)\\(?:[[:space:].,:!?;'\")}\0-]\\|$\\)"
            nil t)
      (let ((close (match-beginning 2)))
        (well-formed--mask-region (match-beginning 1) (match-end 1))
        (well-formed--mask-region close (1+ close))
        (goto-char (1+ close))))))

(defun well-formed--mask-markdown ()
  (well-formed--mask-lines-between "^[ \t]*\\(```\\|~~~\\)" "^[ \t]*\\(```\\|~~~\\)")
  (goto-char (point-min))
  (when (looking-at "---[ \t]*$")
    (let ((b (point)))
      (forward-line 1)
      (when (re-search-forward "^---[ \t]*$" nil t)
        (well-formed--mask-region b (point)))))
  (well-formed--mask-matches "^\\(    \\|\t\\).*$")
  (well-formed--mask-matches "^[ \t]*|.*$")
  (well-formed--mask-matches "^\\(#+ +\\)" 1)
  (well-formed--mask-matches "`[^`\n]+`")
  (well-formed--mask-matches "!?\\[[^]\n]*\\]\\(([^)\n]*)\\|\\[[^]\n]*\\]\\)" 1)
  (well-formed--mask-matches "\\(!?\\[\\)[^]\n]*\\]\0" 1)
  (well-formed--mask-matches "!?\\[[^]\n]*\\(\\]\\)\0" 1)
  (well-formed--mask-matches "<[^>\n]+>")
  (well-formed--mask-matches "^\\[[^]\n]+\\]:.*$")
  (well-formed--mask-matches "\\$\\$[^$]+\\$\\$\\|\\$[^ $\n][^$\n]*\\$")
  (well-formed--mask-matches "^[ \t]*\\(\\(?:[-+*]\\|[0-9]+[.)]\\) \\(?:\\[[ xX]\\] \\)?\\)" 1)
  (well-formed--mask-matches "^[ \t]*\\(>+ ?\\)" 1)
  (well-formed--mask-matches "\\(\\*\\*\\|__\\|\\*\\|~~\\)[^ \n*_~]" 1)
  (well-formed--mask-matches "[^ \n*_~]\\(\\*\\*\\|__\\|\\*\\|~~\\)" 1))

(defun well-formed--mask-urls ()
  (well-formed--mask-matches "\\b\\(?:https?\\|ftp\\|file\\|mailto\\):[^][ \t\n<>()\"]+")
  (well-formed--mask-matches "\\b[[:alnum:]._%+-]+@[[:alnum:].-]+\\.[a-z]\\{2,\\}\\b")
  (well-formed--mask-matches "\\(?:^\\|[ \t(]\\)\\(\\(?:~\\|\\.\\{1,2\\}\\)?/[^ \t\n,;)]+\\)" 1))

(defun well-formed--comment-ranges (beg end)
  "The comments between BEG and END of the current buffer, as (B . E)."
  (save-excursion
    (let ((pos beg) state out)
      (goto-char beg)
      (while (< pos end)
        (setq state (parse-partial-sexp pos end nil nil state 'syntax-table)
              pos (point))
        (when (nth 4 state)
          (let ((b (nth 8 state)))
            (setq state (parse-partial-sexp pos end nil nil state 'syntax-table)
                  pos (point))
            (push (cons b pos) out)))
        (when (and (not (nth 4 state)) (nth 3 state))
          ;; In a string: skip it.
          (setq state (parse-partial-sexp pos end nil nil state 'syntax-table)
                pos (point)))
        (when (= pos (point-max)) (setq pos end)))
      (nreverse out))))

(defun well-formed--masked-text (beg end)
  "The current buffer's BEG..END with everything but prose masked."
  (let ((mode (cond ((derived-mode-p 'org-mode) 'org)
                    ((derived-mode-p 'markdown-mode 'gfm-mode) 'markdown)
                    ((derived-mode-p 'prog-mode) 'prog)
                    (t 'text)))
        (comments (and (derived-mode-p 'prog-mode) (well-formed--comment-ranges beg end)))
        (source (current-buffer)))
    (with-temp-buffer
      (insert-buffer-substring-no-properties source beg end)
      (when (eq mode 'prog)
        ;; Mask everything outside comments, then the comment starters.
        (let ((keep (mapcar (lambda (r) (cons (- (car r) beg -1) (- (cdr r) beg -1))) comments))
              (pos (point-min)))
          (dolist (r keep)
            (well-formed--mask-region pos (car r))
            (setq pos (cdr r)))
          (well-formed--mask-region pos (point-max)))
        (well-formed--mask-matches "^[ \t\0]*\\(\\(?:;+\\|#+\\|//+\\|/\\*+\\|\\*+/?\\|--+\\|%+\\)[!:]?\\)" 1))
      (with-syntax-table well-formed--syntax-table
        (pcase mode
          ('org (well-formed--mask-org))
          ('markdown (well-formed--mask-markdown)))
        (well-formed--mask-urls))
      (buffer-string))))

;;;; Sentences and words

(defconst well-formed--abbreviations
  (regexp-opt '("Mr" "Mrs" "Ms" "Dr" "Prof" "Sr" "Jr" "St" "vs" "etc" "cf" "al" "Fig" "fig"
                "No" "Nr" "ca" "bzw" "usw" "evtl" "ggf" "inkl" "vgl" "Abb" "Kap" "Bd" "Hrsg"
                "Jh" "z.B" "d.h" "u.a" "s.o" "s.u" "e.g" "i.e" "approx" "Str" "Tel" "Inc" "Ltd"
                "Jan" "Feb" "Mar" "Apr" "Jun" "Jul" "Aug" "Sep" "Sept" "Oct" "Okt" "Nov" "Dec" "Dez"))
  "Words a period doesn't end a sentence after.")

(defun well-formed--sentences (text)
  "TEXT's sentences as (BEG . END)."
  (let ((case-fold-search nil) (start 0) (pos 0) out)
    (with-syntax-table well-formed--syntax-table
      (while (string-match "[.!?…]+[\"'”’)\0]*\\(?:[[:space:]]+\\|\\'\\)" text pos)
        (let* ((mb (match-beginning 0)) (me (match-end 0))
               (word-start (save-match-data
                             (let ((i mb))
                               (while (and (> i 0) (string-match-p "[[:alnum:].]" (string (aref text (1- i)))))
                                 (setq i (1- i)))
                               i)))
               (word (substring text word-start mb))
               (next (and (< me (length text)) (aref text me))))
          (if (or (and (eq (aref text mb) ?.)
                       (or (string-match-p (concat "\\`\\(?:" well-formed--abbreviations "\\)\\'") word)
                           (string-match-p "\\`[[:upper:]]\\'" word)))
                  (and next (memq (get-char-code-property next 'general-category) '(Ll))
                       (or (<= (length word) 3) (string-search "." word)
                           ;; "(really?) yes": inside parentheses
                           (string-search ")" (match-string 0 text)))))
              (setq pos me)
            (push (cons start (save-match-data
                                (let ((e me))
                                  (while (and (> e mb) (memq (aref text (1- e)) '(?\s ?\t ?\n))) (setq e (1- e)))
                                  e)))
                  out)
            (setq start me pos me))))
      (when (string-match-p "[[:alpha:]]" (substring text start))
        (push (cons start (length (string-trim-right text "[[:space:]\0]+"))) out)))
    (cl-loop for (b . e) in (nreverse out)
             for b2 = (or (string-match "[^[:space:]]" text b) b)
             when (< b2 e) collect (cons b2 e))))

(defconst well-formed--word-regexp "[[:alpha:]][[:alpha:]'’-]*[[:alpha:]]\\|[[:alpha:]]")

(defun well-formed--words (text &optional beg end)
  "Words of TEXT (between BEG and END) as (WORD BEG . END)."
  (let ((pos (or beg 0)) (end (or end (length text))) out)
    (while (and (< pos end) (string-match well-formed--word-regexp text pos) (< (match-beginning 0) end))
      (push (cons (match-string 0 text) (cons (match-beginning 0) (match-end 0))) out)
      (setq pos (match-end 0)))
    (nreverse out)))

(defun well-formed--word-count (text &optional beg end)
  (let ((pos (or beg 0)) (end (or end (length text))) (n 0))
    (while (and (< pos end) (string-match well-formed--word-regexp text pos) (< (match-beginning 0) end))
      (setq n (1+ n) pos (match-end 0)))
    n))

(defun well-formed--syllables (word)
  "Syllables in WORD, roughly: vowel groups, minus an English silent e."
  (let* ((w (downcase word))
         (n (let ((pos 0) (c 0))
              (while (string-match "[aeiouyäöü]+" w pos)
                (setq c (1+ c) pos (match-end 0)))
              c)))
    (when (and (> n 1) (string-match-p "[^aeiouyl]e\\'" w)) (setq n (1- n)))
    (max 1 n)))

(defconst well-formed--stopwords
  '(("en" "the" "and" "is" "of" "to" "in" "that" "it" "not" "with" "for" "this" "are" "was" "be" "on" "as" "you" "have")
    ("de" "der" "die" "das" "und" "ist" "nicht" "ein" "eine" "zu" "mit" "auf" "für" "sich" "den" "dem" "ich" "es" "auch" "wird")))

(defun well-formed--detect-language (text)
  "\"en\" or \"de\" by stopwords, or nil when TEXT has too few."
  (let ((case-fold-search t) (scores nil))
    (dolist (entry well-formed--stopwords)
      (let ((re (concat "\\<" (regexp-opt (cdr entry)) "\\>")) (pos 0) (n 0))
        (while (string-match re text pos) (setq n (1+ n) pos (match-end 0)))
        (push (cons (car entry) n) scores)))
    (setq scores (sort scores (lambda (a b) (> (cdr a) (cdr b)))))
    (when (>= (cdar scores) 2)
      (if (> (cdar scores) (cdadr scores)) (caar scores) nil))))

;;;; Matching helpers for rules

(defun well-formed--match-case (template replacement)
  "REPLACEMENT capitalized like TEMPLATE's first letter."
  (if (and (> (length template) 0) (> (length replacement) 0)
           (eq (get-char-code-property (aref template 0) 'general-category) 'Lu)
           (not (eq (get-char-code-property (aref replacement 0) 'general-category) 'Lu)))
      (concat (upcase (substring replacement 0 1)) (substring replacement 1))
    replacement))

(defun well-formed--normalize (s)
  (downcase (replace-regexp-in-string "[[:space:]\0]+" " " s)))

(defun well-formed-phrases (table message &optional case-sensitive)
  "A rule function for TABLE, ((PHRASE . REPLACEMENT-OR-REPLACEMENTS) ...).
MESSAGE is a format string given the match and the first replacement
\(\"\" deletes the phrase)."
  (let* ((map (make-hash-table :test #'equal))
         (re (progn
               (dolist (e table) (puthash (downcase (car e)) (cdr e) map))
               (replace-regexp-in-string
                " " "[[:space:]]+"
                (concat "\\<" (regexp-opt (mapcar #'car table) t) "\\>") t t))))
    (lambda (para)
      (let ((text (well-formed-para-text para)) (case-fold-search (not case-sensitive))
            (pos 0) out)
        (with-syntax-table well-formed--syntax-table
          (while (string-match re text pos)
            (let* ((b (match-beginning 0)) (e (match-end 0)) (m (match-string 0 text))
                   (repl (gethash (well-formed--normalize m) map))
                   (repls (if (listp repl) repl (list repl))))
              (push (list b e (format message m (car repls))
                          (mapcar (lambda (r) (well-formed--match-case m r)) repls))
                    out)
              (setq pos e))))
        (nreverse out)))))

(defun well-formed--expand (template string)
  "TEMPLATE with \\N replaced by group N of the last match in STRING."
  (let ((md (match-data)) (pos 0) (out ""))
    (while (string-match "\\\\\\([0-9]\\)" template pos)
      (let ((n (string-to-number (match-string 1 template))) (b (match-beginning 0)) (e (match-end 0)))
        (setq out (concat out (substring template pos b)
                          (save-match-data (set-match-data md) (or (match-string n string) "")))
              pos e)))
    (set-match-data md)
    (concat out (substring template pos))))

(defun well-formed-regexps (table)
  "A rule function for TABLE, ((REGEXP MESSAGE FIX GROUP CASE-SENSITIVE) ...).
FIX is a string with \\N references, a function of the match, or nil;
GROUP (default 0) is what's marked and replaced."
  (lambda (para)
    (let ((text (well-formed-para-text para)) out)
      (with-syntax-table well-formed--syntax-table
        (pcase-dolist (`(,re ,msg ,fix ,group ,cs) table)
          (let ((case-fold-search (not cs)) (pos 0) (g (or group 0)))
            (while (and (< pos (length text)) (string-match re text pos))
              (let* ((b (match-beginning g)) (e (match-end g))
                     (m (match-string g text))
                     (repl (cond ((stringp fix)
                                  (well-formed--match-case m (well-formed--expand fix text)))
                                 ((functionp fix) (save-match-data (funcall fix m)))))
                     (message (if (functionp msg) (save-match-data (funcall msg m repl)) (format msg m repl))))
                (push (list b e message (and repl (list repl))) out)
                (setq pos (max (1+ (match-beginning 0)) (match-end 0))))))))
      (nreverse out))))

(defun well-formed-quote (s)
  (concat "“" (string-trim (replace-regexp-in-string "[[:space:]\0]+" " " s)) "”"))

;;;; Checking

(defvar-local well-formed--cache nil "Paragraph text → findings.")
(defvar-local well-formed--findings nil
  "The last check's findings: list of (BEG END RULE LEVEL MESSAGE FIXES ORIGINAL).")
(defvar-local well-formed--doc nil "The last check's per-document facts (for reports).")
(defvar-local well-formed--tick nil)

(defvar well-formed--ignored nil "Loaded ignore data: plist :rules (IDS) :files ((FILE IDS OCCURRENCES)).")

(defun well-formed--ignore-data ()
  (or well-formed--ignored
      (setq well-formed--ignored
            (or (and (file-readable-p well-formed-ignore-file)
                     (ignore-errors
                       (with-temp-buffer
                         (insert-file-contents well-formed-ignore-file)
                         (read (current-buffer)))))
                (list :rules nil :files nil)))))

(defun well-formed--save-ignore-data ()
  (make-directory (file-name-directory well-formed-ignore-file) t)
  (with-temp-file well-formed-ignore-file
    (let ((print-length nil) (print-level nil))
      (prin1 well-formed--ignored (current-buffer)))))

(defun well-formed--buffer-key ()
  (or buffer-file-name (buffer-name)))

(defvar-local well-formed--local-ignores nil
  "Ignores for buffers without files: (RULES . OCCURRENCES).")

(defun well-formed--file-ignores ()
  "(RULES . OCCURRENCES) ignored in this buffer; OCCURRENCES are (RULE . TEXT)."
  (if buffer-file-name
      (let ((entry (assoc buffer-file-name (plist-get (well-formed--ignore-data) :files))))
        (cons (nth 1 entry) (nth 2 entry)))
    well-formed--local-ignores))

(defun well-formed--document-settings ()
  "Style and language the document asks for: (STYLE-SYMBOL . LANG)."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t) style lang
            (limit (min (point-max) 4000)))
        (when (re-search-forward "^\\(?:#\\+\\)?well_formed:[ \t]*\\([a-z]+\\)" limit t)
          (setq style (intern (downcase (match-string 1)))))
        (goto-char (point-min))
        (when (re-search-forward "^#\\+language:[ \t]*\\([a-z]\\{2\\}\\)" limit t)
          (setq lang (downcase (match-string 1))))
        (cons (if (assq style well-formed-styles) style well-formed-style)
              (or well-formed-language
                  (and (member lang '("en" "de")) lang)))))))

(defun well-formed--paragraphs (text base)
  "Split masked TEXT (starting at buffer position BASE) into paragraphs:
\(BEG KIND STRING), split at blank or fully masked lines, list items
and headings (each its own)."
  (let ((pos 0) (len (length text)) (cur-beg nil) (cur-kind nil) out
        ;; Markup is masked in TEXT, so headings and items are recognized in
        ;; the buffer's own text.
        (heading-re (cond ((derived-mode-p 'org-mode) "\\*+ ")
                          ((derived-mode-p 'markdown-mode) "#+ ")))
        (item-re "[ \t]*\\(?:[-+]\\|[ \t]+\\*\\|\\*\\|[0-9]+[.)]\\|[a-z][.)]\\) "))
    (cl-flet ((flush (end)
                (when cur-beg
                  (let ((s (substring text cur-beg end)))
                    (when (string-match-p "[[:alpha:]]" s)
                      (push (list (+ base cur-beg) cur-kind s) out)))
                  (setq cur-beg nil)))
              (source-looking-at (re)
                (save-excursion (goto-char (+ base pos)) (looking-at re))))
      (while (< pos len)
        (let* ((eol (or (string-search "\n" text pos) len))
               (line (substring text pos eol)))
          (cond
           ((not (string-match-p "[^[:space:]\0]" line)) (flush pos))
           ((and heading-re (source-looking-at heading-re))
            (flush pos) (setq cur-beg pos cur-kind 'heading) (flush eol))
           ((source-looking-at item-re)
            ;; A list item (its bullet masked): its own paragraph.
            (flush pos) (setq cur-beg pos cur-kind 'item))
           ((null cur-beg) (setq cur-beg pos cur-kind 'prose)))
          (setq pos (1+ eol))))
      (flush len))
    (nreverse out)))

(defun well-formed--rule-level (rule style)
  (or (alist-get (well-formed-rule-id rule) (plist-get style :level))
      (well-formed-rule-level rule)))

(defun well-formed--active-rules (lang style)
  (let ((off (plist-get style :off)))
    (cl-remove-if-not
     (lambda (r)
       (and (member lang (well-formed-rule-langs r))
            (not (memq (well-formed-rule-id r) off))
            (not (memq (well-formed-rule-id r) well-formed-disabled-rules))
            (not (memq (well-formed-rule-category r) well-formed-disabled-categories))))
     (reverse well-formed--rules))))

(defun well-formed--check-para (para)
  "Findings in PARA: (RELBEG RELEND RULE-ID MESSAGE FIXES)."
  (let (out)
    (dolist (rule (well-formed--active-rules (well-formed-para-lang para) (well-formed-para-style para)))
      (condition-case err
          (dolist (f (funcall (well-formed-rule-function rule) para))
            (push (list (nth 0 f) (nth 1 f) (well-formed-rule-id rule) (nth 2 f) (nth 3 f)) out))
        (error (message "well-formed: rule %s failed: %S" (well-formed-rule-id rule) err))))
    (nreverse out)))

(defvar well-formed-document-functions nil
  "Functions of (PARAS) run after paragraphs are checked, for findings
that need the whole document (consistency).  Each returns findings
\(BEG END RULE-ID MESSAGE FIXES) in buffer positions.")

(defun well-formed--build-paras (beg end)
  (let* ((settings (well-formed--document-settings))
         (style (cons :name (cons (car settings) (alist-get (car settings) well-formed-styles))))
         (text (well-formed--masked-text beg end))
         (raw (well-formed--paragraphs text beg))
         (fallback (or (cdr settings) (well-formed--detect-language text) "en")))
    (mapcar (lambda (p)
              (pcase-let ((`(,pbeg ,kind ,s) p))
                (well-formed--make-para
                 :beg pbeg :text s :kind kind :style style
                 :lang (or (cdr settings) (well-formed--detect-language s) fallback)
                 :sentences (if (eq kind 'heading) (list (cons 0 (length (string-trim-right s))))
                              (well-formed--sentences s)))))
            raw)))

(defun well-formed-check (&optional beg end)
  "Check the buffer (BEG..END); return findings, cache them in the buffer.
Findings are (BEG END RULE LEVEL MESSAGE FIXES ORIGINAL)."
  (let* ((beg (or beg (point-min))) (end (or end (point-max)))
         (paras (save-restriction (widen) (well-formed--build-paras beg end)))
         (cache (or well-formed--cache (setq well-formed--cache (make-hash-table :test #'equal))))
         (fresh (make-hash-table :test #'equal))
         (ignores (well-formed--file-ignores))
         (global-off (plist-get (well-formed--ignore-data) :rules))
         raw)
    (dolist (p paras)
      (let* ((key (list (well-formed-para-text p) (well-formed-para-lang p)
                        (well-formed-para-kind p) (plist-get (well-formed-para-style p) :name)
                        well-formed-disabled-rules well-formed-disabled-categories))
             (hit (gethash key cache :miss))
             (found (if (eq hit :miss) (well-formed--check-para p) hit)))
        (puthash key found fresh)
        (dolist (f found)
          (push (list (+ (well-formed-para-beg p) (nth 0 f)) (+ (well-formed-para-beg p) (nth 1 f))
                      (nth 2 f) (nth 3 f) (nth 4 f))
                raw))))
    (setq well-formed--cache fresh)
    (dolist (fn well-formed-document-functions)
      (setq raw (nconc (funcall fn paras) raw)))
    (setq well-formed--doc (list :paras paras))
    (setq well-formed--findings
          (sort
           (cl-loop for (b e id msg fixes) in raw
                    for rule = (well-formed--rule id)
                    for original = (buffer-substring-no-properties b e)
                    unless (or (memq id global-off) (memq id well-formed-disabled-rules) (memq id (car ignores))
                               (member (cons id original) (cdr ignores)))
                    collect (list b e id
                                  (well-formed--rule-level rule (well-formed-para-style (car paras)))
                                  msg fixes original))
           (lambda (a b) (< (car a) (car b)))))))

(defun well-formed--check-quietly ()
  "`well-formed-check', abandoned when a key is pressed; nil then."
  (unless (> (buffer-size) well-formed-max-buffer-size)
    (let ((result (while-no-input (well-formed-check))))
      (unless (eq result t) result))))

;;;; Mode

(defcustom well-formed-modes '(org-mode markdown-mode gfm-mode text-mode git-commit-mode
                               message-mode mu4e-compose-mode rst-mode LaTeX-mode latex-mode)
  "Major modes (and their derivatives) `global-well-formed-mode' checks."
  :type '(repeat symbol))

;;;###autoload
(define-minor-mode well-formed-mode
  "Check prose as you write: correctness, clarity, engagement, delivery,
consistency.  Findings show through flycheck or flymake."
  :lighter " WF"
  (cond
   ((not well-formed-mode)
    (setq well-formed--cache nil well-formed--findings nil)
    (when (bound-and-true-p flymake-mode)
      (remove-hook 'flymake-diagnostic-functions #'well-formed-flymake t)))
   ((featurep 'flycheck)
    (put 'well-formed 'flycheck-modes (cl-adjoin major-mode (get 'well-formed 'flycheck-modes)))
    ;; flycheck may have found no checker before this mode was on (its
    ;; predicate is this mode); ask it again.
    (unless (bound-and-true-p flycheck-mode)
      (when (funcall 'flycheck-may-enable-mode) (funcall 'flycheck-mode 1)))
    (when (bound-and-true-p flycheck-mode) (funcall 'flycheck-buffer)))
   ((fboundp 'flymake-mode)
    (add-hook 'flymake-diagnostic-functions #'well-formed-flymake nil t)
    (unless (bound-and-true-p flymake-mode) (funcall 'flymake-mode 1)))))

(defun well-formed--turn-on ()
  (when (and (apply #'derived-mode-p well-formed-modes)
             (not (minibufferp))
             (not (string-prefix-p " " (buffer-name))))
    (well-formed-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-well-formed-mode well-formed-mode well-formed--turn-on)

;;;; flycheck

(declare-function flycheck-define-generic-checker "ext:flycheck" (symbol docstring &rest properties))
(declare-function flycheck-error-new-at-pos "ext:flycheck" (pos level message &rest args))
(declare-function flycheck-error-new "ext:flycheck" (&rest args))
(declare-function flycheck-add-next-checker "ext:flycheck" (checker next &optional append))
(declare-function flycheck-valid-checker-p "ext:flycheck" (checker))
(defvar flycheck-checkers)
(declare-function flycheck-buffer "ext:flycheck" ())
(declare-function flycheck-mode "ext:flycheck" (&optional arg))
(declare-function flycheck-may-enable-mode "ext:flycheck" ())

(defun well-formed--flycheck-start (checker callback)
  (let ((found (condition-case err (well-formed--check-quietly)
                 (error (funcall callback 'errored (error-message-string err)) :failed))))
    (cond
     ((eq found :failed))
     ((and (null found) (input-pending-p)) (funcall callback 'interrupted))
     (t (funcall callback 'finished
                 (mapcar (lambda (f)
                           (pcase-let ((`(,b ,e ,id ,level ,msg . ,_) f))
                             (save-excursion
                               (goto-char b)
                               (flycheck-error-new
                                :buffer (current-buffer) :checker checker
                                :filename buffer-file-name
                                :line (line-number-at-pos b) :column (1+ (current-column))
                                :end-line (line-number-at-pos e)
                                :end-column (progn (goto-char e) (1+ (current-column)))
                                :message msg :level level :id (symbol-name id)))))
                         found))))))

(with-eval-after-load 'flycheck
  (flycheck-define-generic-checker 'well-formed
    "Prose: correctness, clarity, engagement, delivery, consistency (well-formed)."
    :start #'well-formed--flycheck-start
    ;; flycheck matches the major mode exactly; `well-formed-mode' adds its
    ;; buffer's mode to these.
    :modes '(text-mode org-mode markdown-mode gfm-mode)
    :predicate (lambda () (bound-and-true-p well-formed-mode)))
  (add-to-list 'flycheck-checkers 'well-formed t)
  ;; After the mode's own checker, whatever it found.
  (dolist (checker '(+org-lint markdown-markdownlint-cli markdown-markdownlint-cli2 markdown-mdl
                     proselint textlint tex-chktex))
    (when (flycheck-valid-checker-p checker)
      (ignore-errors (flycheck-add-next-checker checker '(t . well-formed) t)))))

;;;; flymake

(declare-function flymake-make-diagnostic "flymake" (locus beg end type text &optional data overlay-properties))

(defun well-formed-flymake (report-fn &rest _)
  "A flymake backend for well-formed."
  (let ((found (well-formed--check-quietly)))
    (funcall report-fn
             (mapcar (lambda (f)
                       (pcase-let ((`(,b ,e ,_id ,level ,msg . ,_) f))
                         (flymake-make-diagnostic (current-buffer) b e
                                                  (pcase level ('error :error) ('warning :warning) (_ :note))
                                                  msg)))
                     found))))

;;;; Commands

(defun well-formed--ensure-findings ()
  (unless (and well-formed--findings (eq well-formed--tick (buffer-chars-modified-tick)))
    (well-formed-check)
    (setq well-formed--tick (buffer-chars-modified-tick)))
  well-formed--findings)

(defun well-formed--at (pos)
  "Findings covering POS (or touching it)."
  (cl-remove-if-not (lambda (f) (and (<= (nth 0 f) pos) (<= pos (nth 1 f))))
                    (well-formed--ensure-findings)))

(defun well-formed--current (&optional prompt)
  "The finding at point; ask when several overlap."
  (let ((here (well-formed--at (point))))
    (cond ((null here) (user-error "No well-formed finding here"))
          ((null (cdr here)) (car here))
          (t (let ((choices (mapcar (lambda (f) (cons (nth 4 f) f)) here)))
               (cdr (assoc (completing-read (or prompt "Which finding: ") choices nil t) choices)))))))

(defun well-formed--apply (finding replacement)
  "Replace FINDING's text with REPLACEMENT if it's still there."
  (pcase-let ((`(,b ,e ,_ ,_ ,_ ,_ ,original) finding))
    (unless (equal (buffer-substring-no-properties b e) original)
      (user-error "The text changed since it was checked"))
    (save-excursion
      (goto-char b)
      (delete-region b e)
      (if (string-empty-p replacement)
          ;; Deleting a phrase: one of the spaces around it goes too.
          (cond ((and (memq (char-after) '(?\s)) (memq (char-before) '(?\s nil ?\n)))
                 (delete-char 1))
                ((memq (char-before) '(?\s)) (delete-char -1)))
        (insert replacement)))
    (setq well-formed--tick nil)))

;;;###autoload
(defun well-formed-fix ()
  "Apply the suggestion for the finding at point (choose when there are several)."
  (interactive)
  (let* ((f (well-formed--current "Fix which: "))
         (fixes (nth 5 f)))
    (unless fixes (user-error "%s (no automatic fix)" (nth 4 f)))
    (well-formed--apply f (if (cdr fixes)
                              (completing-read (format "%s → " (nth 6 f)) fixes nil t)
                            (car fixes)))
    (when (and (featurep 'flycheck) (bound-and-true-p flycheck-mode)) (funcall 'flycheck-buffer))))

;;;###autoload
(defun well-formed-fix-all (rule)
  "Walk the buffer's findings of RULE, applying each fix you accept."
  (interactive
   (let* ((found (well-formed--ensure-findings))
          (ids (delete-dups (cl-loop for f in found when (nth 5 f) collect (symbol-name (nth 2 f))))))
     (unless ids (user-error "Nothing here has an automatic fix"))
     (list (intern (completing-read "Fix all of rule: " ids nil t nil nil
                                    (when-let* ((f (car (well-formed--at (point)))))
                                      (symbol-name (nth 2 f))))))))
  (let ((n 0))
    ;; From the end, so earlier positions stay valid.
    (dolist (f (reverse (cl-remove-if-not (lambda (f) (and (eq (nth 2 f) rule) (nth 5 f)))
                                          (well-formed--ensure-findings))))
      (goto-char (car f))
      (let ((ov (make-overlay (nth 0 f) (nth 1 f))))
        (overlay-put ov 'face 'highlight)
        (unwind-protect
            (when (y-or-n-p (format "%s  →  %s? " (nth 6 f) (car (nth 5 f))))
              (well-formed--apply f (car (nth 5 f)))
              (cl-incf n))
          (delete-overlay ov))))
    (message "well-formed: %d fixed" n)))

;;;###autoload
(defun well-formed-ignore (scope)
  "Ignore the finding at point: SCOPE is `here' (this text in this
document), `rule' (the rule in this document) or `everywhere'."
  (interactive
   (list (intern (completing-read "Ignore: " '("here" "rule" "everywhere") nil t))))
  (let* ((f (well-formed--current "Ignore which: "))
         (id (nth 2 f))
         (data (well-formed--ignore-data)))
    (pcase scope
      ('everywhere (plist-put data :rules (cl-adjoin id (plist-get data :rules))))
      (_ (if (not buffer-file-name)
             (let ((local (or well-formed--local-ignores (cons nil nil))))
               (if (eq scope 'rule) (push id (car local)) (push (cons id (nth 6 f)) (cdr local)))
               (setq well-formed--local-ignores local))
           (let* ((files (plist-get data :files))
                  (entry (or (assoc buffer-file-name files)
                             (car (push (list buffer-file-name nil nil) files)))))
             (if (eq scope 'rule)
                 (setf (nth 1 entry) (cl-adjoin id (nth 1 entry)))
               (setf (nth 2 entry) (cl-adjoin (cons id (nth 6 f)) (nth 2 entry) :test #'equal)))
             (plist-put data :files files)))))
    (setq well-formed--ignored data well-formed--tick nil)
    (well-formed--save-ignore-data)
    (when (and (featurep 'flycheck) (bound-and-true-p flycheck-mode)) (funcall 'flycheck-buffer))
    (message "well-formed: ignoring %s %s" id
             (pcase scope ('here (well-formed-quote (nth 6 f))) ('rule "in this document") (_ "everywhere")))))

;;;###autoload
(defun well-formed-unignore ()
  "Stop ignoring a rule or occurrence (this document's, or everywhere)."
  (interactive)
  (let* ((data (well-formed--ignore-data))
         (entry (and buffer-file-name (assoc buffer-file-name (plist-get data :files))))
         (choices (append (mapcar (lambda (id) (cons (format "everywhere: %s" id) (list :rules id)))
                                  (plist-get data :rules))
                          (mapcar (lambda (id) (cons (format "here: %s" id) (list :rule id))) (nth 1 entry))
                          (mapcar (lambda (o) (cons (format "here: %s %s" (car o) (well-formed-quote (cdr o)))
                                                    (list :occ o)))
                                  (nth 2 entry)))))
    (unless choices (user-error "Nothing is ignored"))
    (pcase (cdr (assoc (completing-read "Stop ignoring: " choices nil t) choices))
      (`(:rules ,id) (plist-put data :rules (delq id (plist-get data :rules))))
      (`(:rule ,id) (setf (nth 1 entry) (delq id (nth 1 entry))))
      (`(:occ ,o) (setf (nth 2 entry) (delete o (nth 2 entry)))))
    (well-formed--save-ignore-data)
    (setq well-formed--tick nil)
    (when (and (featurep 'flycheck) (bound-and-true-p flycheck-mode)) (funcall 'flycheck-buffer))))

(defun well-formed--describe-rule (id)
  (let ((rule (well-formed--rule id)))
    (with-help-window (help-buffer)
      (princ (format "%s  (%s, %s)\n\n" id (well-formed-rule-category rule) (well-formed-rule-level rule)))
      (princ (or (well-formed-rule-doc rule) "No description."))
      (princ "\n")
      (when (well-formed-rule-examples rule)
        (princ "\nExamples:\n")
        (pcase-dolist (`(,bad . ,good) (well-formed-rule-examples rule))
          (princ (format "  ✗ %s\n  ✓ %s\n\n" bad good))))
      (princ (format "\nLanguages: %s\n" (string-join (well-formed-rule-langs rule) ", ")))
      (princ "\nIgnore it here or everywhere: M-x well-formed-ignore."))))

;;;###autoload
(defun well-formed-explain (&optional id)
  "Explain the rule of the finding at point (or rule ID)."
  (interactive)
  (well-formed--describe-rule
   (or id (if-let* ((here (well-formed--at (point))))
              (nth 2 (if (cdr here) (well-formed--current "Explain which: ") (car here)))
            (intern (completing-read "Rule: " (mapcar (lambda (r) (symbol-name (well-formed-rule-id r)))
                                                      well-formed--rules)
                                     nil t))))))

;;;###autoload
(defun well-formed-next (&optional n)
  "Go to the Nth next finding."
  (interactive "p")
  (let* ((found (well-formed--ensure-findings))
         (pos (point))
         (target (if (> (or n 1) 0)
                     (cl-find-if (lambda (f) (> (car f) pos)) found)
                   (cl-find-if (lambda (f) (< (car f) pos)) (reverse found)))))
    (if (not target) (message "well-formed: no more findings")
      (goto-char (car target))
      (message "%s" (nth 4 target)))))

;;;###autoload
(defun well-formed-previous (&optional n)
  "Go to the Nth previous finding."
  (interactive "p")
  (well-formed-next (- (or n 1))))

(defconst well-formed-categories
  '((correctness . "Correctness") (clarity . "Clarity") (engagement . "Engagement")
    (delivery . "Delivery") (consistency . "Consistency")))

(declare-function consult--read "ext:consult" (table &rest options))
(declare-function consult--lookup-candidate "ext:consult" (selected candidates &rest _))
(declare-function consult--jump-state "ext:consult" ())

;;;###autoload
(defun well-formed-list ()
  "Every finding in the buffer, grouped by category; goes to the chosen one
\(with consult, previewed while you move)."
  (interactive)
  (let* ((found (well-formed--ensure-findings))
         (buf (current-buffer))
         (cands (mapcar (lambda (f)
                          (let* ((rule (well-formed--rule (nth 2 f)))
                                 (cat (well-formed-rule-category rule))
                                 (line (line-number-at-pos (car f))))
                            (propertize (format "%5d  %s" line (nth 4 f))
                                        'well-formed--group (alist-get cat well-formed-categories)
                                        'well-formed--finding f
                                        'face (pcase (nth 3 f) ('error 'error) ('warning 'warning) (_ 'shadow)))))
                        found)))
    (unless cands (user-error "well-formed: nothing to report here"))
    (let ((choice
           (if (require 'consult nil t)
               (consult--read cands
                              :prompt "Finding: " :sort nil :require-match t
                              :group (lambda (c transform)
                                       (if transform c (get-text-property 0 'well-formed--group c)))
                              :lookup #'consult--lookup-candidate
                              :state (let ((jump (consult--jump-state)))
                                       (lambda (action cand)
                                         (funcall jump action
                                                  (and cand (set-marker (make-marker)
                                                                        (car (get-text-property 0 'well-formed--finding cand))
                                                                        buf))))))
             (completing-read "Finding: " cands nil t))))
      (when-let* ((f (and choice (get-text-property 0 'well-formed--finding
                                                    (or (car (member choice cands)) choice)))))
        (goto-char (car f))))))

(defun well-formed-set-style (style)
  "Use STYLE in this buffer."
  (interactive (list (intern (completing-read "Style: " (mapcar (lambda (s) (symbol-name (car s))) well-formed-styles)
                                              nil t))))
  (setq-local well-formed-style style)
  (setq well-formed--tick nil)
  (when (and (featurep 'flycheck) (bound-and-true-p flycheck-mode)) (funcall 'flycheck-buffer))
  (message "well-formed: %s style here (a document keeps it with \"#+well_formed: %s\")" style style))

(defun well-formed-toggle-category (category)
  "Report CATEGORY or not, everywhere."
  (interactive (list (intern (completing-read "Toggle category: "
                                              (mapcar (lambda (c) (symbol-name (car c))) well-formed-categories)
                                              nil t))))
  (setq well-formed-disabled-categories
        (if (memq category well-formed-disabled-categories)
            (delq category well-formed-disabled-categories)
          (cons category well-formed-disabled-categories)))
  (setq well-formed--tick nil)
  (when (and (featurep 'flycheck) (bound-and-true-p flycheck-mode)) (funcall 'flycheck-buffer)))

;;;; Embark

(defvar embark-target-finders)
(defvar embark-keymap-alist)

(defun well-formed-embark-target ()
  "The well-formed finding at point, for embark."
  (when-let* (((bound-and-true-p well-formed-mode))
              (f (car (well-formed--at (point)))))
    `(well-formed ,(nth 6 f) ,(nth 0 f) . ,(nth 1 f))))

(defvar-keymap well-formed-embark-map
  :doc "Actions on a well-formed finding."
  "f" #'well-formed-fix
  "a" #'well-formed-fix-all
  "i" #'well-formed-ignore
  "e" #'well-formed-explain
  "l" #'well-formed-list)

(with-eval-after-load 'embark
  (add-to-list 'embark-target-finders #'well-formed-embark-target)
  (add-to-list 'embark-keymap-alist '(well-formed . well-formed-embark-map)))

(provide 'well-formed)
(require 'well-formed-rules)
;;; well-formed.el ends here
