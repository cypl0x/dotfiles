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
                          (mapconcat (lambda (p) (format "→ %s" p)) places ", ")))))))))))

(map! :after org :map org-mode-map :localleader :desc "Capture (AI files it)" "C" #'+org/ai-capture)

(provide '+org-ai-capture)
;;; +org-ai-capture.el ends here
