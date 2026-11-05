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

;;;; A link shows its real text while point is on it
;;
;; Links read as their description (or an icon); to edit one it has to show
;; what it is.  org-appear revealed links only in insert state (its manual
;; trigger, which keeps prose from wiggling), so a link flipped between its
;; two forms as states changed and couldn't be edited where it stood.  Now
;; a link is shown as written, [[target][description]], as long as point is
;; on it, in any state, at once; leaving it hides it again.  The same for
;; every markup object: =verbatim=, ~code~, *bold*, /italic/, _underline_,
;; +strike+ show their markers while point is in them.
;;
;; Editing inside one used to hide it again: typing makes font-lock
;; refontify the line during redisplay, after the command, and that hid
;; the target anew.  Now font-lock itself leaves the object at point shown
;; (an advice after it refontifies), so it stays while you edit.

(defvar-local +org-links--revealed nil "(BEG . END) markers of the object shown as written.")
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))

(defconst +org-links--reveal-types '(link bold italic underline strike-through verbatim code)
  "Org objects shown as written while point is in them.")

(defconst +org-links--markup-faces '(org-link bold italic underline org-verbatim org-code)
  "Faces that mark such an object, for a cheap first test.")

(defun +org-links--marked-p (pos)
  (and (>= pos (point-min)) (< pos (point-max))
       (let ((face (get-text-property pos 'face)))
         (or (cl-intersection (ensure-list face) +org-links--markup-faces)
             (and (consp face) (plist-get face :strike-through))
             (get-text-property pos 'invisible)))))

(defun +org-links--link-at-point ()
  "Bounds (BEG . END) of the link or markup object at point, or nil.
Cheap off markup: Org's parser only runs where its faces are."
  (when (or (+org-links--marked-p (point)) (+org-links--marked-p (1- (point))))
    (let ((ctx (save-match-data (org-element-context))))
      (when (memq (org-element-type ctx) +org-links--reveal-types)
        (cons (org-element-property :begin ctx)
              (- (org-element-property :end ctx) (or (org-element-property :post-blank ctx) 0)))))))

(defun +org-links--unhide (beg end)
  (with-silent-modifications
    (remove-text-properties beg end '(invisible nil display nil composition nil))))

(defun +org-links-reveal-h ()
  "Show the object at point as written; hide the one left."
  (let ((shown +org-links--revealed))
    (unless (and shown (<= (car shown) (point) (cdr shown)))
      (when shown
        (setq +org-links--revealed nil)
        (font-lock-flush (car shown) (cdr shown))
        (set-marker (car shown) nil) (set-marker (cdr shown) nil))
      (when-let* ((bounds (+org-links--link-at-point)))
        (+org-links--unhide (car bounds) (cdr bounds))
        (setq +org-links--revealed (cons (copy-marker (car bounds)) (copy-marker (cdr bounds) t)))))))

(defun +org-links-keep-revealed-a (beg end &rest _)
  "After font-lock fontifies BEG..END: the object at point stays shown."
  (when-let* ((shown +org-links--revealed)
              ((< (car shown) end))
              ((> (cdr shown) beg)))
    (+org-links--unhide (car shown) (cdr shown))))

(advice-add 'font-lock-default-fontify-region :after #'+org-links-keep-revealed-a)

(add-hook 'org-mode-hook
          (defun +org-links-reveal-setup-h ()
            (add-hook 'post-command-hook #'+org-links-reveal-h nil t)))

;;;; RET on an image link: its preview, whatever the link's form
;;
;; Doom's RET on an image link toggles its preview through `org-link-preview'
;; without an argument, which previews links without a description only:
;; file:shot.png showed inline, [[file:shot.png][a description]] did nothing.
;; Org's own C-u 1 includes described links; RET on a link now asks for that.

(defun +org-links-preview-described-a (args)
  "Filter for `org-link-preview' ARGS: include described links when the call
is for the link at point (Doom's RET passes that link's region)."
  (if (and (null (car args)) (cadr args)
           (derived-mode-p 'org-mode)
           (eq (org-element-type (save-match-data (org-element-context))) 'link))
      (cons 1 (cdr args))
    args))

;; RET inside a link (not at its end) acts on it in insert state too, as in
;; normal state: shows an image inline or visits the target.  Insert
;; state's RET only broke the line there.  At a link's end, a new line.
(declare-function +org/dwim-at-point "ext:org" (&optional arg))

(defun +org-links-return-a (fn &rest args)
  "Around `+org/return' (FN, ARGS): on a link, do what RET does in normal state."
  (let ((ctx (and (derived-mode-p 'org-mode) (save-match-data (org-element-context)))))
    (if (and (eq (org-element-type ctx) 'link)
             (< (org-element-property :begin ctx) (point)
                (- (org-element-property :end ctx) (or (org-element-property :post-blank ctx) 0))))
        (+org/dwim-at-point)
      (apply fn args))))

(with-eval-after-load 'org
  (when (fboundp '+org/return)
    (advice-add '+org/return :around #'+org-links-return-a)))

;; All of a buffer's images at once: Org 9.8 renamed org-toggle-inline-images
;; to org-link-preview (C-c C-x C-v), where the whole buffer takes C-u C-u
;; and described links C-u 11.  SPC m l v: one key, every image link.
(defvar org-link-preview-overlays)
(declare-function org-link-preview "ol" (&optional arg beg end))

(defun +org/toggle-images ()
  "Show every image link in this buffer inline, with or without a
description; if some show already, hide them all."
  (interactive)
  (if (seq-some (lambda (o) (overlay-get o 'org-image-overlay))
                (overlays-in (point-min) (point-max)))
      (progn (org-link-preview '(64)) (message "Images hidden"))
    (org-link-preview 11)
    (let ((n (cl-count-if (lambda (o) (overlay-get o 'org-image-overlay))
                          (overlays-in (point-min) (point-max)))))
      (message "%d image%s shown" n (if (= n 1) "" "s")))))

(map! :after org :map org-mode-map :localleader "l v" #'+org/toggle-images)

(with-eval-after-load 'ol
  (when (fboundp 'org-link-preview)
    (advice-add 'org-link-preview :filter-args #'+org-links-preview-described-a)))

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
