;;; lisp/+screenshot.el --- Screenshots: paste the newest, browse them all -*- lexical-binding: t; -*-
;;
;; Hyprland's Print keys copy a shot to the clipboard *and* save it to
;; ~/Pictures/Screenshots (grimblast copysave).  M-y lists text only, so
;; images get their own keys:
;;
;;   SPC i S    link the newest screenshot right away, no prompt (C-u N:
;;              the Nth newest); also SPC m l p in Org and Markdown
;;   M-Y        insert a screenshot: the clipboard image (as a pasted
;;              attachment, Org's yank-media) or a saved one, newest first,
;;              previewed while you move; Org gets a link, Markdown an image
;;   SPC o S    browse them in dirvish, newest first, preview at point
;;   SPC o C-s  the same as thumbnails (image-dired)
;;
;;; Code:

(declare-function consult--read "ext:consult" (table &rest options))
(declare-function consult--file-preview "ext:consult" ())
(declare-function org-link-preview-region "ol" (&optional include-linked refresh beg end))
(defvar yank-media--registered-handlers)

(defvar +screenshot-dir (expand-file-name "~/Pictures/Screenshots/")
  "Where screenshots are saved (hyprland.conf: $shot).")

(defvar +screenshot-file-regexp "\\.\\(?:png\\|jpe?g\\|webp\\)\\'")

(defun +screenshot-files ()
  "Screenshots in `+screenshot-dir', newest first."
  (let ((files (directory-files +screenshot-dir t +screenshot-file-regexp)))
    (mapcar #'car
            (sort (mapcar (lambda (f) (cons f (file-attribute-modification-time
                                               (file-attributes f))))
                          files)
                  (lambda (a b) (time-less-p (cdr b) (cdr a)))))))

(defun +screenshot--clipboard-image-p ()
  "Non-nil when the clipboard holds an image this buffer can paste."
  (and (executable-find "wl-paste")
       (fboundp 'yank-media)
       (seq-some (lambda (type) (string-prefix-p "image/" type))
                 (ignore-errors (process-lines "wl-paste" "--list-types")))
       (seq-some (lambda (h) (string-match-p (car h) "image/png"))
                 (bound-and-true-p yank-media--registered-handlers))))

(defun +screenshot--age (file)
  (let ((secs (float-time (time-subtract nil (file-attribute-modification-time
                                               (file-attributes file))))))
    (cond ((< secs 3600) (format "%d min ago" (/ secs 60)))
          ((< secs 86400) (format "%d h ago" (/ secs 3600)))
          (t (format "%d days ago" (/ secs 86400))))))

(defun +screenshot-insert-file (file)
  "Insert FILE the way this buffer shows images."
  (let ((path (abbreviate-file-name file)))
    (cond ((derived-mode-p 'org-mode)
           (insert (format "[[file:%s]]" path))
           (when (fboundp 'org-link-preview-region)
             (org-link-preview-region nil t (line-beginning-position) (line-end-position))))
          ((derived-mode-p 'markdown-mode)
           (insert (format "![%s](%s)" (file-name-base file) path)))
          (t (insert path)))))

(defconst +screenshot--clipboard "⎘ Clipboard image (paste it)")

;;;###autoload
(defun +screenshot/insert ()
  "Insert the clipboard image or a saved screenshot, newest first."
  (interactive)
  (let* ((files (+screenshot-files))
         (cands (append (and (+screenshot--clipboard-image-p) (list +screenshot--clipboard))
                        (mapcar #'abbreviate-file-name files)))
         (annotate (lambda (c) (unless (equal c +screenshot--clipboard)
                                 (concat "  " (+screenshot--age (expand-file-name c))))))
         (pick (if (fboundp 'consult--read)
                   (consult--read cands :prompt "Screenshot: " :sort nil :require-match t
                                  :category 'file :annotate annotate
                                  :state (consult--file-preview))
                 (let ((completion-extra-properties (list :annotation-function annotate)))
                   (completing-read "Screenshot: " cands nil t)))))
    (if (equal pick +screenshot--clipboard)
        (yank-media)
      (+screenshot-insert-file (expand-file-name pick)))))

;;;###autoload
(defun +screenshot/insert-latest (&optional n)
  "Link the newest screenshot at point, or the Nth newest with a prefix arg."
  (interactive "p")
  (let ((file (nth (1- (max 1 (or n 1))) (+screenshot-files))))
    (unless file
      (user-error "No screenshot number %d in %s" (or n 1) +screenshot-dir))
    (+screenshot-insert-file file)
    (message "Linked %s (%s)" (file-name-nondirectory file) (+screenshot--age file))))

;;;###autoload
(defun +screenshot/browse ()
  "Screenshots in dired (dirvish), newest first."
  (interactive)
  (dired +screenshot-dir "-alt"))

;;;###autoload
(defun +screenshot/thumbnails ()
  "Screenshots as thumbnails."
  (interactive)
  (image-dired +screenshot-dir))

(map! "M-Y" #'+screenshot/insert
      :leader
      :desc "Latest screenshot"      "i S"   #'+screenshot/insert-latest
      :desc "Screenshots"            "o S"   #'+screenshot/browse
      :desc "Screenshot thumbnails"  "o C-s" #'+screenshot/thumbnails)

(map! :after org :map org-mode-map :localleader
      :desc "Latest screenshot" "l p" #'+screenshot/insert-latest)
(map! :after markdown-mode :map markdown-mode-map :localleader
      :desc "Latest screenshot" "l p" #'+screenshot/insert-latest)

(provide '+screenshot)
;;; +screenshot.el ends here
