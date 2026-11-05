;;; lisp/+org-links.el --- Org links that show what they point to -*- lexical-binding: t; -*-
;;
;; Org drew every link alike, blue and underlined: file:~/vault, a PDF, a
;; web page and a note looked the same.  Now each link carries an icon for
;; what it points to (org-modern's way: the text stays, the look says more):
;;   - a directory: a folder; a file: the icon of its type (nerd-icons)
;;   - a web page: its site's icon (GitHub, YouTube, Wikipedia …) or a globe
;;   - a note (id:, roam:), a manual (info:, man:, help:), mail, a DOI,
;;     a shell or Elisp link: each its own icon
;;   - a file link whose target doesn't exist: struck through, in red
;;   - hovering says what it is and whether it's there
;; A bare file:~/vault shows the folder in place of "file:".
;;
;;; Code:

(require 'cl-lib)

(declare-function nerd-icons-icon-for-file "ext:nerd-icons" (file &rest args))
(declare-function nerd-icons-icon-for-dir "ext:nerd-icons" (dir &rest args))
(declare-function nerd-icons-icon-for-url "ext:nerd-icons" (url &rest args))
(declare-function nerd-icons-mdicon "ext:nerd-icons" (name &rest args))
(declare-function org-link-set-parameters "ol" (type &rest parameters))
(defvar org-link-parameters)

(defvar-local +org-links-mode nil)

(defun +org-links--local-file (path)
  "PATH as a local file name, or nil (remote, or not a file name)."
  (let ((file (expand-file-name (car (split-string path "::")))))
    (unless (file-remote-p file) file)))

(defvar +org-links--exists (make-hash-table :test #'equal)
  "File → (TIME . EXISTS), so redisplay doesn't stat every link each time.")

(defun +org-links--exists-p (file)
  (let ((hit (gethash file +org-links--exists)))
    (if (and hit (< (- (float-time) (car hit)) 10))
        (cdr hit)
      (let ((exists (and (file-exists-p file) (if (file-directory-p file) 'dir 'file))))
        (puthash file (cons (float-time) exists) +org-links--exists)
        exists))))

(defun +org-links--icon (type path)
  "(ICON . STATE) for a TYPE link to PATH; STATE is missing, dir, file or nil."
  (let ((md (lambda (name) (nerd-icons-mdicon name :face 'org-link :v-adjust 0))))
    (pcase type
      ((or "file" "attachment" "docview" "pdf")
       (let* ((file (+org-links--local-file path))
              (state (if file (+org-links--exists-p file) 'remote)))
         (cons (cond ((eq state 'dir) (nerd-icons-icon-for-dir file :face 'org-link))
                     ((eq state 'remote) (funcall md "nf-md-server_network"))
                     ((null state) (funcall md "nf-md-file_hidden"))
                     (t (nerd-icons-icon-for-file file)))
               (or state 'missing))))
      ((or "http" "https") (cons (nerd-icons-icon-for-url (concat type ":" path)) nil))
      ((or "id" "roam") (cons (funcall md "nf-md-graph_outline") nil))
      ((or "info" "man" "woman" "help") (cons (funcall md "nf-md-book_open_variant") nil))
      ("mailto" (cons (funcall md "nf-md-email_outline") nil))
      ("doi" (cons (funcall md "nf-md-school_outline") nil))
      ((or "shell" "elisp") (cons (funcall md "nf-md-console") nil)))))

(defun +org-links--describe (type path state)
  (pcase state
    ('missing (format "%s:%s, which doesn't exist" type path))
    ('dir (format "Directory %s" path))
    ('file (format "File %s" path))
    ('remote (format "Remote file %s" path))
    (_ (format "%s:%s" type path))))

(defun +org-links--activator (type)
  "The `:activate-func' for links of TYPE."
  (lambda (start end path _bracketp)
    (when (and +org-links-mode (display-graphic-p) (require 'nerd-icons nil t))
      (pcase-let* ((`(,icon . ,state) (or (ignore-errors (+org-links--icon type path)) '(nil)))
                   ;; The first character shown (Org has hidden the brackets).
                   (visible (if (get-text-property start 'invisible)
                                (next-single-property-change start 'invisible nil end)
                              start)))
        (when (and icon (< visible end))
          (with-silent-modifications
            (if (and (equal type "file")
                     (string-prefix-p "file:" (buffer-substring-no-properties visible end)))
                ;; file:~/vault, bare or in brackets: the icon stands for "file:".
                (put-text-property visible (+ visible 5) 'display (concat icon " "))
              (put-text-property visible (1+ visible) 'display
                                 (concat icon " " (buffer-substring-no-properties visible (1+ visible)))))
            (put-text-property start end 'help-echo (+org-links--describe type path state))
            (when (eq state 'missing)
              (add-face-text-property visible end '(:strike-through t :inherit error)))))))))

(defconst +org-links-types
  '("file" "attachment" "http" "https" "id" "roam" "info" "man" "woman" "help" "mailto" "doi" "shell" "elisp")
  "Link types that get an icon.")

(defun +org-links-mode (&optional arg)
  "Icons on Org links for what they point to (see the file).  ARG as for
minor modes."
  (interactive (list (if current-prefix-arg (prefix-numeric-value current-prefix-arg) 'toggle)))
  (setq +org-links-mode (if (eq arg 'toggle) (not +org-links-mode) (or (null arg) (> (prefix-numeric-value arg) 0))))
  ;; The icons are display properties: font-lock removes them with the rest.
  (if +org-links-mode
      (add-to-list (make-local-variable 'font-lock-extra-managed-props) 'display)
    (setq-local font-lock-extra-managed-props (remq 'display font-lock-extra-managed-props)))
  (when (fboundp 'font-lock-flush) (font-lock-flush)))

(defun +org-links--register ()
  (dolist (type +org-links-types)
    (when (assoc type org-link-parameters)
      (org-link-set-parameters type :activate-func (+org-links--activator type)))))

(with-eval-after-load 'ol (+org-links--register))
;; roam: exists once org-roam is loaded.
(with-eval-after-load 'org-roam (+org-links--register))

(add-hook 'org-mode-hook #'+org-links-mode)

;;;; Completing links as you type them
;;
;; In [[file:… and a bare file:… (and the other link types that take a
;; path), the path completes from the disk, relative to the Org file, a
;; directory at a time: folders first, then newest first, so the screenshot
;; just taken is the first candidate; the directory is read again as you
;; type, so new files are there at once.  After [[ the link types complete.

(declare-function org-link-types "ol" ())

(defconst +org-links-path-types
  '("file" "file+sys" "file+emacs" "docview" "attachment" "pdf" "pdfview")
  "Link types whose target is a path.")

(defun +org-links--newest-first (base input)
  "A display sort for candidates under INPUT's directory (relative to BASE)."
  (let ((dir (expand-file-name (or (file-name-directory input) "") base)))
    (lambda (files)
      (if (or (file-remote-p dir) (> (length files) 2000))
          files
        (let ((time (lambda (f) (float-time (or (file-attribute-modification-time
                                                 (file-attributes (expand-file-name f dir)))
                                                0)))))
          (sort (copy-sequence files)
                (lambda (a b)
                  (let ((da (string-suffix-p "/" a)) (db (string-suffix-p "/" b)))
                    (cond ((equal a "../") nil) ((equal b "../") t)   ; up: last
                          ((and da (not db)) t) ((and db (not da)) nil)
                          (t (> (funcall time a) (funcall time b))))))))))))

(defun +org-links-capf ()
  "Complete Org link types after [[, and paths in file-like links."
  (let ((bol (line-beginning-position)))
    (save-excursion
      (cond
       ;; [[fi| → link types
       ((looking-back "\\[\\[\\([[:alpha:]+-]*\\)" bol)
        (let ((beg (match-beginning 1)))
          (list beg (point)
                (mapcar (lambda (ty) (concat ty ":")) (delete-dups (cons "file" (org-link-types))))
                :exclusive 'no)))
       ;; [[file:some/pa| or file:some/pa| → paths
       ((looking-back (concat "\\(?:\\[\\[\\|[[:space:](]\\|^\\)"
                              (regexp-opt +org-links-path-types) ":\\([^]\[\n \t]*\\)")
                      bol)
        (let* ((beg (match-beginning 1))
               (base (if buffer-file-name (file-name-directory buffer-file-name) default-directory)))
          (unless (or (file-remote-p base) (find-file-name-handler base 'file-attributes))
            (list beg (point)
                  (lambda (str pred action)
                    (if (eq action 'metadata)
                        `(metadata (category . file)
                                   (display-sort-function . ,(+org-links--newest-first base str)))
                      (let ((default-directory base)
                            ;; Not Emacs's lock and autosave files (.#x, #x#).
                            (pred (lambda (f)
                                    (and (not (string-match-p "\\`\\.?#" (file-name-nondirectory
                                                                     (directory-file-name f))))
                                         (not (member f '("./" ".")))
                                         (or (null pred) (funcall pred f))))))
                        (completion-file-name-table str pred action))))
                  :exclusive 'no
                  :exit-function (lambda (str _status)
                                   ;; A folder: go on into it.
                                   (when (string-suffix-p "/" str)
                                     (run-at-time 0 nil #'completion-at-point)))
                  :annotation-function
                  (lambda (cand)
                    (unless (string-suffix-p "/" cand)
                      (when-let* ((attrs (file-attributes
                                          (expand-file-name
                                           cand (expand-file-name
                                                 (or (file-name-directory
                                                      (buffer-substring-no-properties beg (point)))
                                                     "")
                                                 base)))))
                        (propertize (format-time-string "  %Y-%m-%d %H:%M"
                                                        (file-attribute-modification-time attrs))
                                    'face 'completions-annotations))))))))))))

(add-hook 'org-mode-hook
          (defun +org-links-capf-h ()
            (add-hook 'completion-at-point-functions #'+org-links-capf -50 t)))

(provide '+org-links)
;;; +org-links.el ends here
