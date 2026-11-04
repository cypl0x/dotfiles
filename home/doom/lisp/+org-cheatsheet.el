;;; lisp/+org-cheatsheet.el --- Org by example: how do I ... in Org? -*- lexical-binding: t; -*-
;;
;; SPC m ? in Org (M-x +org/cheatsheet anywhere): search "how do I ..."
;; (vertico), see a small working example in a popup, fontified as Org.
;; There:
;;
;;   i   insert the example where you were
;;   m   the Org manual's node about it, for the whole story
;;   a   every example on one page (all markup at a glance)
;;   q   close
;;
;; The examples follow the Org manual (Info: org); each names its node.
;;
;;; Code:

(declare-function org-mode "org" ())
(defvar org-hide-emphasis-markers)
(defvar org-pretty-entities)
(defvar org-link-descriptive)

(defconst +org-cheatsheet
  '(;; Markup
    ("Bold, italic, underline, strike-through"
     "*bold* /italic/ _underlined_ +strike-through+" "Emphasis and Monospace")
    ("Inline code vs verbatim: ~code~ or =verbatim=?"
     "Call ~org-capture~ and set ~org-agenda-files~ to ~nil~.
Set the =TODO= keyword, the =ID= property to =yes=, open =notes.org=.

Both are monospace and Org syntax inside isn't processed.  Org's own
manual writes Lisp symbols as ~code~, literal strings (keywords,
property names, values, file names) as =verbatim=."
     "Emphasis and Monospace")
    ("Emphasize the region (or insert markers)" "C-c C-x C-f  (org-emphasize)" "Emphasis and Monospace")
    ("Sub- and superscripts" "H_2O  E = mc^2  x_{i+1}  2^{10}" "Subscripts and Superscripts")
    ("Special symbols (entities)" "\\alpha \\to \\beta, 30\\deg, \\copy 2026" "Special Symbols")
    ("Inline math (LaTeX)" "Euler: \\(e^{i\\pi} + 1 = 0\\)" "LaTeX fragments")
    ("Display math" "\\[ \\sum_{k=1}^{n} k = \\frac{n(n+1)}{2} \\]" "LaTeX fragments")
    ("Horizontal rule" "-----" "Horizontal Rules")
    ("Line break inside a paragraph" "first line\\\\
second line" "Paragraphs")
    ("Comment out a line" "# This line is not exported." "Comment Lines")
    ("Escape markup (zero width space)" "Insert U+200B between markers: C-x 8 RET zero width space" "Escape Character")
    ;; Structure
    ("Headings and levels" "* Level 1
** Level 2
*** Level 3" "Headlines")
    ("TODO heading with priority and tags" "** TODO [#A] Write the report  :work:urgent:" "TODO Basics")
    ("Own TODO keywords for this file" "#+todo: TODO NEXT WAIT | DONE CANCELLED" "Per-file keywords")
    ("Progress cookie on a heading" "* Tasks [1/3]
- [X] one
- [ ] two
- [ ] three" "Checkboxes")
    ("Plain, numbered and description lists" "- item
  - nested item
1. first
2. second
- term :: its description" "Plain Lists")
    ("Checkbox list" "- [ ] open
- [X] done
- [-] partly done" "Checkboxes")
    ("Drawer (hidden notes)" ":NOTES:
Hidden until opened.
:END:" "Drawers")
    ("Properties of an entry" "* Entry
:PROPERTIES:
:ID:       1234
:CATEGORY: work
:END:" "Property Syntax")
    ("Quote, example, verse and center blocks" "#+begin_quote
Quoted text.
#+end_quote

#+begin_example
Shown as is.
#+end_example" "Blocks")
    ("Insert a block quickly" "C-c C-,  (org-insert-structure-template), or /quote here" "Structure Templates")
    ("Footnote" "Text with a footnote.[fn:1]

[fn:1] The note." "Creating Footnotes")
    ("Document title, author, options" "#+title: Notes
#+author: Me
#+options: toc:nil num:nil" "Export Settings")
    ;; Tables
    ("Table" "| Name | Qty |
|------+-----|
| tea  |   2 |" "Built-in Table Editor")
    ("Create a table of a size" "C-c |  then 5x2  (COLUMNSxROWS), or /table5x2" "Built-in Table Editor")
    ("Spreadsheet formula" "| a | b | sum |
|---+---+-----|
| 1 | 2 |   3 |
#+tblfm: $3=$1+$2" "The Spreadsheet")
    ("Table caption and name" "#+caption: Prices
#+name: tab:prices
| item | price |" "Captions")
    ;; Links and images
    ("Link to a web page" "[[https://orgmode.org][Org mode]]" "Link Format")
    ("Link to a file, a line, a heading" "[[file:notes.org]]  [[file:init.el::42]]  [[file:notes.org::*Ideas]]" "Search Options")
    ("Link to a heading in this file" "[[*Ideas][see Ideas]]" "Internal Links")
    ("Image" "[[file:diagram.png]]" "Images")
    ("Insert or edit a link" "C-c C-l  (org-insert-link); C-c C-o opens it" "Handling Links")
    ;; Dates
    ("Active and inactive timestamps" "<2026-11-04 Wed 10:00>  [2026-11-04 Wed]" "Timestamps")
    ("Schedule and deadline" "** TODO Pay rent
SCHEDULED: <2026-11-28 Sat> DEADLINE: <2026-12-01 Tue>" "Deadlines and Scheduling")
    ("Repeating task" "** TODO Water plants
SCHEDULED: <2026-11-04 Wed +1w>" "Repeated tasks")
    ("Time range" "<2026-11-04 Wed 10:00-11:30>  <2026-11-04 Wed>--<2026-11-06 Fri>" "Timestamps")
    ("Clock time on a task" "C-c C-x C-i  clock in,  C-c C-x C-o  clock out" "Clocking commands")
    ;; Code
    ("Source block" "#+begin_src emacs-lisp
(message \"hi\")
#+end_src" "Structure of Code Blocks")
    ("Run a source block and keep its result" "#+begin_src sh :results output
date
#+end_src

C-c C-c on the block" "Evaluating Code Blocks")
    ("Edit a source block in its own mode" "C-c '  (org-edit-special) on the block" "Editing Source Code")
    ("Inline source code" "src_python{1 + 1}  {{{results(=2=)}}}" "Structure of Code Blocks")
    ("Tangle code to a file" "#+begin_src sh :tangle setup.sh
echo set up
#+end_src

C-c C-v t  (org-babel-tangle)" "Extracting Source Code")
    ;; Doing things
    ("Export (HTML, PDF, Markdown, ...)" "C-c C-e  (org-export-dispatch)" "The Export Dispatcher")
    ("Capture a note from anywhere" "C-c c  (org-capture), or SPC X in Doom" "Using capture")
    ("Move a subtree elsewhere (refile)" "C-c C-w  (org-refile)" "Refile and Copy")
    ("Archive a done subtree" "C-c C-x C-s  (org-archive-subtree)" "Moving subtrees")
    ("Agenda" "C-c a  (org-agenda); files from org-agenda-files" "Agenda Dispatcher")
    ("Sparse tree: show only matches" "C-c /  (org-sparse-tree)" "Sparse Trees")
    ("Fold and unfold" "TAB on a heading; S-TAB the whole buffer" "Global and local cycling")
    ("Move and promote headings" "M-up / M-down move, M-left / M-right promote / demote" "Structure Editing"))
  "How do I ... in Org: (QUESTION EXAMPLE MANUAL-NODE).")

(defvar-local +org-cheatsheet--entry nil "The entry shown in this popup.")
(defvar +org-cheatsheet--origin nil "Window to insert into.")

(defvar +org-cheatsheet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "i" #'+org-cheatsheet-insert)
    (define-key map "m" #'+org-cheatsheet-manual)
    (define-key map "a" #'+org/cheatsheet-all)
    (define-key map "q" #'quit-window)
    map))

(define-minor-mode +org-cheatsheet-mode
  "Keys in the Org by example popup."
  :keymap +org-cheatsheet-mode-map)

(defun +org-cheatsheet--show (title text &optional entry)
  "Show TEXT under TITLE in the popup, for ENTRY (or all)."
  (with-current-buffer (get-buffer-create "*Org by example*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert text)
      (delay-mode-hooks (org-mode))
      ;; The syntax is the point here: markers, entities and link brackets shown.
      (setq-local org-hide-emphasis-markers nil
                  org-pretty-entities nil
                  org-link-descriptive nil)
      (font-lock-flush)
      (font-lock-ensure)
      (goto-char (point-min)))
    (setq +org-cheatsheet--entry entry
          header-line-format
          (format " %s   %s" title
                  (substitute-command-keys
                   (concat (if entry "\\<+org-cheatsheet-mode-map>\\[+org-cheatsheet-insert] insert · \\[+org-cheatsheet-manual] manual · " "")
                           "\\<+org-cheatsheet-mode-map>\\[+org/cheatsheet-all] all · \\[quit-window] close"))))
    (+org-cheatsheet-mode 1)
    (setq buffer-read-only t)
    (pop-to-buffer (current-buffer))))

;;;###autoload
(defun +org/cheatsheet (question)
  "How do I QUESTION in Org: a small working example, in a popup."
  (interactive
   (list (completing-read
          "How do I … in Org: "
          (lambda (str pred action)
            (if (eq action 'metadata)
                `(metadata (annotation-function
                            . ,(lambda (q)
                                 (concat "   " (car (split-string (nth 1 (assoc q +org-cheatsheet)) "\n"))))))
              (complete-with-action action (mapcar #'car +org-cheatsheet) str pred)))
          nil t)))
  (setq +org-cheatsheet--origin (selected-window))
  (let ((entry (assoc question +org-cheatsheet)))
    (+org-cheatsheet--show (car entry)
                           (format "%s\n\n# Manual: (org) %s\n" (nth 1 entry) (nth 2 entry))
                           entry)))

(defun +org/cheatsheet-all ()
  "Every example on one page."
  (interactive)
  (unless (window-live-p +org-cheatsheet--origin)
    (setq +org-cheatsheet--origin (selected-window)))
  (+org-cheatsheet--show
   "Org by example: all"
   (mapconcat (lambda (e) (format "* %s\n%s\n" (car e) (nth 1 e))) +org-cheatsheet "\n")))

(defun +org-cheatsheet-insert ()
  "Insert the example shown where you were."
  (interactive)
  (let ((text (nth 1 +org-cheatsheet--entry)))
    (unless text (user-error "Pick one example first (SPC m ?)"))
    (quit-window)
    (when (window-live-p +org-cheatsheet--origin)
      (select-window +org-cheatsheet--origin))
    (insert text)))

(defun +org-cheatsheet-manual ()
  "The Org manual's node about the example shown."
  (interactive)
  (when-let* ((node (nth 2 +org-cheatsheet--entry)))
    (info (format "(org) %s" node))))

(map! :after org :map org-mode-map :localleader :desc "Org by example" "?" #'+org/cheatsheet)

(provide '+org-cheatsheet)
;;; +org-cheatsheet.el ends here
