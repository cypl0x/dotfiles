;;; lisp/+format.el --- SPC c f formats, Org included -*- lexical-binding: t; -*-
;;
;; With Doom's :editor format off, SPC c f pointed at an undefined command.
;; Now it formats the region or buffer by what the buffer is:
;;
;;   Org         `+format-org': align tables and tags, repair lists (indent,
;;               numbering), update statistics cookies, drop trailing blanks.
;;               C-u: the canonical form Org's own parser prints back
;;               (`org-element-interpret-data'), shown as a diff first.
;;   eglot       the language server's formatter
;;   otherwise   re-indent
;;
;;; Code:

(declare-function org-table-map-tables "org-table" (f &optional quietly))
(declare-function org-table-align "org-table" ())
(declare-function org-list-repair "org-list" ())
(declare-function org-at-item-p "org" ())
(declare-function org-update-statistics-cookies "org" (all))
(declare-function org-align-tags "org" (&optional all))
(declare-function org-element-parse-buffer "org-element" (&optional granularity visible-only keep-deferred))
(declare-function org-element-interpret-data "org-element" (data))
(declare-function org-element-at-point "org-element" (&optional epom cached-only))
(declare-function org-element-lineage "org-element-ast" (datum &optional types with-self))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))
(defvar org-src-preserve-indentation)
(declare-function eglot-managed-p "eglot" ())
(declare-function eglot-format "eglot" (&optional beg end on-type-format))
(declare-function eglot-server-capable "eglot" (&rest feats))

(defun +format-org (&optional beg end)
  "Tidy Org between BEG and END (default: the whole buffer), in place."
  (let ((beg (copy-marker (or beg (point-min))))
        (end (copy-marker (or end (point-max)) t)))
    (save-excursion
      (save-restriction
        (narrow-to-region beg end)
        (org-table-map-tables #'org-table-align t)
        ;; Each top-level list once: `org-list-repair' fixes the whole list.
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]" nil t)
          (when (org-at-item-p)
            (org-list-repair)
            (goto-char (org-element-property :end (org-element-lineage
                                                   (org-element-at-point)
                                                   '(plain-list) t)))))
        (org-update-statistics-cookies 'all)
        (org-align-tags t)
        (delete-trailing-whitespace)))
    (set-marker beg nil)
    (set-marker end nil)))

(defun +format-org-canonical ()
  "Org's parser printed back: the canonical form of this buffer's text."
  ;; Src block bodies keep their indentation; only the syntax around them changes.
  (let ((org-src-preserve-indentation t))
    (substring-no-properties
     (org-element-interpret-data (org-element-parse-buffer)))))

(defun +format-org-canonical-buffer ()
  "Replace the buffer by its canonical form, after showing the diff."
  (let ((new (+format-org-canonical))
        (scratch (generate-new-buffer " *org canonical*")))
    (unwind-protect
        (if (string= new (buffer-string))
            (message "Already canonical")
          (with-current-buffer scratch (insert new))
          (let ((diff (diff-buffers (current-buffer) scratch nil t)))
            (unwind-protect
                (progn
                  (display-buffer diff)
                  (when (y-or-n-p "Replace with the canonical form (undoable)? ")
                    ;; Minimal edits: markers, point and undo stay sensible.
                    (if (>= emacs-major-version 31)
                        (replace-region-contents (point-min) (point-max) scratch)
                      (with-no-warnings (replace-buffer-contents scratch)))))
              (when (buffer-live-p diff) (kill-buffer diff)))))
      (kill-buffer scratch))))

;;;###autoload
(defun +format/dwim (&optional canonical)
  "Format the region, else the buffer, by what the buffer is.
In Org with prefix arg CANONICAL, rewrite it in Org's canonical form."
  (interactive "P")
  (let ((beg (and (use-region-p) (region-beginning)))
        (end (and (use-region-p) (region-end))))
    (cond ((derived-mode-p 'org-mode)
           (if canonical (+format-org-canonical-buffer) (+format-org beg end))
           (message "Org tidied%s" (if beg " (region)" "")))
          ((and (fboundp 'eglot-managed-p) (eglot-managed-p)
                (eglot-server-capable (if beg :documentRangeFormattingProvider
                                        :documentFormattingProvider)))
           (eglot-format beg end))
          (t (indent-region (or beg (point-min)) (or end (point-max)))))))

(map! :leader :desc "Format buffer/region" "c f" #'+format/dwim)

(provide '+format)
;;; +format.el ends here
