;;; lisp/+org-vault.el --- Obsidian's panels and tools, for the vault -*- lexical-binding: t; -*-
;;
;; What Obsidian has beside its graph (lisp/+org-graph.el), here, reading
;; the vault the same way (file: and id: links, not org-roam's id-only
;; database):
;;
;;   eldoc      on a link to a note: its title and first lines in the echo
;;              area (Obsidian's page preview, without the mouse)
;;   SPC n r p  that note, read-only, in a window below (q closes it)
;;   SPC n r l  links of this note: backlinks (with the line), outgoing,
;;              unlinked mentions both ways; RET goes there
;;   SPC n r t  every tag in the vault, how often; RET lists what has it
;;   SPC n r P  every property, how often, its values; RET lists them
;;   SPC n r B  a base: the headings with these properties as a table; edit
;;              a cell, C-c C-c writes it back (Obsidian's Bases)
;;   SPC n r u  a new note named by the time (Obsidian's unique note)
;;   SPC n r o  record audio into the vault; again stops and links it here
;;   SPC n r W  publish the vault as a website (local HTML, an index, files)
;;   SPC n r Y  sync: commit the vault; pull and push if it has a remote
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function +org-graph-read "+org-graph" (&optional root))
(declare-function +org-graph-mentions "+org-graph" (graph))
(declare-function +org-graph--root "+org-graph" ())
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))
(declare-function org-roam-db-query "ext:org-roam-db" (sql &rest args))

;;;; The note a link points to

(defun +org-vault--link-target ()
  "The Org file the link at point points to, or nil."
  (let ((ctx (and (derived-mode-p 'org-mode) (save-match-data (org-element-context)))))
    (when (eq (org-element-type ctx) 'link)
      (let ((type (org-element-property :type ctx)) (path (org-element-property :path ctx)))
        (pcase type
          ("file" (let ((f (expand-file-name path (and buffer-file-name (file-name-directory buffer-file-name)))))
                    (and (string-suffix-p ".org" f) (file-readable-p f) f)))
          ("id" (ignore-errors (caar (org-roam-db-query [:select file :from nodes :where (= id $s1)] path)))))))))

(defun +org-vault--summary (file &optional lines)
  "FILE's title and its first LINES (3) lines of text."
  (with-temp-buffer
    (insert-file-contents file nil 0 6000)
    (goto-char (point-min))
    (let ((title (if (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t) (match-string 1) (file-name-base file)))
          text)
      (goto-char (point-min))
      (while (and (< (length text) (or lines 3)) (not (eobp)))
        (let ((l (string-trim (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))
          (unless (or (string-empty-p l) (string-prefix-p "#+" l) (string-prefix-p ":" l))
            (push l text)))
        (forward-line 1))
      (cons title (nreverse text)))))

(defun +org-vault-eldoc (callback &rest _)
  "Eldoc for a link to a note: its title and opening (CALLBACK gets it)."
  (when-let* ((file (+org-vault--link-target)))
    (pcase-let ((`(,title . ,text) (+org-vault--summary file)))
      (funcall callback (concat (propertize title 'face 'bold) "  "
                                (propertize (string-join text " · ") 'face 'shadow))))))

(add-hook 'org-mode-hook
          (defun +org-vault-eldoc-h ()
            (add-hook 'eldoc-documentation-functions #'+org-vault-eldoc nil t)))

;;;###autoload
(defun +org-vault/peek ()
  "The note the link at point points to, read-only, in a window below."
  (interactive)
  (let ((file (or (+org-vault--link-target) (user-error "No link to a note here"))))
    (with-current-buffer (find-file-noselect file)
      (view-mode 1)
      (display-buffer (current-buffer) '((display-buffer-below-selected) (window-height . 0.35))))))

;;;; Links of this note

(defun +org-vault--line-with (file target)
  "The first line of FILE linking to TARGET (a file), trimmed, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((name (regexp-quote (file-name-nondirectory target))))
      (goto-char (point-min))
      (when (re-search-forward (concat "\\[\\[\\(?:file\\|id\\):[^]]*" name) nil t)
        (string-trim (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))))

(defun +org-vault--button (file &optional label)
  (insert-text-button (or label (car (+org-vault--summary file 0)))
                      'action (lambda (_) (find-file-other-window file))
                      'follow-link t 'help-echo (abbreviate-file-name file)))

;;;###autoload
(defun +org-vault/links ()
  "This note's backlinks (with their lines), outgoing links and unlinked
mentions, file: links included, in a side window."
  (interactive)
  (let* ((me (or (and buffer-file-name (expand-file-name buffer-file-name)) (user-error "Not a file")))
         (graph (+org-graph-read))
         (edges (cdr graph))
         (mentions (+org-graph-mentions graph))
         (back (delete-dups (mapcar #'car (seq-filter (lambda (e) (equal (cdr e) me)) edges))))
         (out (delete-dups (mapcar #'cdr (seq-filter (lambda (e) (equal (car e) me)) edges))))
         (named-here (mapcar #'cdr (seq-filter (lambda (e) (equal (car e) me)) mentions)))
         (naming-me (mapcar #'car (seq-filter (lambda (e) (equal (cdr e) me)) mentions))))
    (with-current-buffer (get-buffer-create "*note links*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (car (+org-vault--summary me 0)) 'face '(:inherit bold :height 1.2)) "\n")
        (cl-flet ((section (title files &optional context)
                    (insert "\n" (propertize (format "%s (%d)" title (length files)) 'face 'bold) "\n")
                    (if (null files) (insert (propertize "  none\n" 'face 'shadow))
                      (dolist (f files)
                        (insert "  ")
                        (if (string-suffix-p ".org" f) (+org-vault--button f)
                          (+org-vault--button f (abbreviate-file-name f)))
                        (insert "\n")
                        (when-let* ((line (and context (funcall context f))))
                          (insert (propertize (format "    %s\n" (truncate-string-to-width line 90 nil nil "…"))
                                              'face 'shadow)))))))
          (section "Backlinks" back (lambda (f) (+org-vault--line-with f me)))
          (section "Outgoing" out)
          (section "Mentions you, unlinked" naming-me)
          (section "You mention, unlinked" named-here)))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer) '((display-buffer-in-side-window) (side . right) (window-width . 0.35))))))

;;;; Tags and properties of the vault

(defun +org-vault--files ()
  (directory-files-recursively (+org-graph--root) "\\.org\\'" nil
                               (lambda (d) (not (string-match-p "/\\.git\\'" d)))))

(defun +org-vault-tags ()
  "Every tag in the vault: hash TAG → list of (FILE POS TITLE)."
  (let ((h (make-hash-table :test #'equal)))
    (dolist (f (+org-vault--files))
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:[ \t]*\\(.+\\)$" nil t)
          (dolist (tag (split-string (match-string 1) "[: \t]+" t))
            (push (list f 1 (file-name-base f)) (gethash tag h))))
        (goto-char (point-min))
        (while (re-search-forward "^\\*+ \\(.*?\\)[ \t]+:\\([[:alnum:]_@#%:]+\\):[ \t]*$" nil t)
          (let ((title (match-string 1)) (pos (line-beginning-position)))
            (dolist (tag (split-string (match-string 2) ":" t))
              (push (list f pos title) (gethash tag h)))))))
    h))

(defun +org-vault-properties ()
  "Every property in the vault's drawers: hash KEY → list of (FILE POS VALUE)."
  (let ((h (make-hash-table :test #'equal)))
    (dolist (f (+org-vault--files))
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" nil t)
          (let ((end (save-excursion (re-search-forward "^[ \t]*:END:" nil t))))
            (while (and end (re-search-forward "^[ \t]*:\\([^: \t\n]+\\):[ \t]*\\(.*\\)$" end t))
              (unless (equal (match-string 1) "END")
                (push (list f (line-beginning-position) (string-trim (match-string 2))) (gethash (match-string 1) h))))))))
    h))

(defun +org-vault--list (title items fmt)
  "A buffer TITLE listing ITEMS (FILE POS LABEL) with FMT for the label."
  (with-current-buffer (get-buffer-create (format "*%s*" title))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize title 'face 'bold) "\n\n")
      (pcase-dolist (`(,file ,pos ,label) items)
        (insert "  ")
        (insert-text-button (funcall fmt label file)
                            'action (lambda (_) (find-file-other-window file) (goto-char pos))
                            'follow-link t 'help-echo (abbreviate-file-name file))
        (insert (propertize (format "  %s\n" (file-name-base file)) 'face 'shadow))))
    (special-mode)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

(defun +org-vault--counts (title table describe on-ret)
  (with-current-buffer (get-buffer-create (format "*%s*" title))
    (let ((inhibit-read-only t) rows)
      (erase-buffer)
      (maphash (lambda (k v) (push (cons k v) rows)) table)
      (insert (propertize title 'face 'bold) (propertize (format "   %d, RET lists them\n\n" (length rows)) 'face 'shadow))
      (dolist (row (sort rows (lambda (a b) (> (length (cdr a)) (length (cdr b))))))
        (insert (format "%4d  " (length (cdr row))))
        (insert-text-button (car row) 'action (let ((r row)) (lambda (_) (funcall on-ret r))) 'follow-link t)
        (insert (propertize (funcall describe row) 'face 'shadow) "\n")))
    (special-mode)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

;;;###autoload
(defun +org-vault/tags ()
  "Every tag of the vault, how often; RET lists the notes and headings."
  (interactive)
  (+org-vault--counts "Tags of the vault" (+org-vault-tags) (lambda (_) "")
                      (lambda (row) (+org-vault--list (format "Tagged %s" (car row)) (reverse (cdr row))
                                                      (lambda (label _) label)))))

;;;###autoload
(defun +org-vault/properties ()
  "Every property of the vault, how often and with which values; RET lists them."
  (interactive)
  (+org-vault--counts "Properties of the vault" (+org-vault-properties)
                      (lambda (row) (let ((vals (delete-dups (mapcar #'caddr (cdr row)))))
                                      (format "  %s%s" (string-join (seq-take vals 4) ", ") (if (cdr (nthcdr 3 vals)) " …" ""))))
                      (lambda (row) (+org-vault--list (format "Property %s" (car row)) (reverse (cdr row))
                                                      (lambda (value _) (if (string-empty-p value) "(empty)" value))))))

;;;; Bases: a table of notes by their properties, edited in place

(defvar-local +org-vault--base nil "(KEYS . ROWS) of this base: ROWS are (FILE POS TITLE VALUES...).")
(defvar-local +org-vault--base-filter nil "(KEY . VALUE) this base is filtered by.")

(defun +org-vault--base-rows (keys &optional filter)
  "Headings with any of KEYS: (FILE POS TITLE VALUE...), FILTER (KEY . VALUE)
keeping those whose KEY is VALUE."
  (let ((props (+org-vault-properties)) (seen (make-hash-table :test #'equal)) rows)
    (dolist (key keys)
      (pcase-dolist (`(,file ,pos ,_) (gethash key props))
        (puthash (cons file pos) t seen)))
    (maphash
     (lambda (loc _)
       (pcase-let ((`(,file . ,pos) loc))
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char pos)
           (let* ((heading (save-excursion (re-search-backward "^\\*+ \\(.*\\)$" nil t)))
                  (title (if heading (string-trim (replace-regexp-in-string ":[[:alnum:]_@#%:]+:[ \t]*\\'" "" (match-string 1)))
                           (file-name-base file)))
                  (start (or heading (point-min)))
                  (values (mapcar (lambda (k)
                                    (save-excursion
                                      (goto-char start)
                                      (if (re-search-forward (concat "^[ \t]*:" (regexp-quote k) ":[ \t]*\\(.*\\)$")
                                                             (save-excursion (or (re-search-forward "^[ \t]*:END:" nil t) (point-max))) t)
                                          (string-trim (match-string 1)) "")))
                                  keys)))
             (when (or (null filter)
                       (equal (nth (cl-position (car filter) keys :test #'equal) values) (cdr filter)))
               (push (append (list file start title) values) rows))))))
     seen)
    (sort rows (lambda (a b) (string< (nth 2 a) (nth 2 b))))))

;;;###autoload
(defun +org-vault/base (keys &optional filter)
  "A table of the vault's headings by the properties KEYS (asked), filtered
by FILTER (KEY=VALUE, optional).  Edit a cell and C-c C-c writes it back."
  (interactive
   (let* ((all (hash-table-keys (+org-vault-properties)))
          (keys (completing-read-multiple "Properties (comma between): " all nil t))
          (f (read-string "Only where (KEY=VALUE, empty: all): ")))
     (list keys (and (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" f) (cons (match-string 1 f) (match-string 2 f))))))
  (let ((rows (+org-vault--base-rows keys filter)))
    (with-current-buffer (get-buffer-create "*base*")
      (org-mode)
      (erase-buffer)
      (insert (format "#+title: Base: %s%s\n# C-c C-c writes edited cells back; C-c ^ sorts by the column at point.\n\n"
                      (string-join keys ", ") (if filter (format " where %s = %s" (car filter) (cdr filter)) "")))
      (insert "| Note | " (string-join keys " | ") " |\n|-\n")
      (dolist (row rows)
        (insert "| " (replace-regexp-in-string "|" "¦" (nth 2 row)) " | "
                (string-join (mapcar (lambda (v) (replace-regexp-in-string "|" "¦" v)) (nthcdr 3 row)) " | ") " |\n"))
      (forward-line -1) (org-table-align)
      (setq-local +org-vault--base (cons keys rows) +org-vault--base-filter filter)
      (local-set-key (kbd "C-c C-c") #'+org-vault-base-write)
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

(declare-function org-table-align "org-table" ())
(declare-function org-entry-put "org" (epom property value))
(declare-function org-table-get "org-table" (line column))

(defun +org-vault-base-write ()
  "Write the cells changed in this base back to their headings.
Each file is changed from the bottom up (an edit shifts what follows) in
its Emacs buffer, saved unless it had edits of yours waiting."
  (interactive)
  (pcase-let ((`(,keys . ,rows) +org-vault--base) (changes nil))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "^|-")
      (forward-line 1)
      (dolist (row rows)
        (let ((cells (mapcar #'string-trim
                             (cdr (split-string (buffer-substring-no-properties
                                                 (line-beginning-position) (line-end-position))
                                                "|" t)))))
          (cl-loop for key in keys for old in (nthcdr 3 row) for new in cells
                   for value = (replace-regexp-in-string "¦" "|" new)
                   unless (equal old value)
                   do (push (list (nth 0 row) (nth 1 row) key value) changes)))
        (forward-line 1)))
    (dolist (file (delete-dups (mapcar #'car changes)))
      (with-current-buffer (find-file-noselect file)
        (let ((yours (buffer-modified-p)))
          (dolist (c (sort (seq-filter (lambda (c) (equal (car c) file)) changes)
                           (lambda (a b) (> (nth 1 a) (nth 1 b)))))
            (save-excursion (goto-char (nth 1 c)) (org-entry-put (point) (nth 2 c) (nth 3 c))))
          (unless yours (save-buffer)))))
    (message "%d cell%s written back" (length changes) (if (= 1 (length changes)) "" "s"))
    (when changes (+org-vault/base keys +org-vault--base-filter))))

;;;; Publish: the vault as a website, locally

(defvar org-publish-project-alist)
(defvar org-export-with-broken-links)
(declare-function org-publish "ox-publish" (project &optional force async))

;;;###autoload
(defun +org-vault/publish (dir)
  "The vault as a website in DIR (asked; ~/vault-site/ by default): every
note as HTML with its links working, an index of all of them, attachments
copied.  Local only; nothing is uploaded."
  (interactive (list (read-directory-name "Publish the vault into: " "~/vault-site/")))
  (require 'ox-publish)
  (let* ((root (+org-graph--root))
         (dir (file-name-as-directory (expand-file-name dir)))
         (org-publish-project-alist
          `(("vault-notes" :base-directory ,root :base-extension "org" :recursive t
             :publishing-directory ,dir :publishing-function org-html-publish-to-html
             :exclude "\\(?:\\`\\|/\\)\\.git/" :with-toc t :section-numbers nil
             :auto-sitemap t :sitemap-filename "index.org" :sitemap-title "The vault"
             :sitemap-sort-files alphabetically)
            ("vault-files" :base-directory ,root :recursive t :publishing-directory ,dir
             :base-extension "png\\|jpe?g\\|gif\\|svg\\|pdf\\|flac\\|css"
             :exclude "\\(?:\\`\\|/\\)\\.git/" :publishing-function org-publish-attachment)
            ("vault" :components ("vault-notes" "vault-files")))))
    ;; A vault has links to what isn't there (yet): marked, not fatal.
    (let ((org-export-with-broken-links 'mark)) (org-publish "vault" t))
    (message "Published to %s (open %sindex.html)" (abbreviate-file-name dir) (abbreviate-file-name dir))
    dir))

;;;; Sync: commit the vault, and push where it has somewhere to go

;;;###autoload
(defun +org-vault/sync ()
  "Commit the vault's changes; if it has a remote, pull (rebase) and push."
  (interactive)
  (let ((default-directory (+org-graph--root)))
    (unless (file-directory-p ".git") (user-error "The vault isn't a git repository"))
    (let ((changed (not (string-empty-p
                         (string-trim (shell-command-to-string "git status --porcelain"))))))
      (when changed
        (call-process "git" nil nil nil "add" "-A")
        (call-process "git" nil nil nil "commit" "-q" "-m" (format-time-string "vault: %F %H:%M")))
      (cond ((string-empty-p (string-trim (shell-command-to-string "git remote")))
             (message "%s; the vault has no remote to sync with (git remote add …)"
                      (if changed "Committed" "Nothing to commit")))
            ((and (zerop (call-process "git" nil nil nil "pull" "-q" "--rebase"))
                  (zerop (call-process "git" nil nil nil "push" "-q")))
             (message "Vault synced"))
            (t (message "Sync stopped: see git status in %s"
                        (abbreviate-file-name default-directory)))))))

;;;; A note named by the time

;;;###autoload
(defun +org-vault/unique-note ()
  "A new note in the vault named by the time (as Obsidian's unique note)."
  (interactive)
  (let* ((stamp (format-time-string "%Y%m%d%H%M%S"))
         (file (expand-file-name (concat stamp ".org") (+org-graph--root))))
    (find-file file)
    (insert (format "#+title: %s\n\n" (format-time-string "%Y-%m-%d %H:%M")))
    (when (fboundp 'evil-insert-state) (evil-insert-state))))

;;;; Audio into the vault

(defvar +org-vault--recording nil "(PROCESS FILE START BUFFER POINT) of the recording running.")

;;;###autoload
(defun +org-vault/record ()
  "Record audio (FLAC) into the vault's audio/; again to stop, which links
the recording at point (where you started)."
  (interactive)
  (if-let* ((rec +org-vault--recording))
      (pcase-let ((`(,proc ,file ,start ,buf ,pos) rec))
        (setq +org-vault--recording nil)
        (when (process-live-p proc) (interrupt-process proc))
        (let ((secs (round (float-time (time-subtract nil start)))))
          (run-at-time 0.5 nil
                       (lambda ()
                         (when (buffer-live-p buf)
                           (with-current-buffer buf
                             (save-excursion
                               (goto-char pos)
                               (insert (format "[[file:%s][Recording %s (%d:%02d)]]"
                                               (file-relative-name file (file-name-directory (or buffer-file-name file)))
                                               (format-time-string "%H:%M" start) (/ secs 60) (% secs 60))))))
                         (message "Recorded %d s: %s" secs (abbreviate-file-name file))))))
    (unless (executable-find "pw-record") (user-error "pw-record (PipeWire) isn't installed"))
    (let* ((dir (expand-file-name "audio/" (+org-graph--root)))
           (file (expand-file-name (format-time-string "%Y-%m-%d_%H%M%S.flac") dir)))
      (make-directory dir t)
      (setq +org-vault--recording
            (list (start-process "vault-recording" nil "pw-record" file) file (current-time)
                  (current-buffer) (point-marker)))
      (message "● Recording into %s; SPC n r o again stops and links it here" (abbreviate-file-name file)))))

(map! :leader
      :desc "Peek the linked note"  "n r p" #'+org-vault/peek
      :desc "Links of this note"    "n r l" #'+org-vault/links
      :desc "Tags of the vault"     "n r t" #'+org-vault/tags
      :desc "Properties of the vault" "n r P" #'+org-vault/properties
      :desc "Base: notes by properties" "n r B" #'+org-vault/base
      :desc "Unique note (by time)" "n r u" #'+org-vault/unique-note
      :desc "Publish the vault (HTML)" "n r W" #'+org-vault/publish
      :desc "Sync the vault (git)"  "n r Y" #'+org-vault/sync
      ;; o, not a: SPC n r a is Doom's random note.
      :desc "Record audio here"     "n r o" #'+org-vault/record)

(provide '+org-vault)
;;; +org-vault.el ends here
