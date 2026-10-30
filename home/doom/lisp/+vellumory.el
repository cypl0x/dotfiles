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

(defvar org-capture-templates)
(declare-function org-capture-get "org-capture" (prop &optional local))

(defvar +vellumory-feedback-file
  (expand-file-name "vellumory-feedback.org" org-directory)
  "Org file collecting Vellumory review notes.")

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

(map! :leader :desc "Vellumory feedback" "n V" #'+vellumory/open-feedback)
(map! :after vellumory
      :map vellumory-mode-map
      :localleader
      :desc "Feedback" "F" #'+vellumory/feedback)

(provide '+vellumory)
;;; +vellumory.el ends here
