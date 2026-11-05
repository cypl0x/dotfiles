;;; well-formed-ai.el --- A model's reading, on top of well-formed's rules -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;; well-formed's rules catch what rules can.  This layer asks a language
;; model (through familiar, Claude) about what they can't: whether a
;; sentence says what it means, fits the document's declared style and
;; audience, keeps its terms and naming consistent, uses Org well.
;;
;; Live (on by default, `well-formed-ai-mode'): when you pause, the
;; paragraphs you changed, only those, each once per text (cached), at
;; most `well-formed-ai-max-per-minute' a minute, go to the fast model with
;; the document's style.  What it finds shows as findings like the rules'
;; (flycheck checker `well-formed-ai', after `well-formed'), each quoting
;; the text exactly (so it can be found) and offering its rewrite as a fix:
;; SPC P x.
;;
;; The style: "#+well_formed: academic" picks a rules style; a free one
;; says anything a model understands: "#+well_formed_goal: a friendly
;; README for Emacs users who know Lisp".
;;
;; The report (`well-formed-ai-report', SPC P a): the smart model reads the
;; whole text and rates it honestly: how it leans (percentages of styles it
;; names itself: academic, storytelling, …), tone, audience, ratings with
;; reasons, strengths, the issues that matter most, naming and Org syntax
;; consistency.  Shown below well-formed's own report.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'well-formed)

(declare-function familiar-request "familiar" (prompt &rest args))




(declare-function flycheck-buffer "ext:flycheck" ())


(defcustom well-formed-ai-max-per-minute 6
  "Paragraph requests at most, per minute, across buffers."
  :type 'natnum :group 'well-formed)

(defcustom well-formed-ai-min-words 6
  "Paragraphs shorter than this aren't sent."
  :type 'natnum :group 'well-formed)

(defconst well-formed-ai-system
  "You are a meticulous editor.  You read one paragraph of a document and \
report only real problems: wrong or unclear wording, grammar, a sentence \
that doesn't say what the writer evidently means, a mismatch with the \
document's style and audience, inconsistent terms or naming, Org markup \
used wrongly.  Be honest and specific; never praise, never invent problems; \
an empty list is a good answer.  Don't report what a spell checker or \
simple rules catch (typos, doubled words, a/an, passive voice, long \
sentences): another tool does.  Keep the writer's language (German stays \
German) and voice.  Reply with JSON only: {\"issues\": [{\"quote\": \"the \
exact text from the paragraph, copied character for character, as short as \
possible\", \"issue\": \"what is wrong, one sentence\", \"category\": \
\"correctness|clarity|engagement|delivery|consistency\", \"severity\": \
\"error|warning|info\", \"fix\": \"replacement text for the quote, or \
empty\"}]}"
  "System prompt of the live paragraph review.")

(defconst well-formed-ai-report-system
  "You are a candid, experienced editor writing an assessment of a \
document for its author.  No flattery; ratings must be earned and \
justified; say plainly what doesn't work.  Reply with JSON only: \
{\"style_mix\": [{\"style\": \"a style you name (academic, technical, \
storytelling, conversational, persuasive, instructional, …)\", \
\"percent\": n}] (percentages adding to 100), \"tone\": \"a few words\", \
\"audience\": \"who it reads as written for\", \"fit\": \"how well it fits \
the declared style/goal if one is given, one sentence\", \"ratings\": \
[{\"aspect\": \"clarity|correctness|structure|concision|consistency|engagement\", \
\"score\": 0-10, \"why\": \"one sentence\"}], \"strengths\": [\"…\"], \
\"issues\": [{\"quote\": \"short exact quote\", \"issue\": \"what and why\", \
\"suggestion\": \"how\"}] (the most important, at most 8), \"naming\": \
\"consistency of terms and names, one or two sentences\", \"org\": \
\"use of Org structure and markup, one or two sentences\"}"
  "System prompt of the AI report.")

;;;; Live

(defvar well-formed-ai--cache (make-hash-table :test #'equal :size 512)
  "(GOAL . PARAGRAPH-TEXT) → issues (or :pending).")
(defvar well-formed-ai--sent nil "Times of recent requests.")
(defvar-local well-formed-ai--baseline nil
  "Paragraph texts the buffer had when first checked: not sent (only what
you change afterwards is; the report reads the whole text on demand).")

(defun well-formed-ai--goal ()
  "The document's style or goal, as words for the model."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t) goal)
        (when (re-search-forward "^\\(?:#\\+\\)?well_formed_goal:[ \t]*\\(.+\\)$" 4000 t)
          (setq goal (string-trim (match-string-no-properties 1))))
        (format "Declared style: %s.%s Mode: %s."
                (car (well-formed--document-settings))
                (if goal (format " Goal: %s." goal) "")
                major-mode)))))

(defun well-formed-ai--budget-p ()
  (let ((now (float-time)))
    (setq well-formed-ai--sent (seq-filter (lambda (s) (< (- now s) 60)) well-formed-ai--sent))
    (< (length well-formed-ai--sent) well-formed-ai-max-per-minute)))

(defun well-formed-ai--request (buf key text goal)
  (push (float-time) well-formed-ai--sent)
  (puthash key :pending well-formed-ai--cache)
  (familiar-request
   (format "%s\n\nParagraph:\n%s" goal text)
   :task 'writing-review :system well-formed-ai-system :silent t
   :callback
   (lambda (response _info)
     (let ((issues (and (stringp response)
                        (plist-get (ignore-errors
                                     (json-parse-string
                                      (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" response)
                                      :object-type 'plist :array-type 'list :null-object nil))
                                   :issues))))
       (puthash key (or issues '()) well-formed-ai--cache)
       (when (and (buffer-live-p buf) (bound-and-true-p flycheck-mode))
         (with-current-buffer buf
           (when (bound-and-true-p flycheck-mode) (flycheck-buffer))))))))

(defun well-formed-ai--findings ()
  "Findings from the cache for this buffer's paragraphs; ask for the missing
ones (within budget).  Each finding: (BEG END ID LEVEL MESSAGE FIXES)."
  (let ((goal (well-formed-ai--goal))
        ;; The paragraphs of the check this runs after (never a new check:
        ;; that runs this again).
        (paras (plist-get well-formed--doc :paras))
        (first (null well-formed-ai--baseline))
        out)
    (when first (setq well-formed-ai--baseline (make-hash-table :test #'equal)))
    (dolist (p paras)
      (let* ((beg (well-formed-para-beg p))
             (text (buffer-substring-no-properties beg (+ beg (length (well-formed-para-text p)))))
             (key (cons goal text))
             (hit (gethash key well-formed-ai--cache 'none)))
        (cond
         ((or (eq (well-formed-para-kind p) 'heading)
              (< (well-formed--word-count (well-formed-para-text p)) well-formed-ai-min-words)))
         ((eq hit 'none)
          (when first (puthash text t well-formed-ai--baseline))
          (when (and (not (gethash text well-formed-ai--baseline)) (well-formed-ai--budget-p))
            (well-formed-ai--request (current-buffer) key text goal)))
         ((listp hit)
          (dolist (i hit)
            (let* ((quote (plist-get i :quote))
                   (pos (and (stringp quote) (not (string-empty-p quote)) (string-search quote text))))
              (when pos
                (push (list (+ beg pos) (+ beg pos (length quote)) 'ai
                            (pcase (plist-get i :severity) ("error" 'error) ("info" 'info) (_ 'warning))
                            (format "%s (AI)" (plist-get i :issue))
                            (let ((fix (plist-get i :fix)))
                              (and (stringp fix) (not (string-empty-p fix)) (not (equal fix quote))
                                   (list fix))))
                      out))))))))
    (nreverse out)))

(well-formed-define-rule ai
  :category 'clarity :level 'warning
  :doc "What a language model, reading the paragraph with the document's
declared style (#+well_formed / #+well_formed_goal), found: unclear or
wrong wording, a mismatch with the style or audience, inconsistent terms,
Org used wrongly.  Its rewrite is the fix."
  :function #'ignore)

;;;###autoload
(define-minor-mode well-formed-ai-mode
  "A language model reads changed paragraphs as you pause (see the file)."
  :global t :group 'well-formed)

;; The AI findings join well-formed's own, after each check: flycheck shows
;; them with the rest (rule `ai'), SPC P x fixes them, ignoring works as for
;; any rule.  When an answer arrives, flycheck checks again.
(defun well-formed-ai--merge (found)
  (if (not (and well-formed-ai-mode (bound-and-true-p well-formed-mode)))
      found
    (let* ((ignores (well-formed--file-ignores))
           (off (or (memq 'ai well-formed-disabled-rules)
                    (memq 'ai (car ignores))
                    (memq 'ai (plist-get (well-formed--ignore-data) :rules))))
           (ai (unless off
                 (cl-loop for f in (ignore-errors (well-formed-ai--findings))
                          for original = (buffer-substring-no-properties (nth 0 f) (nth 1 f))
                          unless (member (cons 'ai original) (cdr ignores))
                          collect (append f (list original))))))
      (setq well-formed--findings
            (sort (append found ai) (lambda (a b) (< (car a) (car b))))))))

(advice-add 'well-formed-check :filter-return #'well-formed-ai--merge)

;;;; Report

(defun well-formed-ai--bar (fraction width)
  (let* ((eighths (round (* 8 width (max 0 (min 1 fraction))))))
    (concat (make-string (/ eighths 8) ?█)
            (if (> (% eighths 8) 0) (string (aref " ▏▎▍▌▋▊▉" (% eighths 8))) ""))))

;;;###autoload
(defun well-formed-ai-report ()
  "The smart model's candid assessment of the buffer (or region)."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg (min end (+ beg 60000))))
         (goal (well-formed-ai--goal))
         (name (buffer-name)))
    (message "well-formed: asking for an assessment…")
    (familiar-request
     (format "%s\n\nDocument (%s):\n%s" goal name text)
     :task 'writing-report :escalate t :system well-formed-ai-report-system
     :callback
     (lambda (response _info)
       (let ((a (and (stringp response)
                     (ignore-errors
                       (json-parse-string (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" response)
                                          :object-type 'plist :array-type 'list :null-object nil)))))
         (if (not a)
             (message "well-formed: no assessment (%s)" (if (stringp response) "unreadable answer" "no answer"))
           (with-current-buffer (get-buffer-create "*well-formed AI report*")
             (let ((inhibit-read-only t))
               (erase-buffer)
               (insert (propertize (format "%s, as an editor reads it\n" name) 'face '(:weight bold :height 1.2))
                       (propertize (format "%s\n\n" goal) 'face 'shadow))
               (insert (propertize "How it leans\n" 'face 'font-lock-keyword-face))
               (dolist (s (plist-get a :style_mix))
                 (insert (format "  %-18s %3d%% " (plist-get s :style) (or (plist-get s :percent) 0))
                         (propertize (well-formed-ai--bar (/ (or (plist-get s :percent) 0) 100.0) 30) 'face 'success) "\n"))
               (insert (format "\n  Tone: %s\n  Reads as written for: %s\n" (plist-get a :tone) (plist-get a :audience)))
               (when (plist-get a :fit) (insert (format "  Fit with the declared style: %s\n" (plist-get a :fit))))
               (insert "\n" (propertize "Ratings\n" 'face 'font-lock-keyword-face))
               (dolist (r (plist-get a :ratings))
                 (let ((score (or (plist-get r :score) 0)))
                   (insert (format "  %-12s %2d/10 " (plist-get r :aspect) score)
                           (propertize (well-formed-ai--bar (/ score 10.0) 10)
                                       'face (cond ((>= score 8) 'success) ((>= score 5) 'warning) (t 'error)))
                           (format "  %s\n" (plist-get r :why)))))
               (when (plist-get a :strengths)
                 (insert "\n" (propertize "Strengths\n" 'face 'font-lock-keyword-face))
                 (dolist (s (plist-get a :strengths)) (insert "  + " s "\n")))
               (when (plist-get a :issues)
                 (insert "\n" (propertize "What matters most\n" 'face 'font-lock-keyword-face))
                 (dolist (i (plist-get a :issues))
                   (insert (format "  - “%s”\n    %s\n    → %s\n"
                                   (plist-get i :quote) (plist-get i :issue) (plist-get i :suggestion)))))
               (insert "\n" (propertize "Naming\n" 'face 'font-lock-keyword-face) "  " (or (plist-get a :naming) "") "\n"
                       "\n" (propertize "Org\n" 'face 'font-lock-keyword-face) "  " (or (plist-get a :org) "") "\n")
               (goto-char (point-min))
               (special-mode))
             (display-buffer (current-buffer)))))))))

(provide 'well-formed-ai)
;;; well-formed-ai.el ends here
