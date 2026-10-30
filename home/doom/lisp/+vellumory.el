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
;;
;;; Code:

(require 'cl-lib)

(defvar org-capture-templates)
(declare-function org-capture-get "org-capture" (prop &optional local))

(defvar +vellumory-feedback-file
  (expand-file-name "vellumory-feedback.org" org-directory)
  "Org file collecting Vellumory review notes.")

(after! vellumory
  ;; Pages in the Emacs theme's foreground and background ("theme colours").
  (setq vellumory-theme 'tint))

(defvar +vellumory-checkout "~/dev/vellumory"
  "The clone Doom builds Vellumory's Lisp from (see packages.el).")

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

;;; Update to the latest commit ───────────────────────────────────────────

(defvar +vellumory-dotfiles "~/dotfiles"
  "Flake whose `vellumory' input pins the worker.")

(defvar +vellumory-lisp-only-paths '("lisp/" "tests/" "docs/requirements" "README" ".github/")
  "Changes under these prefixes need no new worker.
Everything else (worker sources, the manual, packaging) does.")

(defun +vellumory--changes (old new)
  "Classify files changed between OLD and NEW: (LISP-P . WORKER-P)."
  (let ((files (split-string (or (+vellumory--git "diff" "--name-only" old new) "")
                             "\n" t)))
    (cons (seq-some (lambda (f) (string-prefix-p "lisp/" f)) files)
          (seq-some (lambda (f)
                      (not (seq-some (lambda (p) (string-prefix-p p f))
                                     +vellumory-lisp-only-paths)))
                    files))))

(defun +vellumory--reload-lisp ()
  "Re-load every Vellumory feature already loaded, from its rebuilt file."
  (let ((n 0))
    (dolist (f features)
      (when (string-prefix-p "vellumory" (symbol-name f))
        (when-let* ((file (locate-library (symbol-name f))))
          (load file nil t)
          (cl-incf n))))
    n))

(defun +vellumory--run (name command then)
  "Run shell COMMAND in buffer *NAME*; call THEN with success (t/nil)."
  (let ((buf (get-buffer-create (format "*%s*" name))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "\n$ %s\n" command))))
    (make-process
     :name name :buffer buf :noquery t
     :command (list shell-file-name shell-command-switch command)
     :sentinel (lambda (proc _)
                 (unless (process-live-p proc)
                   (funcall then (zerop (process-exit-status proc))))))))

(defun +vellumory--notify (title body &optional critical)
  (message "%s: %s" title body)
  (when (executable-find "notify-send")
    (apply #'call-process "notify-send" nil 0 nil
           `("-a" "Emacs · Vellumory" ,@(when critical '("-u" "critical")) ,title ,body))))

;;;###autoload
(defun +vellumory/update ()
  "Pull the Vellumory checkout and bring this session up to its latest commit.
Changed Lisp is rebuilt (`doom sync') and re-loaded in place. If anything
beyond Lisp changed, the flake input is bumped and the system rebuilt, so the
worker and manual match; reopen documents to use the new worker. Progress
and output are in *vellumory-update*."
  (interactive)
  (let* ((old (+vellumory--git "rev-parse" "HEAD"))
         (default-directory (expand-file-name +vellumory-checkout))
         (dotfiles (expand-file-name +vellumory-dotfiles)))
    (unless old (user-error "No git checkout at %s" +vellumory-checkout))
    (+vellumory--run
     "vellumory-update" "git pull --ff-only"
     (lambda (ok)
       (let* ((new (+vellumory--git "rev-parse" "HEAD"))
              (log (+vellumory--git "log" "--format=%h %s" (concat old ".." new)))
              (changes (+vellumory--changes old new)))
         (cond
          ((not ok)
           (pop-to-buffer "*vellumory-update*")
           (+vellumory--notify "Update failed" "git pull did not fast-forward" t))
          ((equal old new)
           (+vellumory--notify "Vellumory" (format "Already at %s" (substring new 0 7))))
          (t
           (let* ((finish
                   (lambda (worker-ok)
                     (+vellumory--notify
                      (if worker-ok "Vellumory updated" "Vellumory worker update failed")
                      (format "%s → %s%s\n%s"
                              (substring old 0 7) (substring new 0 7)
                              (if (cdr changes) " (new worker: reopen documents)" "")
                              log)
                      (not worker-ok))))
                  (worker
                   (lambda ()
                     (if (not (cdr changes))
                         (funcall finish t)
                       (+vellumory--run
                        "vellumory-update"
                        (format "cd %s && nix flake update vellumory && sudo nixos-rebuild switch --flake .#%s"
                                (shell-quote-argument dotfiles) (system-name))
                        finish)))))
             (if (not (car changes))
                 (funcall worker)
               (+vellumory--run
                "vellumory-update"
                (format "%s sync -B" (shell-quote-argument
                                      (expand-file-name "bin/doom" doom-emacs-dir)))
                (lambda (sync-ok)
                  (if (not sync-ok)
                      (progn (pop-to-buffer "*vellumory-update*")
                             (+vellumory--notify "Update failed" "doom sync failed" t))
                    (message "Vellumory: re-loaded %d features" (+vellumory--reload-lisp))
                    (funcall worker)))))))))))))

(map! :leader
      :desc "Vellumory feedback" "n V" #'+vellumory/open-feedback)
(map! :after vellumory
      :map vellumory-mode-map
      :localleader
      :desc "Feedback" "F" #'+vellumory/feedback
      :desc "Update to latest" "U" #'+vellumory/update)

(provide '+vellumory)
;;; +vellumory.el ends here
