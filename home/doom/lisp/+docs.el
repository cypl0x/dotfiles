;;; lisp/+docs.el --- Find your own additions, and learn them -*- lexical-binding: t; -*-
;;
;; Hand-kept menus go stale; these are generated from the code itself.
;;
;;   SPC h /    every command defined in this config's lisp/, with its keys
;;              and first doc line; RET runs it (M-x for your own additions)
;;   +docs/learn  lisp/README.org at its learning path   (SPC H L)
;;   +docs/info   the same README as an Info manual        (SPC H i)
;;   SPC n r ?    Org Roam as configured here (docs/org-roam-here.org, Info)
;;   SPC n r M    Org-roam's own manual
;;
;;; Code:

(defvar doom-cache-dir)
(declare-function org-fold-show-subtree "org-fold" ())
(declare-function consult--read "ext:consult" (table &rest options))
(declare-function org-export-to-file "ox" (backend file &optional async subtreep visible-only body-only ext-plist post-process))

(defvar +docs-dir (file-name-directory (or load-file-name buffer-file-name))
  "This config's lisp/ directory.")

(defvar +docs-readme (expand-file-name "README.org" +docs-dir))

(defun +docs-commands ()
  "Interactive commands defined in this config, sorted by name.
One pass over `load-history' (per-symbol `symbol-file' calls rescan it
and took a minute)."
  (let ((dir (file-truename +docs-dir)) out)
    (dolist (entry load-history)
      (when (and (stringp (car entry))
                 (string-prefix-p dir (file-truename (car entry))))
        (dolist (def (cdr entry))
          (when (and (eq (car-safe def) 'defun) (commandp (cdr def)))
            (push (cdr def) out)))))
    (sort (delete-dups out) #'string<)))

(defun +docs--annotate (name)
  (let* ((sym (intern-soft name))
         (keys (where-is-internal sym nil t))
         (doc (car (split-string (or (ignore-errors (documentation sym t)) "") "\n"))))
    (concat (propertize " " 'display '(space :align-to 44))
            (propertize (if keys (key-description keys) "") 'face 'help-key-binding)
            (propertize " " 'display '(space :align-to 64))
            (propertize doc 'face 'completions-annotations))))

;;;###autoload
(defun +docs/commands ()
  "Pick one of this config's own commands (keys and doc shown) and run it."
  (interactive)
  (let* ((names (mapcar #'symbol-name (+docs-commands)))
         (pick (if (fboundp 'consult--read)
                   (consult--read names :prompt "My commands: " :require-match t
                                  :category 'command :annotate #'+docs--annotate)
                 (let ((completion-extra-properties (list :annotation-function #'+docs--annotate)))
                   (completing-read "My commands: " names nil t)))))
    (call-interactively (intern pick))))

;;;###autoload
(defun +docs/learn ()
  "Open lisp/README.org at its learning path."
  (interactive)
  (find-file +docs-readme)
  (goto-char (point-min))
  (when (re-search-forward "^\\* Learning path" nil t)
    (beginning-of-line)
    (org-fold-show-subtree)
    (recenter 0)))

;;;###autoload
(defun +docs--info-of (org name)
  "Info manual NAME.info built from Org file ORG (in the cache, rebuilt when
ORG is newer); its path."
  (let* ((dir (expand-file-name "docs/" doom-cache-dir))
         (info (expand-file-name (concat name ".info") dir)))
    (when (or (not (file-exists-p info))
              (file-newer-than-file-p org info))
      (make-directory dir t)
      (require 'ox-texinfo)
      ;; Built in the cache, not next to the source (that's the repo).
      (let ((texi (expand-file-name (concat name ".texi") dir)))
        (with-current-buffer (find-file-noselect org)
          (org-export-to-file 'texinfo texi nil nil nil nil
                              '(:with-broken-links mark)))
        (unless (zerop (call-process "makeinfo" nil "*makeinfo*" nil
                                     "--no-split" "--force" "-o" info texi))
          (pop-to-buffer "*makeinfo*")
          (user-error "makeinfo failed; see *makeinfo*"))))
    info))

(defun +docs/info ()
  "The README as an Info manual, rebuilt when the README is newer."
  (interactive)
  (info (+docs--info-of +docs-readme "doom-config")))

(defvar +docs-org-roam
  (expand-file-name "../docs/org-roam-here.org" (file-truename +docs-dir))
  "The companion to Org-roam's manual, for this configuration.")

(defun +docs/org-roam ()
  "Org Roam as configured here (Info; Org-roam's own manual: SPC n r M)."
  (interactive)
  (info (+docs--info-of +docs-org-roam "org-roam-here")))

(defun +docs/org-roam-manual ()
  "Org-roam's own manual."
  (interactive)
  (info "org-roam"))

;; By name too, as `magit-info' opens Magit's (Org-roam has no such command).
(defalias 'org-roam-info #'+docs/org-roam-manual)
(defalias 'org-roam-manual #'+docs/org-roam-manual)

(map! :leader
      (:prefix "n"
       (:prefix "r"
        :desc "Org Roam here (manual)" "?" #'+docs/org-roam
        :desc "Org-roam's manual"      "M" #'+docs/org-roam-manual)))

(map! :leader :desc "My commands" "h /" #'+docs/commands)

(provide '+docs)
;;; +docs.el ends here
