;;; lisp/+org-lint.el --- Org style lint, live, on Org's own org-lint -*- lexical-binding: t; -*-
;;
;; markdownlint for Org: rules about how Org is written, not whether it
;; parses (Org's own `org-lint' does that).  Each rule is an org-lint
;; checker in the `style' category, so
;;
;;   M-x org-lint          lists Org's findings and these together
;;   C-u M-x org-lint      `style' only
;;
;; and flycheck shows all of them as you write (checker `+org-lint').
;;
;;   rule                          like markdownlint
;;   =x= that is code → ~x~        (Org manual: ~code~, =verbatim=)
;;   empty heading
;;   heading level jumps           MD001
;;   same heading twice in a row   MD024 (siblings only)
;;   heading ending in . , ; : !   MD026
;;   runs of blank lines           MD012
;;   trailing spaces               MD009
;;   blank line missing            MD022 MD031 MD032 (what SPC c f adds)
;;   #+KEYWORD in upper case       (Org writes them lower case since 9)
;;   bullets mixed in one list     MD004
;;   same text =x= here, ~x~ there
;;   *bold* paragraph as heading   MD036
;;   link text "here", "link"      MD059
;;   tab characters                MD010
;;   table not aligned
;;   ordered list 1. and 1) mixed  MD029
;;   bare URL                      MD034
;;   empty link or link text       MD042
;;   image without caption or alt  MD045
;;   = x= or ~ x~ (not marked up)  MD037 MD038
;;   no final newline              MD047
;;   a second #+title              MD025
;;
;;; Code:

(require 'map)
(require 'cl-lib)
(require 'seq)
(declare-function org-lint-add-checker "org-lint" (name summary fun &rest props))
(declare-function org-lint-checker-function "org-lint" (cl-x))
(declare-function org-lint-checker-name "org-lint" (cl-x))
(declare-function org-element-map "org-element" (data types fun &optional info first-match no-recursion with-affiliated))
(declare-function org-element-parse-buffer "org-element" (&optional granularity visible-only keep-deferred))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))
(declare-function org-element-contents "org-element-ast" (node))
(declare-function org-element-at-point "org-element" (&optional epom cached-only))
(declare-function org-element-parent "org-element-ast" (node))
(declare-function org-element-lineage "org-element-ast" (datum &optional types with-self))
(declare-function +format-org--blank-positions "+format" ())
(defvar org-lint--checkers)
(defvar +format-org-verbatim)

;;;; Rules

(defun +org-lint--key-p (s)
  "Whether S reads as keys (C-c C-c, SPC c f, M-ß): those stay =verbatim=."
  (string-match-p
   "\\`\\(?:\\(?:[CMSsHA]-\\)*\\(?:[^ ]\\|SPC\\|RET\\|TAB\\|ESC\\|DEL\\|<[[:alnum:]-]+>\\)\\(?: \\|\\'\\)\\)+\\'"
   s))

(defun +org-lint--code-p (s)
  "Whether S is plainly code: a Lisp form, or an Emacs function or variable."
  (and (not (+org-lint--key-p s))
       (or (string-match-p "\\`([^ ].*)\\'" s)
           (when-let* ((sym (intern-soft s)))
             (and (string-match-p "[-/]" s) (or (fboundp sym) (boundp sym)))))))

(defun +org-lint-verbatim-code (ast)
  (org-element-map ast 'verbatim
    (lambda (v)
      (let ((s (org-element-property :value v)))
        (when (+org-lint--code-p s)
          (list (org-element-property :begin v)
                (format "=%s= is code: Org writes code as ~%s~" s s)))))))

(defun +org-lint--title (h)
  (string-trim (or (org-element-property :raw-value h) "")))

(defun +org-lint-empty-heading (ast)
  (org-element-map ast 'headline
    (lambda (h)
      (when (string-empty-p (+org-lint--title h))
        (list (org-element-property :begin h) "Heading without a title")))))

(defun +org-lint-heading-increment (ast)
  (org-element-map ast 'headline
    (lambda (h)
      (let* ((parent (org-element-property :parent h))
             (above (if (eq (org-element-type parent) 'headline)
                        (org-element-property :level parent)
                      0))
             (level (org-element-property :level h)))
        (when (> level (1+ above))
          (list (org-element-property :begin h)
                (format "Heading level %d under level %d: skips a level" level above)))))))

(defun +org-lint-duplicate-sibling (ast)
  (let (reports)
    (org-element-map ast '(org-data headline)
      (lambda (parent)
        (let (seen)
          (dolist (h (org-element-contents parent))
            (when (eq (org-element-type h) 'headline)
              (let ((title (+org-lint--title h)))
                (unless (string-empty-p title)
                  (if (member title seen)
                      (push (list (org-element-property :begin h)
                                  (format "Same heading as a sibling above: %s" title))
                            reports)
                    (push title seen)))))))))
    (nreverse reports)))

(defun +org-lint-heading-punctuation (ast)
  (org-element-map ast 'headline
    (lambda (h)
      (let ((title (replace-regexp-in-string "[ \t]*\\[[0-9]*[/%][0-9]*\\]\\'" ""
                                             (+org-lint--title h))))
        ;; An ellipsis (a placeholder: "Include ...") isn't a sentence end.
        (when (and (string-match-p "[.,;:!]\\'" title)
                   (not (string-match-p "\\.\\.\\'\\|…\\'" title)))
          (list (org-element-property :begin h)
                (format "Heading ends in \"%s\"" (substring title -1))))))))

(defun +org-lint--in-verbatim-p ()
  "Whether point is between the delimiters of a block whose text is content."
  (let ((el (org-element-at-point)))
    (and (memq (org-element-type el) +format-org-verbatim)
         (> (point) (save-excursion (goto-char (org-element-property :post-affiliated el))
                                    (line-end-position)))
         (< (point) (save-excursion (goto-char (org-element-property :end el))
                                    (skip-chars-backward " \t\n")
                                    (line-beginning-position))))))

(defun +org-lint-blank-lines (_ast)
  (let (reports)
    (while (re-search-forward "\n\\(?:[ \t]*\n\\)\\{2,\\}" nil t)
      (let ((pos (1+ (match-beginning 0))))
        (unless (save-match-data (save-excursion (goto-char pos) (+org-lint--in-verbatim-p)))
          (push (list pos "More than one blank line") reports))))
    (nreverse reports)))

(defun +org-lint-trailing-whitespace (_ast)
  (let (reports)
    (while (re-search-forward "[ \t]+$" nil t)
      (unless (save-match-data (+org-lint--in-verbatim-p))
        (push (list (match-beginning 0) "Trailing whitespace") reports)))
    (nreverse reports)))

(defun +org-lint-missing-blank-line (_ast)
  (when (fboundp '+format-org--blank-positions)   ; lisp/+format.el
    (let (reports)
      (dolist (pos (+format-org--blank-positions))
        (save-excursion
          (goto-char pos)
          (unless (or (bobp)
                      (save-excursion (forward-line -1) (looking-at-p "[ \t]*$")))
            (push (list pos "No blank line before this (SPC c f adds it)") reports))))
      (sort reports (lambda (a b) (< (car a) (car b)))))))

(defun +org-lint-keyword-case (_ast)
  (let ((case-fold-search nil) reports)
    (while (re-search-forward "^[ \t]*#\\+\\(\\(?:BEGIN\\|END\\)_[A-Za-z]+\\|[A-Z_]+:\\)" nil t)
      (unless (save-match-data (+org-lint--in-verbatim-p))
        (push (list (match-beginning 1)
                    (format "#+%s: Org writes it lower case" (match-string 1)))
              reports)))
    (nreverse reports)))

(defun +org-lint-list-bullets (ast)
  (org-element-map ast 'plain-list
    (lambda (l)
      (unless (eq (org-element-property :type l) 'ordered)
        (let* ((items (org-element-contents l))
               (bullet (lambda (i) (string-trim (org-element-property :bullet i))))
               (first (funcall bullet (car items))))
          (seq-some (lambda (i)
                      (unless (equal (funcall bullet i) first)
                        (list (org-element-property :begin i)
                              (format "Bullet %s in a list of %s" (funcall bullet i) first))))
                    (cdr items)))))))

(defun +org-lint-mixed-markup (ast)
  "The same text as =verbatim= in one place and ~code~ in another."
  (let ((seen (make-hash-table :test #'equal)))
    (org-element-map ast '(verbatim code)
      (lambda (v) (push (cons (org-element-type v) (org-element-property :begin v))
                        (gethash (org-element-property :value v) seen))))
    (let (out)
      (maphash
       (lambda (text uses)
         (let ((code (cl-count 'code uses :key #'car))
               (verb (cl-count 'verbatim uses :key #'car)))
           (when (and (> code 0) (> verb 0))
             ;; The fewer kind is reported; ~code~ wins a tie.
             (let ((minority (if (> verb code) 'code 'verbatim)))
               (dolist (u uses)
                 (when (eq (car u) minority)
                   (push (list (cdr u)
                               (format "%s is %s here but %s %d× elsewhere: pick one (~code~ for code, =verbatim= for literal text)"
                                       text
                                       (if (eq minority 'code) (format "~%s~" text) (format "=%s=" text))
                                       (if (eq minority 'code) (format "=%s=" text) (format "~%s~" text))
                                       (if (eq minority 'code) verb code)))
                         out)))))))
       seen)
      out)))

(defun +org-lint-emphasis-heading (ast)
  "A paragraph that is only *bold* or /italic/ text: a heading in disguise (MD036)."
  (org-element-map ast 'paragraph
    (lambda (p)
      (let ((contents (seq-remove (lambda (c) (and (stringp c) (string-blank-p c)))
                                  (org-element-contents p))))
        (when (and (= (length contents) 1)
                   (memq (org-element-type (car contents)) '(bold italic))
                   (not (eq (org-element-type (org-element-property :parent p)) 'item)))
          (list (org-element-property :begin p)
                "Emphasis as a heading (MD036): make it a heading"))))))

(defconst +org-lint-vague-link-texts
  '("here" "click here" "link" "this link" "this" "more" "read more" "hier" "mehr" "dieser link")
  "Link descriptions that don't say where they lead.")

(defun +org-lint-link-text (ast)
  "A link whose text says nothing about where it goes (MD059)."
  (org-element-map ast 'link
    (lambda (l)
      (let ((desc (org-element-contents l)))
        (when (and desc (stringp (car desc)) (null (cdr desc))
                   (member (downcase (string-trim (car desc))) +org-lint-vague-link-texts))
          (list (org-element-property :begin l)
                (format "Link text \"%s\" (MD059): say where it leads" (string-trim (car desc)))))))))


(defun +org-lint-hard-tabs (_ast)
  "Tabs in the text (MD010): they align differently everywhere."
  (let (reports)
    (while (re-search-forward "\t" nil t)
      (unless (save-match-data (+org-lint--in-verbatim-p))
        (push (list (match-beginning 0) "Tab character (MD010): use spaces") reports)
        (forward-line 1)))
    (nreverse reports)))

(defun +org-lint--table-columns (line)
  "Positions of the column separators (| and +) in table LINE."
  (let (cols (i 0))
    (while (string-match "[|+]" line i)
      (push (match-beginning 0) cols) (setq i (match-end 0)))
    (nreverse cols)))

(defun +org-lint-table-alignment (ast)
  "A table whose columns don't line up (TAB in it aligns it)."
  (org-element-map ast 'table
    (lambda (tbl)
      (when (eq (org-element-property :type tbl) 'org)
        (let* ((text (buffer-substring-no-properties (org-element-property :contents-begin tbl)
                                                     (org-element-property :contents-end tbl)))
               (rows (seq-filter (lambda (l) (string-match-p "\\`[ \t]*|" l)) (split-string text "\n" t)))
               (shapes (delete-dups (mapcar #'+org-lint--table-columns rows))))
          (when (cdr shapes)
            (list (org-element-property :begin tbl) "Table not aligned (TAB in it aligns it)")))))))

(defun +org-lint-ordered-delimiters (ast)
  "An ordered list mixing 1. and 1) (MD029)."
  (org-element-map ast 'plain-list
    (lambda (l)
      (when (eq (org-element-property :type l) 'ordered)
        (let ((delims (delete-dups (org-element-map l 'item
                                     (lambda (i) (when (eq (org-element-parent i) l)
                                                   (substring (string-trim (org-element-property :bullet i)) -1)))
                                     nil nil 'item))))
          (when (cdr delims)
            (list (org-element-property :begin l) "Ordered list mixes \"1.\" and \"1)\" (MD029)")))))))

(defun +org-lint-bare-url (ast)
  "A bare URL (MD034): [[URL][what it is]] reads better."
  (org-element-map ast 'link
    (lambda (l)
      (when (and (eq (org-element-property :format l) 'plain)
                 (member (org-element-property :type l) '("http" "https")))
        (list (org-element-property :begin l) "Bare URL (MD034): [[URL][what it is]]")))))

(defun +org-lint-empty-link (_ast)
  "A link with nothing to go to, or empty link text (MD042)."
  (let (reports)
    (while (re-search-forward "\\[\\[[ \t]*\\]\\(?:\\[[^]]*\\]\\)?\\]\\|\\[\\[[^]\n]+\\]\\[[ \t]*\\]\\]" nil t)
      (unless (save-match-data (+org-lint--in-verbatim-p))
        (push (list (match-beginning 0) "Empty link or empty link text (MD042)") reports)))
    (nreverse reports)))

(defconst +org-lint--image-re "\\.\\(?:png\\|jpe?g\\|gif\\|svg\\|webp\\|avif\\)\\'")

(defun +org-lint-image-alt (ast)
  "An image without a caption or alt text (MD045)."
  (org-element-map ast 'link
    (lambda (l)
      (when (and (member (org-element-property :type l) '("file" "attachment"))
                 (string-match-p +org-lint--image-re (org-element-property :path l))
                 (null (org-element-contents l)))
        (let ((par (org-element-lineage l '(paragraph))))
          (unless (or (and par (org-element-property :caption par))
                      (and par (seq-some (lambda (a) (string-match-p ":alt" a))
                                         (org-element-property :attr_html par))))
            (list (org-element-property :begin l)
                  "Image without #+caption or #+attr_html: :alt (MD045)")))))))

(defun +org-lint-emphasis-spaces (_ast)
  "=x = or ~ x~: spaces inside the markers, shown literally (MD037/MD038)."
  (let (reports)
    (while (re-search-forward "\\(?:^\\|[[:space:](\"']\\)\\([=~]\\)\\(?: [^\n=~]*[^ \n=~]\\|[^ \n=~][^\n=~]* \\)\\1\\(?:[[:space:][:punct:]]\\|$\\)" nil t)
      (unless (save-match-data (+org-lint--in-verbatim-p))
        (push (list (match-beginning 1) "Space inside =…= or ~…~: Org won't mark it up (MD037/MD038)") reports)))
    (nreverse reports)))

(defun +org-lint-final-newline (_ast)
  "The file doesn't end with a newline (MD047)."
  (when (and (> (point-max) (point-min)) (/= (char-before (point-max)) ?\n))
    (list (list (1- (point-max)) "No newline at the end of the file (MD047)"))))

(defun +org-lint-several-titles (ast)
  "More than one #+title (MD025): one document, one title."
  (cdr (org-element-map ast 'keyword
         (lambda (k) (when (equal (org-element-property :key k) "TITLE")
                       (list (org-element-property :begin k) "A second #+title (MD025)"))))))
(defconst +org-lint-rules
  '((+org-lint-verbatim-code      "=code= that should be ~code~" low)
    (+org-lint-empty-heading      "Heading without a title" high)
    (+org-lint-heading-increment  "Heading levels skipped (MD001)" high)
    (+org-lint-duplicate-sibling  "Same heading twice among siblings (MD024)" high)
    (+org-lint-heading-punctuation "Heading ends in punctuation (MD026)" high)
    (+org-lint-blank-lines        "Runs of blank lines (MD012)" high)
    (+org-lint-trailing-whitespace "Trailing whitespace (MD009)" high)
    (+org-lint-missing-blank-line "Blank line missing (MD022/MD031/MD032)" high)
    (+org-lint-keyword-case       "Upper-case #+KEYWORD" high)
    (+org-lint-list-bullets       "Bullets mixed in one list (MD004)" high)
    (+org-lint-mixed-markup       "Same text as =verbatim= and ~code~" high)
    (+org-lint-emphasis-heading   "Emphasis used as a heading (MD036)" low)
    (+org-lint-link-text          "Link text that says nothing (MD059)" high)
    (+org-lint-hard-tabs          "Tab characters (MD010)" high)
    (+org-lint-table-alignment    "Table not aligned" high)
    (+org-lint-ordered-delimiters "Ordered list mixes 1. and 1) (MD029)" high)
    (+org-lint-bare-url           "Bare URL (MD034)" low)
    (+org-lint-empty-link         "Empty link or link text (MD042)" high)
    (+org-lint-image-alt          "Image without caption or alt text (MD045)" low)
    (+org-lint-emphasis-spaces    "Spaces inside =…= or ~…~ (MD037/MD038)" high)
    (+org-lint-final-newline      "No final newline (MD047)" high)
    (+org-lint-several-titles     "More than one #+title (MD025)" high))
  "The style rules: (FUNCTION SUMMARY TRUST).")

(with-eval-after-load 'org-lint
  (pcase-dolist (`(,fn ,summary ,trust) +org-lint-rules)
    (org-lint-add-checker fn summary fn :categories '(style) :trust trust)))

;;;; Flycheck

(declare-function flycheck-define-generic-checker "ext:flycheck" (symbol docstring &rest properties))
(declare-function flycheck-error-new-at-pos "ext:flycheck" (pos level message &rest args))
(defvar flycheck-checkers)
(defvar flycheck-disabled-checkers)

(defcustom +org-lint-max-per-rule 3
  "A style rule with more findings than this is shown once as you write,
saying how many more; M-x org-lint lists them all."
  :type 'natnum :group 'org)

(defcustom +org-lint-max-size 150000
  "Larger Org buffers aren't linted as you write (it runs in this Emacs:
~170 ms for 100k characters); M-x org-lint still works there."
  :type 'natnum :group 'org)

(defun +org-lint-findings ()
  "This buffer's `org-lint' findings: (POS LEVEL MESSAGE) ...
Org's checks are warnings, the style rules above info; a style rule with
more than `+org-lint-max-per-rule' findings gives its first, with a count."
  (require 'org-lint)
  (let ((ast (org-element-parse-buffer nil nil 'defer))
        (style (mapcar #'car +org-lint-rules))
        findings)
    (dolist (checker org-lint--checkers)
      (let* ((name (org-lint-checker-name checker))
             (reports (condition-case nil
                          (save-excursion
                            (goto-char (point-min))
                            (funcall (org-lint-checker-function checker) ast))
                        (error nil)))
             (more (and (memq name style)
                        (> (length reports) +org-lint-max-per-rule)
                        (1- (length reports)))))
        (pcase-dolist (`(,pos ,msg) (if more (list (car reports)) reports))
          (push (list (if (markerp pos) (marker-position pos) pos)
                      (if (memq name style) 'info 'warning)
                      (if more
                          (format "%s, and %d more like it (M-x org-lint lists them)" msg more)
                        msg))
                findings))))
    (sort findings (lambda (a b) (< (car a) (car b))))))

;; In place of flycheck's own org-lint checker (an Emacs subprocess
;; showing every finding): the same checks in this Emacs, many of a kind
;; shown once.
(with-eval-after-load 'flycheck
  (flycheck-define-generic-checker '+org-lint
    "Org's `org-lint' checks and the style rules of lisp/+org-lint.el."
    :start (lambda (checker callback)
             (condition-case err
                 (funcall callback 'finished
                          (mapcar (pcase-lambda (`(,pos ,level ,msg))
                                    (flycheck-error-new-at-pos pos level msg :checker checker))
                                  (+org-lint-findings)))
               (error (funcall callback 'errored (error-message-string err)))))
    :modes '(org-mode)
    :predicate (lambda () (< (buffer-size) +org-lint-max-size)))
  (add-to-list 'flycheck-checkers '+org-lint)
  (setq-default flycheck-disabled-checkers
                (cons 'org-lint (default-value 'flycheck-disabled-checkers))))

(provide '+org-lint)
;;; +org-lint.el ends here
