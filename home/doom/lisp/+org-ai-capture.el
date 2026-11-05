;;; lisp/+org-ai-capture.el --- Capture headings; AI files them where they belong -*- lexical-binding: t; -*-
;;
;; SPC m C in an Org buffer: write one or more headings (TODO, tags and text
;; under them as you like) in a small Org buffer; C-c C-c and each goes under
;; the heading of this buffer it belongs to, or under a new one where none
;; fits.  C-c C-k cancels.
;;
;; The model only places: it sees the outline (headings, numbered) and what
;; you wrote, and answers with numbers.  Your text is put in by Org itself
;; (`org-paste-subtree', at the level under its parent), as you wrote it; a
;; number that isn't a heading of the buffer is refused.  One undo takes the
;; whole capture back.
;;
;;; Code:

(declare-function familiar-request "familiar" (prompt &rest args))
(declare-function org-map-entries "org" (func &optional match scope &rest skip))
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-current-level "org" ())
(declare-function org-end-of-subtree "org" (&optional invisible-ok to-heading element))
(declare-function org-paste-subtree "org" (&optional level tree for-yank remove))

(defconst +org-ai-capture-system
  "You file new Org entries into an existing Org outline.  The outline's \
headings are numbered [N], indented by level.  For each new entry, numbered \
{K}, choose the heading it belongs under.  Reply with JSON only: \
{\"placements\": [{\"entry\": K, \"under\": N}]} where N is a heading number \
from the outline; when no heading fits, {\"entry\": K, \"new\": \"title of a \
new heading\", \"new_under\": N or 0 for the top level}.  Place every entry \
once.  Prefer the most specific fitting heading.  Judge by meaning, not \
words alone."
  "System prompt of the capture's placement.")

(defun +org-ai-capture--outline ()
  "This buffer's headings: list of (MARKER LEVEL TITLE)."
  (let (out)
    (save-restriction
      (widen)
      (org-map-entries
       ;; Insertion type t: an entry put in right before this heading (at the
       ;; end of the one above) leaves the marker on this heading.
       (lambda () (push (list (copy-marker (point) t) (org-current-level) (org-get-heading t t t t)) out))))
    (nreverse out)))

(defun +org-ai-capture--entries (text)
  "TEXT split into Org subtrees (strings starting with stars), at the level
of its first heading.  Lines without stars become headings of their own."
  (let ((text (string-trim text)))
    (if (string-match "\\`\\(\\*+\\) " text)
        (let ((re (format "^\\*\\{%d\\} " (length (match-string 1 text))))
              parts)
          (with-temp-buffer
            (insert text "\n")
            (let ((end (point-max)))
              (while (re-search-backward re nil t)
                (push (string-trim-right (buffer-substring (point) end)) parts)
                (setq end (point)))))
          parts)
      (mapcar (lambda (l) (concat "* " (string-trim l)))
              (seq-remove #'string-blank-p (split-string text "\n"))))))

(defun +org-ai-capture--request (outline entries)
  "The placement request for OUTLINE and ENTRIES."
  (concat
   "Outline:\n"
   (cl-loop for (_ level title) in outline for n from 1
            concat (format "%s[%d] %s\n" (make-string (* 2 (1- level)) ?\s) n title))
   "\nNew entries:\n"
   (cl-loop for e in entries for k from 1
            concat (format "{%d} %s\n" k (replace-regexp-in-string "\n" "\n    " e)))))

(defun +org-ai-capture--plan (answer outline entries)
  "Placements of ANSWER checked against OUTLINE and ENTRIES:
list of (ENTRY-TEXT . WHERE), WHERE a heading of OUTLINE or (new TITLE PARENT)
with PARENT a heading or nil for the top.  Entries not placed, or placed
under a number that doesn't exist, go to the top level as they are."
  (let ((heading (lambda (n) (and (integerp n) (<= 1 n (length outline)) (nth (1- n) outline))))
        plan)
    (cl-loop for e in entries for k from 1
             do (let* ((p (seq-find (lambda (p) (eql (plist-get p :entry) k))
                                    (plist-get answer :placements)))
                       (under (and p (funcall heading (plist-get p :under))))
                       (new (and p (stringp (plist-get p :new))
                                 (not (string-blank-p (plist-get p :new)))
                                 (plist-get p :new))))
                  (push (cons e (cond (under under)
                                      (new (list 'new (string-trim new)
                                                 (funcall heading (plist-get p :new_under))))
                                      (t nil)))
                        plan)))
    (nreverse plan)))

(defun +org-ai-capture--apply (plan)
  "Put PLAN's entries in place, new parents first made; as one change.
Return the places, for the message."
  (let ((made (make-hash-table :test #'equal))
        (group (prepare-change-group))
        places)
    (activate-change-group group)
    (unwind-protect
        (save-excursion
          (pcase-dolist (`(,entry . ,where) plan)
            (let ((parent
                   (pcase where
                     (`(new ,title ,under)
                      (or (gethash (cons title under) made)
                          (puthash (cons title under)
                                   (+org-ai-capture--insert (concat "* " title) under)
                                   made)))
                     ((and `(,m . ,_) (guard (markerp m))) where)
                     (_ nil))))
              (+org-ai-capture--insert entry parent)
              (push (if parent (nth 2 parent) "top level") places))))
      (accept-change-group group)
      (undo-amalgamate-change-group group))
    (nreverse places)))

(defun +org-ai-capture--insert (tree parent)
  "Insert subtree TREE at the end of PARENT (MARKER LEVEL TITLE), one level
below it, or at the end of the buffer when PARENT is nil.  Return the new
heading as (MARKER LEVEL TITLE)."
  (if parent
      (progn (goto-char (car parent))
             (org-end-of-subtree t t))
    (goto-char (point-max)))
  (unless (bolp) (insert "\n"))
  (let ((level (if parent (1+ (nth 1 parent)) 1))
        (beg (point)))
    (org-paste-subtree level tree)
    (goto-char beg)
    (list (copy-marker (point) t) level (org-get-heading t t t t))))

;;;; The capture buffer

(defvar-local +org-ai-capture--target nil "The Org buffer captured into.")

(defvar +org-ai-capture-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'+org-ai-capture-finish)
    (define-key map (kbd "C-c C-k") #'+org-ai-capture-cancel)
    map))

(define-minor-mode +org-ai-capture-mode
  "Writing entries for `+org/ai-capture': C-c C-c files them, C-c C-k cancels."
  :keymap +org-ai-capture-mode-map)

;;;###autoload
(defun +org/ai-capture ()
  "Write headings to file into this Org buffer, where they belong (AI)."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not an Org buffer"))
  (let ((target (current-buffer)))
    (pop-to-buffer (get-buffer-create (format "*capture → %s*" (buffer-name target))))
    (unless (derived-mode-p 'org-mode) (org-mode))
    (+org-ai-capture-mode 1)
    (setq +org-ai-capture--target target
          header-line-format
          (substitute-command-keys
           (format " Headings for %s; AI files them   \\<+org-ai-capture-mode-map>\\[+org-ai-capture-finish] file · \\[+org-ai-capture-cancel] cancel"
                   (buffer-name target))))
    (when (fboundp 'evil-insert-state) (evil-insert-state))))

(defun +org-ai-capture-cancel ()
  (interactive)
  (quit-window t))

(defun +org-ai-capture-finish ()
  "File what was written into the target buffer."
  (interactive)
  (let* ((target +org-ai-capture--target)
         (entries (+org-ai-capture--entries (buffer-string))))
    (unless entries (user-error "Nothing written"))
    (when (eq target 'vault) (+vault-capture--finish entries))
    (unless (eq target 'vault)
    (unless (buffer-live-p target) (user-error "The Org buffer is gone"))
    (let ((outline (with-current-buffer target (+org-ai-capture--outline))))
      (quit-window t)
      (message "Filing %d entr%s…" (length entries) (if (cdr entries) "ies" "y"))
      (familiar-request
       (+org-ai-capture--request outline entries)
       :task 'capture :system +org-ai-capture-system
       :callback
       (lambda (response _info)
         (when (and (stringp response) (buffer-live-p target))
           (let ((answer (ignore-errors
                           (json-parse-string
                            (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" response)
                            :object-type 'plist :array-type 'list))))
             (with-current-buffer target
               (let ((places (+org-ai-capture--apply
                              (+org-ai-capture--plan answer outline entries))))
                 (message "Filed: %s  (undo takes it back)"
                          (mapconcat (lambda (p) (format "→ %s" p)) places ", "))))))))))))


;;;; Into the whole vault

;; SPC n x, from anywhere: the same capture buffer, but filed across the
;; vault (`org-directory'): the model sees every Org file there and its
;; headings (three levels deep), numbered, and puts each entry under a
;; heading, at the top level of a file, under a new heading, or into a new
;; file it names.  Files are only made inside the vault.  A buffer you have
;; unsaved edits in gets the entry but isn't saved (your edits stay yours to
;; save); the others are saved.  Undo, per file, takes an entry back.

(defvar org-directory)
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))

(defcustom +vault-capture-max-depth 3
  "Heading levels of vault files the capture shows the model."
  :type 'natnum :group 'org)

(defcustom +vault-capture-exclude "\\(?:/\\.\\|/roam/daily/\\|~\\'\\|#\\|\\.org_archive\\'\\)"
  "Vault files the capture leaves out (regexp on the file name)."
  :type 'regexp :group 'org)

(defconst +vault-capture-system
  "You file new Org entries into a vault of Org files.  The outline lists \
the files, [N] file: title, and under each its headings, [N] with \
indentation by level.  For each new entry, numbered {K}, choose where it \
belongs.  Reply with JSON only: {\"placements\": [...]} with one object per \
entry, either {\"entry\": K, \"under\": N} (N a heading, or a file: then it \
goes at that file's top level), or {\"entry\": K, \"new\": \"title of a new \
heading\", \"new_under\": N} (N a heading or a file), or {\"entry\": K, \
\"new_file\": \"short-name.org\", \"title\": \"File title\"} when nothing in \
the vault fits at all.  Prefer the most specific fitting heading; make new \
headings and files rarely.  Judge by meaning."
  "System prompt of the vault capture's placement.")

(defun +vault-capture--files ()
  (seq-remove (lambda (f) (string-match-p +vault-capture-exclude f))
              (directory-files-recursively (expand-file-name org-directory) "\\.org\\'" nil
                                           (lambda (d) (not (string-match-p "/\\." d))))))

(defun +vault-capture--outline ()
  "The vault: list of (KIND FILE MARKER-OR-NIL LEVEL TITLE), KIND file or heading."
  (let (out)
    (dolist (file (+vault-capture--files))
      (let ((buf (find-file-noselect file t)))
        (with-current-buffer buf
          (push (list 'file file nil 0
                      (or (save-excursion (goto-char (point-min))
                                          (and (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" 4000 t)
                                               (match-string-no-properties 1)))
                          (file-name-base file)))
                out)
          (save-restriction
            (widen)
            (org-map-entries
             (lambda ()
               (when (<= (org-current-level) +vault-capture-max-depth)
                 (push (list 'heading file (copy-marker (point) t) (org-current-level)
                             (org-get-heading t t t t))
                       out))))))))
    (nreverse out)))

(defun +vault-capture--request (outline entries)
  (concat
   "Vault:\n"
   (cl-loop for (kind file _ level title) in outline for n from 1
            concat (if (eq kind 'file)
                       (format "[%d] %s: %s\n" n (file-relative-name file org-directory) title)
                     (format "%s[%d] %s\n" (make-string (* 2 level) ?\s) n title)))
   "\nNew entries:\n"
   (cl-loop for e in entries for k from 1
            concat (format "{%d} %s\n" k (replace-regexp-in-string "\n" "\n    " e)))))

(defun +vault-capture--new-file (name title)
  "A new vault file NAME (made safe, inside the vault) with TITLE."
  (let* ((base (replace-regexp-in-string "[^[:alnum:]._-]+" "-" (file-name-nondirectory name)))
         (base (if (string-suffix-p ".org" base) base (concat base ".org")))
         (file (expand-file-name base org-directory)))
    (unless (file-exists-p file)
      (with-temp-file file (insert "#+title: " (or title (file-name-base base)) "\n\n")))
    file))

(defun +vault-capture--file (answer outline entries)
  "Put ENTRIES where ANSWER says.  Returns the places for the message."
  (let ((item (lambda (n) (and (integerp n) (<= 1 n (length outline)) (nth (1- n) outline))))
        (dirty (cl-loop for b in (buffer-list)
                        when (and (buffer-file-name b) (buffer-modified-p b)) collect b))
        touched places)
    (cl-loop
     for e in entries for k from 1
     do (let* ((p (seq-find (lambda (p) (eql (plist-get p :entry) k)) (plist-get answer :placements)))
               (under (and p (funcall item (plist-get p :under))))
               (new (and p (stringp (plist-get p :new)) (string-trim (plist-get p :new))))
               (new-under (and p (funcall item (plist-get p :new_under))))
               (new-file (and p (stringp (plist-get p :new_file)) (plist-get p :new_file)))
               ;; Where: a file and a parent heading (or nil: its top level).
               (where
                (cond (under (list (nth 1 under) (and (eq (car under) 'heading) under)))
                      ((and new new-under) (list (nth 1 new-under) (and (eq (car new-under) 'heading) new-under) new))
                      (new-file (list (+vault-capture--new-file new-file (plist-get p :title)) nil))
                      ;; Not placed: the inbox, at its top level.
                      (t (list (expand-file-name "inbox.org" org-directory) nil)))))
          (pcase-let ((`(,file ,parent ,new-title) where))
            (with-current-buffer (find-file-noselect file)
              (save-excursion
                (let* ((parent (and parent (list (nth 2 parent) (nth 3 parent) (nth 4 parent))))
                       (parent (if new-title (+org-ai-capture--insert (concat "* " new-title) parent) parent)))
                  (let ((entry (+org-ai-capture--insert e parent)))
                    (push (list (concat (file-relative-name file org-directory)
                                        (if parent (concat " › " (nth 2 parent)) ""))
                                (car entry) (nth 2 entry))
                          places))))
              (cl-pushnew (current-buffer) touched)))))
    (dolist (b touched)
      (unless (memq b dirty) (with-current-buffer b (save-buffer))))
    (cons (nreverse places) (seq-filter (lambda (b) (memq b dirty)) touched))))

;;;###autoload
(defun +vault/ai-capture ()
  "Write entries; AI files each into the vault where it belongs (see above)."
  (interactive)
  (pop-to-buffer (get-buffer-create "*capture → vault*"))
  (unless (derived-mode-p 'org-mode) (org-mode))
  (+org-ai-capture-mode 1)
  (setq +org-ai-capture--target 'vault
        header-line-format
        (substitute-command-keys
         " Entries for the vault; AI files each where it belongs   \\<+org-ai-capture-mode-map>\\[+org-ai-capture-finish] file · \\[+org-ai-capture-cancel] cancel"))
  (when (fboundp 'evil-insert-state) (evil-insert-state)))

(defun +vault-capture--finish (entries &optional then)
  "File ENTRIES (Org subtrees as text) into the vault; THEN, if given, gets
the filed places (as in the report) once they are in."
  ;; The vault as it is now: the answer comes later.
  (let ((outline (+vault-capture--outline)) (vault org-directory))
    (quit-window t)
    (message "Filing %d entr%s into the vault…" (length entries) (if (cdr entries) "ies" "y"))
    (familiar-request
     (+vault-capture--request outline entries)
     :task 'capture :system +vault-capture-system
     :callback
     (lambda (response _info)
       (when (stringp response)
         (let* ((answer (ignore-errors
                          (json-parse-string
                           (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" response)
                           :object-type 'plist :array-type 'list)))
                (result (let ((org-directory vault)) (+vault-capture--file answer outline entries))))
           (when then (funcall then (car result)))
           (+vault-capture-report (car result))
           (message "Filed: %s%s"
                    (mapconcat (lambda (p) (format "→ %s" (car p))) (car result) ", ")
                    (if (cdr result)
                        (format "  (not saved, you have edits there: %s)"
                                (mapconcat #'buffer-name (cdr result) ", "))
                      ""))))))))


;;;; Where it all went: the report

;; After filing, *Filed into the vault* lists each entry and its place as a
;; link (RET or a click goes there); x takes an entry back out where it
;; landed, r refiles it (the AI chooses again).
(declare-function org-cut-subtree "org" (&optional n))
(declare-function org-copy-subtree "org" (&optional n cut force-store-markers nosubtrees))
(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(defvar org-subtree-clip)
(declare-function org-reveal "org")
(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))

(defun +vault-capture--report-line-entry ()
  (or (get-text-property (line-beginning-position) '+vault-entry) (user-error "No filed entry on this line")))

(defun +vault-capture-report-visit ()
  "Go to the filed entry on this line."
  (interactive)
  (let ((m (cadr (+vault-capture--report-line-entry))))
    (unless (buffer-live-p (marker-buffer m)) (user-error "Its buffer is gone"))
    (pop-to-buffer (marker-buffer m)) (goto-char m) (org-reveal) (recenter 3)))

(defun +vault-capture-report-remove ()
  "Take the filed entry on this line back out of where it landed."
  (interactive)
  (pcase-let ((`(,place ,m ,title) (+vault-capture--report-line-entry)))
    (when (y-or-n-p (format "Remove \"%s\" from %s? " title place))
      (with-current-buffer (marker-buffer m)
        (save-excursion (goto-char m) (org-cut-subtree)))
      (let ((inhibit-read-only t))
        (put-text-property (line-beginning-position) (line-end-position) 'face 'shadow)
        (put-text-property (line-beginning-position) (line-end-position) '+vault-entry nil))
      (message "Removed (it's on the kill ring: p puts it back)"))))

(defun +vault-capture-report-refile ()
  "Let the AI place the entry on this line again."
  (interactive)
  (let ((m (cadr (+vault-capture--report-line-entry))))
    (with-current-buffer (marker-buffer m)
      (save-excursion (goto-char m) (+vault/ai-refile)))))

(defvar-keymap +vault-capture-report-mode-map
  :parent special-mode-map
  "RET" #'+vault-capture-report-visit  "<mouse-1>" #'+vault-capture-report-visit
  "x" #'+vault-capture-report-remove  "r" #'+vault-capture-report-refile)

(define-derived-mode +vault-capture-report-mode special-mode "Filed"
  "Where the AI filed your entries: RET goes there, x takes one out, r refiles.")

(defun +vault-capture-report (places)
  "Show PLACES ((PLACE MARKER TITLE) …) of entries just filed."
  (with-current-buffer (get-buffer-create "*Filed into the vault*")
    (let ((inhibit-read-only t))
      (unless (derived-mode-p '+vault-capture-report-mode) (+vault-capture-report-mode))
      (goto-char (point-min))
      (insert (propertize (format-time-string "%H:%M  ") 'face 'shadow)
              (propertize (format "%d filed" (length places)) 'face 'bold)
              (propertize "   RET go there · x take it out · r refile\n" 'face 'shadow))
      (dolist (p places)
        (insert (propertize (format "  %s  →  %s\n" (nth 2 p) (car p))
                            '+vault-entry p 'mouse-face 'highlight 'help-echo "RET or click: go there")))
      (insert "\n"))
    (with-eval-after-load 'evil (evil-make-overriding-map +vault-capture-report-mode-map 'normal))
    (display-buffer (current-buffer))))

;;;; AI refile: the item at point to where it belongs

;;;###autoload
(defun +vault/ai-refile ()
  "Move the Org item at point (with its subtree) to where it belongs in the
vault, chosen by the AI like a capture.  It is put in at the new place
first and only then removed from here, so a failed request loses nothing."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not in Org"))
  (save-excursion
    (org-back-to-heading t)
    (let* ((origin (copy-marker (point)))
           (text (progn (org-copy-subtree) org-subtree-clip)))
      (+vault-capture--finish
       (list text)
       (lambda (places)
         (when (and places (buffer-live-p (marker-buffer origin)))
           (with-current-buffer (marker-buffer origin)
             (save-excursion (goto-char origin) (org-cut-subtree)))
           (message "Moved to %s" (car (car places)))))))))

;;;###autoload
(defun +vault/ai-capture-region (beg end)
  "Capture the region BEG..END into the vault (each Org heading in it is an
entry; plain text becomes one), in the capture buffer to look over first."
  (interactive "r")
  (let ((text (buffer-substring-no-properties beg end)))
    (+vault/ai-capture)
    (insert (if (string-match-p "\\`[ \t\n]*\\*+ " text) text (concat "* " (string-trim text) "\n")))
    (goto-char (point-min))))

(map! :leader :desc "Refile: AI moves this item in the vault" "n X" #'+vault/ai-refile)
(map! :after org :map org-mode-map :localleader :desc "Refile (AI places it)" "R" #'+vault/ai-refile)
(defun +vault/ai-capture-dwim (&optional beg end)
  "Capture into the vault; with an active region, its text (BEG..END)."
  (interactive (and (use-region-p) (list (region-beginning) (region-end))))
  (if beg (+vault/ai-capture-region beg end) (+vault/ai-capture)))
(map! :leader :desc "Capture into the vault (AI files it)" "n x" #'+vault/ai-capture-dwim)
(map! :after org :map org-mode-map :localleader :desc "Capture (AI files it)" "C" #'+org/ai-capture)

(provide '+org-ai-capture)
;;; +org-ai-capture.el ends here
