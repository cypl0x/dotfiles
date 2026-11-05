;;; lisp/+format.el --- SPC c f formats, Org included -*- lexical-binding: t; -*-
;;
;; With Doom's :editor format off, SPC c f pointed at an undefined command.
;; Now it formats the region or buffer by what the buffer is:
;;
;;   Org         `+format-org': blank lines by convention (below), lower-case
;;               #+keywords, align tables and tags, repair lists (indent,
;;               numbering), update statistics cookies, drop trailing blanks.
;;               C-u: the canonical form Org's own parser prints back
;;               (`org-element-interpret-data'), shown as a diff first.
;;   eglot       the language server's formatter
;;   otherwise   re-indent
;;
;;; Code:

(declare-function org-table-map-tables "org-table" (f &optional quietly))
(declare-function org-table-align "org-table" ())
(declare-function org-list-repair "org-list" ())
(declare-function org-at-item-p "org" ())
(declare-function org-update-statistics-cookies "org" (all))
(declare-function org-align-tags "org" (&optional all))
(declare-function org-element-parse-buffer "org-element" (&optional granularity visible-only keep-deferred))
(declare-function org-element-interpret-data "org-element" (data))
(declare-function org-element-at-point "org-element" (&optional epom cached-only))
(declare-function org-element-lineage "org-element-ast" (datum &optional types with-self))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))
(declare-function org-element-map "org-element" (data types fun &optional info first-match no-recursion with-affiliated))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-element-contents "org-element-ast" (node))
(defvar org-src-preserve-indentation)
(declare-function eglot-managed-p "eglot" ())
(declare-function eglot-format "eglot" (&optional beg end on-type-format))
(declare-function eglot-server-capable "eglot" (&rest feats))

;; Blank lines, by two conventions already in use rather than a new one:
;; alphapapa's `unpackaged/org-fix-blank-lines' (a blank line between
;; headings, and between a heading's planning/drawers and its text) and
;; markdownlint's (MD012: no runs of blank lines; MD022, MD031, MD032:
;; headings, blocks, tables and lists set apart by one).  Blank lines inside
;; blocks are their content and stay; a heading keeps its planning line and
;; drawers right under it (Org needs them there).
(defconst +format-org-set-apart
  '(table plain-list src-block example-block quote-block center-block
    special-block export-block verse-block dynamic-block fixed-width)
  "Elements with a blank line before and after them.")

(defconst +format-org-verbatim
  '(src-block example-block export-block verse-block comment-block fixed-width)
  "Elements whose blank lines are their content.")

(defun +format-org--blank-before (pos)
  "Make it exactly one blank line before the line at POS (none at the start)."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (let ((end (point)))
      (skip-chars-backward " \t\n")
      (unless (bobp)
        (forward-line 1)
        (delete-region (point) end)
        (insert "\n")))))

(defun +format-org--blank-positions ()
  "Where a blank line goes: before each heading, before each top-level
element set apart (and after it: before what follows), before a section's
text after the heading's planning and drawers."
  (let (positions)
    (org-element-map (org-element-parse-buffer 'element) '(headline section)
      (lambda (el)
        (if (eq (org-element-type el) 'headline)
            (push (org-element-property :begin el) positions)
          (let* ((kids (org-element-contents el))
                 (meta (and (eq (org-element-type (org-element-property :parent el)) 'headline)
                            (seq-take-while (lambda (k) (memq (org-element-type k)
                                                              '(planning property-drawer drawer)))
                                            kids)))
                 (body (nthcdr (length meta) kids)))
            ;; Text under a heading: a blank line between it and the heading.
            (when (and body (eq (org-element-type (org-element-property :parent el)) 'headline))
              (push (org-element-property :begin (car body)) positions))
            (cl-loop for (k next) on body
                     when (memq (org-element-type k) +format-org-set-apart)
                     do (push (org-element-property :begin k) positions)
                     (when next (push (org-element-property :begin next) positions)))))))
    (sort (delete-dups positions) #'>)))

(defun +format-org-blank-lines ()
  "Blank lines by the conventions above, in the accessible part."
  (let ((verbatim
         ;; Inside a block, not in the blank lines after it (its post-blank).
         (lambda ()
           (let ((el (org-element-at-point)) (pos (point)))
             (and (memq (org-element-type el) +format-org-verbatim)
                  (< pos (save-excursion (goto-char (org-element-property :end el))
                                         (skip-chars-backward " \t\n")
                                         (point))))))))
    ;; Runs of blank lines outside blocks: one.
    (save-excursion
      (goto-char (point-min))
      ;; Forward: a match is then a whole run (backward, one could start
      ;; inside a run and leave two blank lines).
      (while (re-search-forward "\n\\(?:[ \t]*\n\\)\\{2,\\}" nil t)
        (unless (save-match-data
                  (save-excursion (goto-char (1+ (match-beginning 0))) (funcall verbatim)))
          (replace-match "\n\n" t t))))
    (dolist (pos (+format-org--blank-positions))
      (+format-org--blank-before pos))
    ;; Org writes its keywords and block delimiters in lower case (since 9);
    ;; a block's own lines are its content.
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search nil))
        (while (re-search-forward "^[ \t]*#\\+\\(\\(?:BEGIN\\|END\\)_[A-Za-z]+\\|[A-Z_]+:\\)" nil t)
          (let* ((el (save-match-data (org-element-at-point)))
                 (bol (line-beginning-position))
                 (first (save-excursion (goto-char (org-element-property :post-affiliated el))
                                        (line-end-position)))
                 (last (save-excursion (goto-char (org-element-property :end el))
                                       (skip-chars-backward " \t\n")
                                       (line-beginning-position))))
            ;; Not a line between a block's delimiters.
            (unless (and (memq (org-element-type el) +format-org-verbatim)
                         (> bol first) (< bol last))
              (replace-match (downcase (match-string 1)) t t nil 1))))))
    ;; One newline at the end of the buffer (not of a region).
    (when (= (point-max) (1+ (buffer-size)))
      (save-excursion
        (goto-char (point-max))
        (skip-chars-backward " \t\n")
        (delete-region (point) (point-max))
        (insert "\n")))))

(defun +format-org (&optional beg end)
  "Tidy Org between BEG and END (default: the whole buffer), in place."
  (let ((beg (copy-marker (or beg (point-min))))
        (end (copy-marker (or end (point-max)) t)))
    (save-excursion
      (save-restriction
        (narrow-to-region beg end)
        (org-table-map-tables #'org-table-align t)
        ;; Each top-level list once: `org-list-repair' fixes the whole list.
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]" nil t)
          (when (org-at-item-p)
            (org-list-repair)
            (goto-char (org-element-property :end (org-element-lineage
                                                   (org-element-at-point)
                                                   '(plain-list) t)))))
        (org-update-statistics-cookies 'all)
        (org-align-tags t)
        (delete-trailing-whitespace)
        (+format-org-blank-lines)))
    (set-marker beg nil)
    (set-marker end nil)))

(defun +format-org-canonical ()
  "Org's parser printed back: the canonical form of this buffer's text."
  ;; Src block bodies keep their indentation; only the syntax around them changes.
  (let ((org-src-preserve-indentation t))
    (substring-no-properties
     (org-element-interpret-data (org-element-parse-buffer)))))

(defun +format-org-canonical-buffer ()
  "Replace the buffer by its canonical form, after showing the diff."
  (let ((new (+format-org-canonical))
        (scratch (generate-new-buffer " *org canonical*")))
    (unwind-protect
        (if (string= new (buffer-string))
            (message "Already canonical")
          (with-current-buffer scratch (insert new))
          (let ((diff (diff-buffers (current-buffer) scratch nil t)))
            (unwind-protect
                (progn
                  (display-buffer diff)
                  (when (y-or-n-p "Replace with the canonical form (undoable)? ")
                    ;; Minimal edits: markers, point and undo stay sensible.
                    (if (>= emacs-major-version 31)
                        (if (< emacs-major-version 31)
                            (replace-region-contents (point-min) (point-max) (lambda () scratch))
                          (replace-region-contents (point-min) (point-max) scratch))
                      (with-no-warnings (replace-buffer-contents scratch)))))
              (when (buffer-live-p diff) (kill-buffer diff)))))
      (kill-buffer scratch))))

;;;###autoload
(declare-function +lua-stylua "+lua" (beg end))
(defun +format/dwim (&optional canonical)
  "Format the region, else the buffer, by what the buffer is.
In Org with prefix arg CANONICAL, rewrite it in Org's canonical form."
  (interactive "P")
  (let ((beg (and (use-region-p) (region-beginning)))
        (end (and (use-region-p) (region-end))))
    (cond ((and (derived-mode-p 'lua-mode 'lua-ts-mode) (executable-find "stylua"))
           (+lua-stylua beg end)
           (message "stylua%s" (if beg " (region)" "")))
          ((derived-mode-p 'org-mode)
           (if canonical (+format-org-canonical-buffer) (+format-org beg end))
           (message "Org tidied%s" (if beg " (region)" "")))
          ((and (fboundp 'eglot-managed-p) (eglot-managed-p)
                (eglot-server-capable (if beg :documentRangeFormattingProvider
                                        :documentFormattingProvider)))
           (eglot-format beg end))
          (t (indent-region (or beg (point-min)) (or end (point-max)))))))

(map! :leader :desc "Format buffer/region" "c f" #'+format/dwim)

;;;; Prose

;; Paragraphs as you write them here: hard-wrapped at `fill-column' (77% of
;; the prose lines in ~/vault are 60-80 columns), one space after a sentence.
;;
;;   M-q, SPC P q   fill the paragraph; again: unfill it (one long line)
;;   SPC P L        one sentence per line (semantic line breaks: diffs and
;;                  reordering by line)
;;   SPC P P        join the paragraphs in the region into one
;;   SPC P p        split into paragraphs where the topic shifts (AI); applied
;;                  only if the words are unchanged, then each one filled

(declare-function familiar-request "familiar" (prompt &rest args))

(defvar +format-abbreviations
  '("e.g." "i.e." "etc." "vs." "cf." "approx." "Dr." "Mr." "Mrs." "Ms." "Prof." "St."
    "z.B." "d.h." "u.a." "bzw." "vgl." "usw." "ggf." "evtl." "ca." "inkl." "sog."
    "Nr." "S." "Abs." "Kap." "Hr." "Fr.")
  "Words ending in a full stop that don't end a sentence (English, German).")

(defun +format--paragraph-bounds ()
  "The region, else the paragraph at point: (BEG . END)."
  (cond
   ((use-region-p) (cons (region-beginning) (region-end)))
   ;; Org's paragraph motion stops at a list item's continuation lines.
   ((and (derived-mode-p 'org-mode)
         (eq (car-safe (org-element-at-point)) 'paragraph))
    (let ((el (org-element-at-point)))
      (cons (org-element-property :contents-begin el)
            (save-excursion (goto-char (org-element-property :contents-end el))
                            (skip-chars-backward " \t\n")
                            (point)))))
   (t
    (save-excursion
      (let ((end (progn (forward-paragraph) (point))))
        (backward-paragraph)
        (skip-chars-forward " \t\n")
        (cons (point) (progn (goto-char end) (skip-chars-backward " \t\n") (point))))))))

(defun +format--sentence-end-p (word)
  "Whether WORD ends a sentence."
  (and (string-match-p "[.!?…][]\"')»“”’*/=~_]*\\'" word)
       (not (member word +format-abbreviations))
       ;; Ordinals and dates ("am 3. Mai"), initials ("J. Doe").
       (not (string-match-p "\\`\\(?:[0-9]+\\|[[:alpha:]]\\)\\.\\'" word))))

(defun +format-sentences (text)
  "TEXT as a list of sentences, whitespace collapsed."
  (let (out cur)
    (dolist (w (split-string text "[ \t\n]+" t))
      (push w cur)
      (when (+format--sentence-end-p w)
        (push (string-join (nreverse cur) " ") out)
        (setq cur nil)))
    (when cur (push (string-join (nreverse cur) " ") out))
    (nreverse out)))

(defun +format--replace (beg end text)
  "Replace BEG..END with TEXT; its later lines indented like the first's text.
In a list item that is the item's text column, not the bullet's."
  (save-excursion
    (goto-char beg)
    (let ((indent (save-excursion
                    (beginning-of-line)
                    (if (looking-at "[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+")
                        (- (match-end 0) (point))
                      (current-indentation)))))
      (atomic-change-group
        (delete-region beg end)
        (insert (replace-regexp-in-string "\n\\(.\\)" (concat "\n" (make-string indent ?\s) "\\1")
                                          text t))
        (point)))))

;;;###autoload
(defun +format/fill-dwim ()
  "Fill the paragraph (or region); repeated, unfill it instead."
  (interactive)
  (if (eq last-command this-command)
      (let ((fill-column most-positive-fixnum))
        (setq this-command nil)           ; a third press fills again
        (fill-paragraph nil (use-region-p))
        (message "Unfilled"))
    (fill-paragraph nil (use-region-p))))

;;;###autoload
(defun +format/sentence-lines ()
  "Put each sentence of the paragraph (or region) on its own line."
  (interactive)
  (pcase-let ((`(,beg . ,end) (+format--paragraph-bounds)))
    (let ((sentences (+format-sentences (buffer-substring-no-properties beg end))))
      (+format--replace beg end (string-join sentences "\n"))
      (message "%d sentences" (length sentences)))))

;;;###autoload
(defun +format/join-paragraphs (beg end)
  "Join the paragraphs between BEG and END into one, filled."
  (interactive "r")
  (let ((text (string-join (split-string (buffer-substring-no-properties beg end)
                                         "[ \t\n]+" t)
                           " ")))
    (+format--replace beg end text)
    (save-excursion (goto-char beg) (fill-paragraph))))

(defun +format--fill-paragraphs (beg end)
  "Fill each paragraph between BEG and END."
  (save-excursion
    (goto-char beg)
    (let ((end (copy-marker end)))
      (while (< (point) end)
        (fill-paragraph)
        (forward-paragraph))
      (set-marker end nil))))

(defun +format-same-words-p (a b)
  "Whether strings A and B hold the same words in the same order."
  (equal (split-string a "[ \t\n]+" t) (split-string b "[ \t\n]+" t)))

;;;###autoload
(defun +format/split-paragraphs ()
  "Split the paragraph (or region) where the topic shifts, by asking a model.
Applied only if its answer keeps every word in order, so nothing but the
breaks can change; then each paragraph is filled."
  (interactive)
  (pcase-let* ((`(,beg . ,end) (+format--paragraph-bounds))
               (text (buffer-substring-no-properties beg end))
               (buf (current-buffer))
               (tick (buffer-chars-modified-tick)))
    (message "Asking where the paragraphs break…")
    (familiar-request
     (string-join (split-string text "[ \t\n]+" t) " ")
     :task 'format
     :system "Split the user's text into paragraphs where the topic or step \
of the argument shifts.  Return the same text: every word and punctuation \
mark unchanged and in order, one blank line between paragraphs, nothing else \
(no commentary, no code fence).  If it is one topic, return it unchanged."
     :callback
     (lambda (response _info)
       (cond
        ((not (stringp response)) (message "No answer; nothing changed"))
        ((not (buffer-live-p buf)))
        ((/= tick (buffer-chars-modified-tick buf))
         (message "The buffer changed meanwhile; nothing applied"))
        ((not (+format-same-words-p text response))
         (message "The answer changed words; nothing applied"))
        (t
         (with-current-buffer buf
           (let ((paras (mapcar (lambda (p) (string-join (split-string p "[ \t\n]+" t) " "))
                                (split-string (string-trim response) "\n[ \t]*\n" t))))
             (atomic-change-group
               (+format--fill-paragraphs
                beg (+format--replace beg end (string-join paras "\n\n"))))
             (message "%d paragraph%s" (length paras) (if (cdr paras) "s" ""))))))))))

(map! :leader
      (:prefix "P"
       :desc "Fill / unfill"         "q" #'+format/fill-dwim
       :desc "Sentence per line"     "L" #'+format/sentence-lines
       :desc "Split paragraphs (AI)" "p" #'+format/split-paragraphs
       :desc "Join paragraphs"       "P" #'+format/join-paragraphs)
      :map text-mode-map "M-q" #'+format/fill-dwim)


;;;; C-RET makes headings the way SPC c f leaves them ───────────────────────

;; Doom's C-RET / C-S-RET (+org/insert-item-below/-above) write the new
;; heading's stars themselves and so ignore `org-blank-before-new-entry';
;; SPC c f then put a blank line before every heading.  The two disagreed.
;; Now C-RET follows `org-blank-before-new-entry' (Org's own setting, also
;; used by M-RET), set to blank lines as the formatter writes them.
(defvar org-blank-before-new-entry)
(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(setq org-blank-before-new-entry '((heading . t) (plain-list-item . auto)))

(defun +format-org-heading-blank-a (fn direction &rest args)
  "After Doom inserts a heading (FN, DIRECTION): blank lines around it, when
`org-blank-before-new-entry' asks for them before headings."
  (progn
    (apply fn direction args)
    (when (and (org-at-heading-p)
               (eq (alist-get 'heading org-blank-before-new-entry) t))
      (let ((here (point-marker)))
        (save-excursion
          (beginning-of-line)
          ;; Before the new heading.
          (unless (or (bobp) (save-excursion (forward-line -1) (looking-at-p "[ \t]*$")))
            (insert "\n"))
          ;; After it, when the old heading follows (C-S-RET, above).
          (forward-line 1)
          (when (and (eq direction 'above) (looking-at-p "\\*+ "))
            (insert "\n")))
        (goto-char here)
        (set-marker here nil)))))

(with-eval-after-load 'org
  (when (fboundp '+org--insert-item)
    (advice-add '+org--insert-item :around #'+format-org-heading-blank-a)))

(provide '+format)
;;; +format.el ends here
