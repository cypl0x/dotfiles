;;; lisp/+vellumory.el --- Review Vellumory: capture feedback where it happens -*- lexical-binding: t; -*-
;;
;; While testing Vellumory, a thought about the page in front of you becomes a
;; TODO in `+vellumory-feedback-file' with everything needed to act on it
;; later: a link back to the exact page and position, the selected text, and
;; the commit and worker you were testing.
;;
;;   SPC m F   in a Vellumory buffer   capture feedback (`+vellumory/feedback')
;;   SPC X V   anywhere                same, via org-capture
;;   SPC n V                           open the feedback file
;;   SPC m U   in a Vellumory buffer   is a newer release out? (`+vellumory/update')
;;
;; The config pins a release (flake.nix tag + packages.el :pin); build info and
;; the release check read the clone Doom built from.
;;
;;; Code:

(require 'cl-lib)

(defvar org-capture-templates)
(declare-function org-capture-get "org-capture" (prop &optional local))
(defvar vellumory-theme)

(defvar +vellumory-feedback-file
  (expand-file-name "vellumory-feedback.org" org-directory)
  "Org file collecting Vellumory review notes.")

(after! vellumory
  ;; Pages in the Emacs theme's foreground and background ("theme colours").
  (setq vellumory-theme 'tint))

(defvar +vellumory-checkout
  (expand-file-name "straight/repos/vellumory" (bound-and-true-p doom-local-dir))
  "The clone Doom builds Vellumory's Lisp from: the pinned release (packages.el).")

(defun +vellumory--git (&rest args)
  (when-let* ((default-directory (file-name-as-directory
                                  (expand-file-name +vellumory-checkout)))
              ((file-directory-p default-directory)))
    (with-temp-buffer
      (when (zerop (apply #'process-file "git" nil t nil args))
        (string-trim (buffer-string))))))

(defun +vellumory-build-info ()
  "One line naming the Vellumory under test: branch, commit, dirtiness, worker."
  (format "%s@%s%s, worker %s"
          (or (+vellumory--git "branch" "--show-current") "?")
          (or (+vellumory--git "rev-parse" "--short" "HEAD") "?")
          (if (equal (+vellumory--git "status" "--porcelain") "") "" " (dirty)")
          (or (ignore-errors
                (car (process-lines "vellumory" "--version")))
              "missing")))

(defun +vellumory-feedback-selection ()
  "The text selected in the buffer org-capture started from, as a quote block."
  (when-let* ((buf (org-capture-get :original-buffer))
              (text (with-current-buffer buf
                      (cond ((and (derived-mode-p 'vellumory-mode)
                                  (fboundp 'vellumory-selection-text))
                             (vellumory-selection-text))
                            ((use-region-p)
                             (buffer-substring-no-properties
                              (region-beginning) (region-end)))))))
    (format "#+begin_quote\n%s\n#+end_quote\n" text)))

(after! org-capture
  (add-to-list 'org-capture-templates
               `("V" "Vellumory feedback" entry
                 (file+headline +vellumory-feedback-file "Inbox")
                 ,(concat "* TODO %^{Feedback}  :vellumory:\n"
                          ":PROPERTIES:\n"
                          ":CREATED:  %U\n"
                          ":BUILD:    %(+vellumory-build-info)\n"
                          ":END:\n"
                          "%a\n"
                          "%(+vellumory-feedback-selection)"
                          "%?")
                 :empty-lines-after 1)
               t))

;;;###autoload
(defun +vellumory/feedback ()
  "Capture feedback about the Vellumory page at point."
  (interactive)
  (org-capture nil "V"))

;;;###autoload
(defun +vellumory/open-feedback ()
  "Open the Vellumory feedback file."
  (interactive)
  (find-file +vellumory-feedback-file))

;;; Newer releases ─────────────────────────────────────────────────────────

(defvar +vellumory-remote "https://github.com/cypl0x/vellumory"
  "Where Vellumory releases (tags vX.Y.Z) are published.")

(defun +vellumory--notify (title body &optional critical)
  (message "%s: %s" title body)
  (when (executable-find "notify-send")
    (apply #'call-process "notify-send" nil 0 nil
           `("-a" "Emacs · Vellumory" ,@(when critical '("-u" "critical")) ,title ,body))))

(defun +vellumory-latest-release (ls-remote-output)
  "The newest (TAG . COMMIT) in LS-REMOTE-OUTPUT of `git ls-remote --tags'.
Annotated tags resolve to their commit (the ^{} line)."
  (let (tags)
    (dolist (line (split-string ls-remote-output "\n" t))
      (when (string-match "\\`\\([0-9a-f]+\\)\trefs/tags/\\(v[0-9.]+\\)\\(\\^{}\\)?\\'" line)
        (let ((sha (match-string 1 line)) (tag (match-string 2 line)))
          ;; The dereferenced commit wins over the tag object.
          (if (match-string 3 line)
              (setf (alist-get tag tags nil nil #'equal) sha)
            (unless (assoc tag tags) (push (cons tag sha) tags))))))
    (car (sort tags (lambda (a b) (version< (substring (car b) 1)
                                            (substring (car a) 1)))))))

;;;###autoload
(defun +vellumory/update ()
  "Check GitHub for a Vellumory release newer than the one this config pins.
The dotfiles pin a release (flake.nix: github:cypl0x/vellumory/vX.Y.Z, and the
matching :pin in packages.el); this tells you what to change, it changes
nothing itself."
  (interactive)
  (let ((pinned (+vellumory--git "rev-parse" "HEAD"))
        (buf (generate-new-buffer " *vellumory-ls-remote*")))
    (message "Vellumory: checking %s…" +vellumory-remote)
    (make-process
     :name "vellumory-ls-remote" :buffer buf :noquery t
     :command (list "git" "ls-remote" "--tags" +vellumory-remote)
     :sentinel
     (lambda (proc _)
       (unless (process-live-p proc)
         (let ((latest (and (zerop (process-exit-status proc))
                            (+vellumory-latest-release
                             (with-current-buffer buf (buffer-string))))))
           (kill-buffer buf)
           (cond ((not latest)
                  (+vellumory--notify "Vellumory" "Could not read the releases" t))
                 ((equal (cdr latest) pinned)
                  (+vellumory--notify "Vellumory"
                                      (format "%s is the newest release, and the one in use"
                                              (car latest))))
                 (t
                  (+vellumory--notify
                   (format "Vellumory %s is out" (car latest))
                   (format "In use: %s. To upgrade: flake.nix tag → %s, packages.el :pin → %s, then nrs and doom sync."
                           (if pinned (substring pinned 0 7) "?")
                           (car latest) (cdr latest)))))))))))

(map! :leader
      :desc "Vellumory feedback" "n V" #'+vellumory/open-feedback)
(map! :after vellumory
      :map vellumory-mode-map
      :localleader
      :desc "Feedback" "F" #'+vellumory/feedback
      :desc "Newer release?" "U" #'+vellumory/update)

(provide '+vellumory)
;;; +vellumory.el ends here
