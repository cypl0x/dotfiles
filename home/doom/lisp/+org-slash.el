;;; lisp/+org-slash.el --- Notion-like /commands in Org -*- lexical-binding: t; -*-
;;
;; Type / at the start of a line or after a space in Org, and the completion
;; popup lists what can go there; picking one replaces the /word with it.
;; Each is Org's own command or syntax:
;;
;;   /table   /table5x2   table, COLUMNSxROWS as `org-table-create' asks
;;   /code    /src        source block (language asked for, completed)
;;   /quote /example /verse /center /comment /export   blocks
;;   /h1 /h2 /h3          heading of that level   /todo   TODO heading here
;;   /check /list /num    - [ ]   -   1.
;;   /date /time          today's timestamp (with the time)
;;   /schedule /deadline  planning for this entry
;;   /link /footnote /math /hr /props
;;
;; Not in src blocks, ~code~, =verbatim= or links; a path like /usr/bin
;; matches no command, so nothing pops up.
;;
;;; Code:

(declare-function org-table-create "org-table" (&optional size))
(declare-function org-insert-structure-template "org" (type))
(declare-function org-insert-link "ol" (&optional complete-file link-location description))
(declare-function org-footnote-new "org-footnote" ())
(declare-function org-schedule "org" (arg &optional time))
(declare-function org-deadline "org" (arg &optional time))
(declare-function org-insert-time-stamp "org" (time &optional with-hm inactive pre post extra))
(declare-function org-in-src-block-p "org" (&optional inside element))
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-current-level "org" ())
(declare-function org-set-property "org" (property value))
(defvar org-src-lang-modes)
(defvar org-babel-load-languages)

(defun +org-slash--src ()
  "A src block, its language picked from those Org knows."
  (let ((lang (completing-read
               "Language: "
               (delete-dups (append (mapcar (lambda (l) (symbol-name (car l))) org-babel-load-languages)
                                    (mapcar #'car org-src-lang-modes)))
               nil nil)))
    (org-insert-structure-template (string-trim (concat "src " lang)))))

(defun +org-slash--heading (level &optional todo)
  (insert (make-string level ?*) " " (if todo "TODO " "")))

(defconst +org-slash-commands
  `(("table"    "table, 3x2; /table5x2: 5 columns, 2 rows" ,(lambda () (org-table-create "3x2")))
    ("code"     "source block"     +org-slash--src)
    ("src"      "source block"     +org-slash--src)
    ("quote"    "quote block"      ,(lambda () (org-insert-structure-template "quote")))
    ("example"  "example block"    ,(lambda () (org-insert-structure-template "example")))
    ("verse"    "verse block"      ,(lambda () (org-insert-structure-template "verse")))
    ("center"   "centered block"   ,(lambda () (org-insert-structure-template "center")))
    ("comment"  "comment block"    ,(lambda () (org-insert-structure-template "comment")))
    ("export"   "export block"     ,(lambda () (org-insert-structure-template "export")))
    ("h1"       "heading, level 1" ,(lambda () (+org-slash--heading 1)))
    ("h2"       "heading, level 2" ,(lambda () (+org-slash--heading 2)))
    ("h3"       "heading, level 3" ,(lambda () (+org-slash--heading 3)))
    ("todo"     "TODO heading one level below this one"
     ,(lambda () (+org-slash--heading (1+ (or (org-current-level) 0)) t)))
    ("check"    "checkbox item"    ,(lambda () (insert "- [ ] ")))
    ("list"     "list item"        ,(lambda () (insert "- ")))
    ("num"      "numbered item"    ,(lambda () (insert "1. ")))
    ("date"     "today"            ,(lambda () (org-insert-time-stamp nil)))
    ("time"     "now"              ,(lambda () (org-insert-time-stamp nil t)))
    ("schedule" "schedule this entry" ,(lambda () (org-schedule nil)))
    ("deadline" "deadline for this entry" ,(lambda () (org-deadline nil)))
    ("link"     "link"             org-insert-link)
    ("footnote" "footnote"         org-footnote-new)
    ("math"     "display math"     ,(lambda () (insert "\\[  \\]") (backward-char 3)))
    ("hr"       "horizontal rule"  ,(lambda () (insert "-----\n")))
    ("props"    "property of this entry" ,(lambda () (call-interactively #'org-set-property))))
  "The /commands: (NAME DESCRIPTION FUNCTION).")

(defun +org-slash--command (name)
  "The function NAME runs: a /tableCxR makes that size."
  (if (string-match "\\`table\\([0-9]+\\)x\\([0-9]+\\)\\'" name)
      (let ((size (format "%sx%s" (match-string 1 name) (match-string 2 name))))
        (lambda () (org-table-create size)))
    (nth 2 (assoc name +org-slash-commands))))

(defun +org-slash--here-p ()
  "Whether a /command may start here: prose, not code, verbatim or a link."
  (not (or (org-in-src-block-p t)
           (memq (org-element-type (org-element-context)) '(code verbatim link)))))

(defun +org-slash-capf ()
  "Complete /commands in Org.  The / is part of the candidate, so corfu
pops up from /t on (two characters)."
  (when-let* (((derived-mode-p 'org-mode))
              (slash (and (looking-back "\\(?:^\\|[ \t]\\)\\(/[[:alnum:]]*\\)" (line-beginning-position))
                          (match-beginning 1)))
              ;; After the match: Org's parser changes the match data.
              ((+org-slash--here-p)))
    (let ((name (lambda (cand) (substring cand 1))))
      (list slash (point)
            (lambda (str pred action)
              (complete-with-action
               action
               (append (mapcar (lambda (c) (concat "/" (car c))) +org-slash-commands)
                       (and (string-match-p "\\`/table[0-9]+x[0-9]+\\'" str) (list str)))
               str pred))
            :annotation-function
            (lambda (cand)
              (concat "  " (or (nth 1 (assoc (funcall name cand) +org-slash-commands))
                               "table of that size")))
            :company-kind (lambda (_) 'snippet)
            :exit-function
            (lambda (cand status)
              (when-let* (((memq status '(finished exact)))
                          (fn (+org-slash--command (funcall name cand))))
                ;; The /word goes; what it names comes in its place.
                (delete-region slash (point))
                (funcall fn)))
            :exclusive 'no))))

;;;; Nothing typed yet: C-SPC offers what can go here

(declare-function org-get-buffer-tags "org" ())
(defvar org-todo-keywords-1)

(defun +org-slash-empty-capf ()
  "With nothing typed before point: what fits here, for C-SPC.
Right after a heading's stars, the TODO keywords and priorities; later in
a heading, the buffer's tags; elsewhere in prose, the /commands (without
the /: picking one inserts it)."
  (when (and (derived-mode-p 'org-mode)
             (or (bolp) (memq (char-before) '(?\s ?\t)))
             (+org-slash--here-p))
    (let ((heading (save-excursion (beginning-of-line) (looking-at "\\(\\*+\\) "))))
      (cond
       ;; "** |": a keyword or a priority.
       ((and heading (= (point) (match-end 0)))
        (list (point) (point)
              (append (mapcar (lambda (k) (concat k " ")) org-todo-keywords-1)
                      '("[#A] " "[#B] " "[#C] "))
              :annotation-function (lambda (c) (if (string-prefix-p "[#" c) "  priority" "  keyword"))
              :exclusive 'no))
       ;; "** TODO Title |": a tag.
       (heading
        (list (point) (point)
              (mapcar (lambda (tag) (concat ":" (car tag) ":")) (org-get-buffer-tags))
              :annotation-function (lambda (_) "  tag")
              :exclusive 'no))
       (t
        (let ((start (point)))
          (list start start
                (mapcar #'car +org-slash-commands)
                :annotation-function (lambda (c) (concat "  " (nth 1 (assoc c +org-slash-commands))))
                :company-kind (lambda (_) 'snippet)
                :exit-function
                (lambda (cand status)
                  (when-let* (((memq status '(finished exact)))
                              (fn (+org-slash--command cand)))
                    ;; The name goes; what it names comes in its place.
                    (delete-region start (point))
                    (funcall fn)))
                :exclusive 'no)))))))

(add-hook 'org-mode-hook
          (defun +org-slash-h ()
            (add-hook 'completion-at-point-functions #'+org-slash-capf 60 t)))

(provide '+org-slash)
;;; +org-slash.el ends here
