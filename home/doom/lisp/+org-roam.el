;;; lisp/+org-roam.el --- Org-roam: starting, and one menu for all of it -*- lexical-binding: t; -*-
;;
;; Org-roam links notes both ways: a link from A to B shows on B as a
;; backlink, and the notes and links form a graph.  A file (or heading) is a
;; note, a "node", once it has an :ID:.  The whole vault is the graph (see
;; +org-power.el); these commands get existing files into it and put
;; everything Org-roam does behind one menu.
;;
;;   SPC n r m   the menu: what the note at point is (title, aliases, tags,
;;               backlinks), and what you can do from here
;;   SPC n r I   make notes of files: this file, the files marked in dired,
;;               or every Org file under a directory (asks first, with the
;;               count)
;;   SPC n r e   Org-roam by example: a tour in a throwaway directory
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)


;; A directory may keep its own graph (.dir-locals.el), as the tour does.
(put 'org-roam-directory 'safe-local-variable #'stringp)
(put 'org-roam-db-location 'safe-local-variable #'stringp)

(declare-function org-roam-node-at-point "org-roam-node" (&optional assert))
(declare-function org-roam-node-title "org-roam-node" (node))
(declare-function org-roam-node-id "org-roam-node" (node))
(declare-function org-roam-node-aliases "org-roam-node" (node))
(declare-function org-roam-node-tags "org-roam-node" (node))
(declare-function org-roam-backlinks-get "org-roam-mode" (node &rest args))
(declare-function org-roam-db-query "org-roam-db" (sql &rest args))
(declare-function org-roam-db-update-file "org-roam-db" (&optional file-path no-require))
(declare-function org-roam-db-sync "org-roam-db" (&optional force))
(declare-function org-id-get-create "org-id" (&optional force))
(declare-function org-id-new "org-id" (&optional prefix))
(declare-function org-entry-get "org" (epom property &optional inherit literal-nil))
(declare-function org-roam-buffer-toggle "org-roam-mode" ())
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(defvar org-roam-directory)
(defvar org-roam-file-exclude-regexp)
(defvar org-roam-db-location)

;;;; Making notes of files

(defun +org-roam--title-from-file (file)
  (let ((base (file-name-base file)))
    ;; 20261105123456-dependent-types → Dependent types
    (setq base (replace-regexp-in-string "\\`[0-9]\\{8,14\\}-" "" base))
    (capitalize (replace-regexp-in-string "[-_]+" " " base))))

(defun +org-roam--init-file (file)
  "Make FILE a node: a file-level :ID: (and a #+title if it has none).
Returns t if it changed."
  (let ((buf (find-buffer-visiting file)) changed)
    (with-current-buffer (or buf (find-file-noselect file t))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          ;; A file-level drawer, written out: at the start of a file that
          ;; begins with a heading, org-id-get-create gave the heading the ID.
          (unless (and (looking-at-p "[ \t]*:PROPERTIES:")
                       (save-excursion (re-search-forward "^[ \t]*:ID:" (save-excursion (re-search-forward "^[ \t]*:END:" nil t)) t)))
            (if (looking-at-p "[ \t]*:PROPERTIES:")
                (progn (forward-line 1) (insert ":ID:       " (org-id-new) "\n"))
              (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n"))
            (setq changed t))
          (goto-char (point-min))
          (unless (re-search-forward "^#\\+title:" nil t)
            (goto-char (point-min))
            ;; After the property drawer, if the file starts with one.
            (when (looking-at-p "[ \t]*:PROPERTIES:")
              (re-search-forward "^[ \t]*:END:[ \t]*\n" nil t))
            (insert "#+title: " (+org-roam--title-from-file file) "\n")
            (setq changed t))))
      (when changed
        (save-buffer)
        (ignore-errors (org-roam-db-update-file file)))
      (unless buf (kill-buffer (current-buffer))))
    changed))

(defun +org-roam--org-files (dir)
  (cl-remove-if (lambda (f) (string-match-p org-roam-file-exclude-regexp f))
                (directory-files-recursively dir "\\.org\\'" nil
                                             (lambda (d) (not (string-match-p "/\\." d))))))

;;;###autoload
(defun +org-roam/init (&optional target)
  "Make notes of Org files: this file, the files marked in dired, or every
Org file under a directory (asked first, with the count).  Each gets an
:ID: (that makes it a node: linkable, with backlinks) and a #+title if it
has none.  TARGET: a file or directory."
  (interactive)
  (require 'org-roam)
  (let* ((files
          (cond
           (target (if (file-directory-p target) (+org-roam--org-files target) (list target)))
           ((derived-mode-p 'dired-mode)
            (cl-loop for f in (dired-get-marked-files)
                     append (if (file-directory-p f) (+org-roam--org-files f)
                              (and (string-suffix-p ".org" f) (list f)))))
           ((and (derived-mode-p 'org-mode) buffer-file-name) (list buffer-file-name))
           (t (+org-roam--org-files (read-directory-name "Make notes of the Org files under: "
                                                         org-roam-directory nil t)))))
         (outside (cl-remove-if (lambda (f) (file-in-directory-p f org-roam-directory)) files)))
    (unless files (user-error "No Org files there"))
    (when outside
      (user-error "%d of them are outside %s, the graph (`org-roam-directory')"
                  (length outside) (abbreviate-file-name org-roam-directory)))
    (when (or (null (cdr files))
              (y-or-n-p (format "Give %d Org files an ID (and a title where missing)? " (length files))))
      (let ((n (cl-count-if #'+org-roam--init-file files)))
        (message "Org-roam: %d of %d files became notes (the others already were)" n (length files))))))

;;;; The menu

(defun +org-roam--node-here ()
  (and (derived-mode-p 'org-mode) (require 'org-roam nil t) (ignore-errors (org-roam-node-at-point))))

(defun +org-roam-menu--header ()
  (let ((node (+org-roam--node-here))
        (count (ignore-errors (caar (org-roam-db-query [:select (funcall count *) :from nodes])))))
    (concat
     (if node
         (format "%s  %s%s%s"
                 (propertize (org-roam-node-title node) 'face 'bold)
                 (let ((n (length (org-roam-backlinks-get node))))
                   (propertize (format "%d backlink%s" n (if (= n 1) "" "s")) 'face (if (> n 0) 'success 'shadow)))
                 (if (org-roam-node-aliases node)
                     (concat "  aka " (string-join (org-roam-node-aliases node) ", ")) "")
                 (if (org-roam-node-tags node)
                     (concat "  :" (string-join (org-roam-node-tags node) ":") ":") ""))
       (propertize (if (derived-mode-p 'org-mode)
                       "Not a note yet: I makes this file one, n this heading"
                     "No note here")
                   'face 'shadow))
     (propertize (format "   ·  %s notes in the graph" (or count "?")) 'face 'shadow))))

(defun +org-roam/heading-node ()
  "Make the heading at point a note of its own (an :ID: on it)."
  (interactive)
  (org-id-get-create)
  (save-buffer)
  (org-roam-db-update-file)
  (message "This heading is a note now: link to it from anywhere"))

(transient-define-prefix +org-roam-menu ()
  "Org-roam: the note here, and everything you can do from it."
  [:description +org-roam-menu--header
   ["Find and link"
    ("f" "find or make a note" org-roam-node-find)
    ("i" "insert a link to a note" org-roam-node-insert)
    ("c" "capture a new note" org-roam-capture)
    ("r" "a random note" org-roam-node-random)
    ("s" "search all notes' text" consult-org-roam-search)]
   ["This note" :if +org-roam--node-here
    ("b" "backlinks beside it" org-roam-buffer-toggle)
    ("a" "add an alias" org-roam-alias-add)
    ("A" "remove an alias" org-roam-alias-remove)
    ("t" "add a tag" org-roam-tag-add)
    ("T" "remove a tag" org-roam-tag-remove)
    ("R" "add a reference (URL, citekey)" org-roam-ref-add)]
   ["Restructure" :if-derived org-mode
    ("x" "heading → a note of its own file" org-roam-extract-subtree)
    ("m" "move heading into another note" org-roam-refile)
    ("n" "this heading becomes a note" +org-roam/heading-node)
    ("I" "make notes of files…" +org-roam/init)]]
  [["Daily notes"
    ("d" "today" org-roam-dailies-goto-today)
    ("y" "yesterday" org-roam-dailies-goto-yesterday)
    ("D" "a date…" org-roam-dailies-goto-date)
    ("j" "jot into today" org-roam-dailies-capture-today)]
   ["The vault (like Obsidian)"
    ("g" "graph, in Emacs" +org/graph)
    ("l" "this note's links, all of them" +org-vault/links)
    ("p" "peek the linked note" +org-vault/peek)
    ("#" "tags of the vault" +org-vault/tags)
    ("P" "properties of the vault" +org-vault/properties)
    ("B" "a base: notes by properties" +org-vault/base)
    ("u" "a note named by the time" +org-vault/unique-note)
    ("o" "record audio here" +org-vault/record)
    ("C" "a canvas: cards on a board" +org/canvas)
    ("W" "publish the vault (HTML)" +org-vault/publish)
    ("Y" "sync the vault (git)" +org-vault/sync)]
   ["Graph (org-roam's)"
    ("G" "Graphviz image" org-roam-graph)
    ("S" "resync the database" org-roam-db-sync)]
   ["Learn"
    ("w" "the workflow, step by step" +org-roam/guide)
    ("e" "Org-roam by example (a tour)" +org-roam/tour)
    ("?" "this setup's manual" +docs/org-roam)
    ("M" "Org-roam's manual" +docs/org-roam-manual)]])

;;;; By example

(defun +org-roam/tour ()
  "Org-roam by example: three notes in a throwaway directory, linked, with
what to try next.  Your vault isn't touched."
  (interactive)
  (require 'org-roam)
  (let* ((dir (make-temp-file "org-roam-tour" t))
         (org-roam-directory dir)
         (org-roam-db-location (expand-file-name "tour.db" dir))
         (notes '(("lean" "Lean" "A proof assistant and programming language.\n\nIt checks [[id:tour-dtt][dependent types]].")
                  ("dtt" "Dependent types" "Types that depend on values.  Lean has them; so does Turm.\n\nSee [[id:tour-curry][Curry–Howard correspondence]].")
                  ("curry" "Curry–Howard correspondence" "Propositions are types, proofs are programs."))))
    (dolist (n notes)
      (with-temp-file (expand-file-name (concat (car n) ".org") dir)
        (insert (format ":PROPERTIES:\n:ID:       tour-%s\n:END:\n#+title: %s\n\n%s\n" (car n) (nth 1 n) (nth 2 n)))))
    ;; Every file there uses the tour's graph (Org-roam's way to keep a
    ;; second one), so following links stays in it.
    (with-temp-file (expand-file-name ".dir-locals.el" dir)
      (prin1 `((nil . ((org-roam-directory . ,dir)
                       (org-roam-db-location . ,(expand-file-name "tour.db" dir)))))
             (current-buffer)))
    (org-roam-db-sync)
    (find-file (expand-file-name "dtt.org" dir))
    (with-current-buffer (get-buffer-create "*org-roam tour*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Org-roam by example\n\n" 'face '(:weight bold :height 1.2))
                "Three notes, in " (abbreviate-file-name dir) " (your vault isn't touched):\n"
                "Lean → Dependent types → Curry–Howard.  You are in \"Dependent types\".\n\n"
                "1. SPC n r b   the backlinks beside it: Lean links here.\n"
                "2. Move onto the link to Curry–Howard, RET: you follow it.  SPC n r b there:\n"
                "   \"Dependent types\" links to it.\n"
                "3. Back (C-o), type [[ and \"Lea\": the note completes; RET links it.\n"
                "4. SPC n r m   the menu: this note's backlinks and tags, and what to do.\n"
                "5. In the menu, t adds a tag, a an alias (another name to find it by).\n"
                "6. SPC n r f   find by title (or a new title: that makes a note).\n"
                "7. SPC n r g   the graph of these three; SPC n r l all links of this one.\n\n"
                "In your vault: SPC n r I makes notes of your Org files (an :ID: each), and\n"
                "then the same works there.  Links grow the graph; folders don't matter.\n")
        (special-mode))
      (display-buffer (current-buffer)))))

;;;; The workflow, step by step

(defconst +org-roam-guide
  '(("Capture: get it out of your head"
     "Everything lands in ~/vault/inbox.org first, stamped with when."
     ("SPC X t" "a TODO for you" org-capture) ("SPC X n" "a note" org-capture)
     ("SPC X a" "a TODO for an agent" org-capture))
    ("Triage: give each item its place"
     "Go through the inbox: a heading worth keeping becomes a note, or moves into one."
     ("SPC n r n" "this heading becomes a note" +org-roam/heading-node)
     ("SPC n r x" "this heading becomes a note of its own file" org-roam-extract-subtree)
     ("SPC n r m m" "move this heading into another note" org-roam-refile))
    ("Write and link"
     "Links are what make notes worth having: link as you write."
     ("[[" "then a title: a note completes (C-SPC with nothing typed: what fits)" nil)
     ("SPC n r i" "link to a note" org-roam-node-insert)
     ("SPC n r f" "find a note, or make one with a new title" org-roam-node-find))
    ("Find again"
     "By title, by text, by tag, by property."
     ("SPC n r f" "by title" org-roam-node-find) ("SPC n r s" "by text" consult-org-roam-search)
     ("SPC n r t" "by tag" +org-vault/tags) ("SPC n r B" "by properties, as a table" +org-vault/base))
    ("See how it connects"
     "Backlinks, the graph, and the links you haven't made yet (dashed)."
     ("SPC n r l" "this note's links: back, out, unlinked mentions" +org-vault/links)
     ("SPC n r g" "the graph around this note" +org/graph)
     ("on a link" "its note's opening in the echo area; SPC n r p shows it" +org-vault/peek))
    ("Every day"
     "A note per day for what doesn't belong anywhere yet."
     ("SPC n r d t" "today's note" org-roam-dailies-goto-today)
     ("SPC n r m j" "jot into today" org-roam-dailies-capture-today))
    ("Keep it tidy"
     "Turn unlinked mentions into links; tags and properties for what you look things up by."
     ("SPC n r l" "the unlinked mentions of this note" +org-vault/links)
     ("SPC n r P" "every property in use" +org-vault/properties)))
  "The guide's steps: (TITLE WHY (KEY WHAT COMMAND)...).")

;;;###autoload
(defun +org-roam/guide ()
  "The workflow from capture to a connected vault, step by step; every
command in it runs from here (RET or click)."
  (interactive)
  (with-current-buffer (get-buffer-create "*org-roam workflow*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "From a thought to a connected vault\n" 'face '(:weight bold :height 1.25))
              (propertize "RET or click a command to run it; SPC n r m has them all.\n" 'face 'shadow))
      (cl-loop for (title why . steps) in +org-roam-guide for i from 1
               do (insert "\n" (propertize (format "%d. %s" i title) 'face 'bold) "\n"
                          (propertize (concat "   " why) 'face 'shadow) "\n")
               (pcase-dolist (`(,key ,what ,cmd) steps)
                 (insert "   " (propertize (string-pad key 12) 'face 'help-key-binding) " ")
                 (if cmd
                     (insert-text-button what 'action (lambda (_) (call-interactively cmd)) 'follow-link t
                                         'help-echo (format "Run %s" cmd))
                   (insert what))
                 (insert "\n"))))
    (special-mode)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

;; Key by key, not as a (:prefix ("n r" …)): Doom owns that prefix (its
;; roam keys: f, i, a, d …); declaring it again here replaced them when
;; this file was loaded anew.
(map! :leader
      :desc "The workflow, step by step" "n r w" #'+org-roam/guide
      :desc "Org-roam menu"           "n r m" #'+org-roam-menu
      :desc "Make notes of files"     "n r I" #'+org-roam/init
      :desc "Org-roam by example"     "n r e" #'+org-roam/tour)

(provide '+org-roam)
;;; +org-roam.el ends here
