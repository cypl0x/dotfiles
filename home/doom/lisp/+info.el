;;; lisp/+info.el --- Info manuals: easy to read, highlighted, and they remember -*- lexical-binding: t; -*-
;;
;; Reading:
;;   - headings sized and colored like Org's, cross references as links,
;;     the text in a centered column of readable width
;;   - code highlighted: indented Lisp examples get emacs-lisp-mode's own
;;     colors, shell examples ($ …) theirs, ⇒ ⊣ error→ stand out, keys too
;;
;; Remembering, in every manual:
;;   - where you were: node and line.  Opening a manual at its Top again
;;     takes you back there (the echo area says so; `t' goes to Top)
;;   - how far you've read: the nodes you've visited, as a percentage, in
;;     the header line
;;   SPC h I   continue reading: manuals by when you last read them, with
;;             how far you got
;;
;; Your own manuals, in C-h i (the "This configuration" section): this
;; config's README, Org-roam here, well-formed (docs/*.org, built with
;; ox-texinfo when they change).
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar Info-current-file)
(defvar Info-current-node)
(defvar Info-additional-directory-list)
(defvar doom-data-dir)
(defvar doom-cache-dir)
(declare-function Info-goto-node "info" (nodename &optional fork strict-case))
(declare-function Info-build-node-completions "info" (&optional filename))
(declare-function +docs--info-of "+docs" (org name))

;;;; Reading

(defun +info-faces-h ()
  "Headings like Org's levels, quoted names as code, links as links."
  (dolist (spec '((info-title-1 org-level-1 1.5) (info-title-2 org-level-2 1.3)
                  (info-title-3 org-level-3 1.15) (info-title-4 org-level-4 1.05)))
    (when (facep (car spec))
      (set-face-attribute (car spec) nil :inherit (nth 1 spec) :height (nth 2 spec) :weight 'bold)))
  (when (facep 'Info-quoted) (set-face-attribute 'Info-quoted nil :inherit 'font-lock-constant-face))
  (when (facep 'info-xref) (set-face-attribute 'info-xref nil :inherit 'link)))
(add-hook 'doom-load-theme-hook #'+info-faces-h)
(with-eval-after-load 'info (+info-faces-h))

(defvar +info-text-width 80 "Columns of Info text; the rest is margin.")

(defun +info--center ()
  "Center the text column in each window showing this Info buffer."
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (let ((margin (max 0 (/ (- (window-total-width w) +info-text-width 4) 2))))
      (set-window-margins w margin margin))))

;;;; Code in examples

(defun +info--fontify-lisp (beg end)
  "Give BEG..END emacs-lisp-mode's colors."
  (let* ((text (buffer-substring-no-properties beg end))
         (faces (with-temp-buffer
                  (insert text)
                  (delay-mode-hooks (emacs-lisp-mode))
                  (font-lock-ensure)
                  (let (out (pos (point-min)))
                    (while (< pos (point-max))
                      (let ((next (next-single-property-change pos 'face nil (point-max)))
                            (face (get-text-property pos 'face)))
                        (when face (push (list (1- pos) (1- next) face) out))
                        (setq pos next)))
                    out))))
    (pcase-dolist (`(,b ,e ,face) faces)
      (put-text-property (+ beg b) (+ beg e) 'font-lock-face face))))

(defun +info-highlight-h ()
  "Highlight the code in this node."
  (let ((inhibit-read-only t))
    (with-silent-modifications
      (save-excursion
        (goto-char (point-min))
        ;; Indented examples: runs of lines indented 5+ spaces.
        (while (re-search-forward "^ \\{5,\\}\\S-" nil t)
          (let ((beg (line-beginning-position)))
            (goto-char beg)
            ;; A chunk: indented lines up to a blank line (each chunk is
            ;; classified by itself: prose and code alternate in examples).
            (while (and (not (eobp)) (looking-at-p "^ \\{5,\\}\\S-")) (forward-line 1))
            (let* ((end (point))
                   (block (buffer-substring-no-properties beg end)))
              (cond ((string-match-p "\\`[ \t]*[(;']" block) (+info--fontify-lisp beg end))
                    ((string-match-p "\\`[ \t]*\\$ " block)
                     (save-excursion
                       (goto-char beg)
                       (while (re-search-forward "^[ \t]*\\(\\$\\) \\([^ \n]+\\)" end t)
                         (put-text-property (match-beginning 1) (match-end 1) 'font-lock-face 'shadow)
                         (put-text-property (match-beginning 2) (match-end 2) 'font-lock-face 'font-lock-function-name-face))))))))
        ;; Results and errors in examples; keys in the prose.
        (goto-char (point-min))
        (while (re-search-forward "⇒\\|⊣\\|error→\\|→\\|≡" nil t)
          (put-text-property (match-beginning 0) (match-end 0) 'font-lock-face 'font-lock-keyword-face))
        (goto-char (point-min))
        (while (re-search-forward "\\_<\\(?:[CMSs]-\\)+[^][ \n’'.,;:()]+" nil t)
          (put-text-property (match-beginning 0) (match-end 0) 'font-lock-face 'help-key-binding))))))

;;;; Remembering

(defvar +info-progress-file
  (expand-file-name "info-progress.eld" (or (bound-and-true-p doom-data-dir) user-emacs-directory))
  "Where each manual's last position and read nodes are kept.")

(defvar +info--progress nil "Hash: manual → plist (:node :line :time :seen (NODES) :total N).")

(defun +info--progress ()
  (or +info--progress
      (setq +info--progress
            (let ((h (make-hash-table :test #'equal)))
              (when (file-readable-p +info-progress-file)
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents +info-progress-file)
                    (pcase-dolist (`(,k . ,v) (read (current-buffer))) (puthash k v h)))))
              h))))

(defun +info--save-progress ()
  (when +info--progress
    (make-directory (file-name-directory +info-progress-file) t)
    (let (alist print-length print-level)
      (maphash (lambda (k v) (push (cons k v) alist)) +info--progress)
      (with-temp-file +info-progress-file (prin1 alist (current-buffer))))))

(defun +info--manual ()
  (and (stringp Info-current-file) (file-name-sans-extension (file-name-nondirectory Info-current-file))))

(defvar-local +info--resumed nil "Manuals this buffer has resumed already.")

(defun +info--record ()
  "Remember where you are in this manual."
  (when-let* ((manual (+info--manual))
              ((not (member Info-current-node '("Top" "*")))))
    (let* ((p (gethash manual (+info--progress)))
           (seen (cl-adjoin Info-current-node (plist-get p :seen) :test #'equal)))
      (puthash manual
               (list :node Info-current-node :line (line-number-at-pos)
                     :time (float-time) :seen seen
                     :total (or (plist-get p :total)
                                (ignore-errors (length (Info-build-node-completions)))))
               (+info--progress)))))

(defun +info--header ()
  (when-let* ((manual (+info--manual))
              (p (gethash manual (+info--progress)))
              (total (plist-get p :total)))
    (let ((seen (length (plist-get p :seen))))
      (setq header-line-format
            ;; A header line reads % as a code: %% for the sign.
            (format "  %s · %s · %d%%%% read (%d of %d nodes)"
                    manual Info-current-node (round (* 100.0 (/ seen (float (max 1 total))))) seen total)))))

(defun +info-node-h ()
  "On every node: highlight, center, remember; at Top, go back to where you were."
  (let* ((manual (+info--manual))
         (p (and manual (gethash manual (+info--progress)))))
    (if (and p (equal Info-current-node "Top")
             (not (member manual +info--resumed))
             (plist-get p :node))
        (progn
          (push manual +info--resumed)
          (Info-goto-node (plist-get p :node))
          ;; Info puts point at the node's start after this hook: the line
          ;; afterwards.
          (let ((buf (current-buffer)) (line (or (plist-get p :line) 1)))
            (run-at-time 0 nil (lambda ()
                                 (when (buffer-live-p buf)
                                   (with-current-buffer buf
                                     (goto-char (point-min)) (forward-line (1- line))
                                     (when-let* ((w (get-buffer-window buf))) (set-window-point w (point))))))))
          (message "Back where you were in %s: %s (t: the Top)" manual (plist-get p :node)))
      (when manual (push manual +info--resumed))
      (+info-highlight-h)
      (+info--center)
      (+info--record)
      (+info--header))))

(defun +info-moved-h ()
  "After a command in Info: remember the line (cheap: no saving)."
  (when (and (derived-mode-p 'Info-mode) (+info--manual))
    (when-let* ((p (gethash (+info--manual) (+info--progress))))
      (puthash (+info--manual) (plist-put (plist-put p :line (line-number-at-pos)) :time (float-time))
               (+info--progress)))))

(defun +info-mode-h ()
  (add-hook 'post-command-hook #'+info-moved-h nil t)
  (add-hook 'window-size-change-functions (lambda (_) (+info--center)) nil t)
  (add-hook 'kill-buffer-hook #'+info--save-progress nil t))

(add-hook 'Info-selection-hook #'+info-node-h)
(add-hook 'Info-mode-hook #'+info-mode-h)
(add-hook 'kill-emacs-hook #'+info--save-progress)
(defvar +info--save-timer (run-with-idle-timer 60 t #'+info--save-progress))

(defun +info--ago (time)
  (let ((s (- (float-time) time)))
    (cond ((< s 3600) (format "%d min ago" (/ s 60))) ((< s 86400) (format "%d h ago" (/ s 3600)))
          (t (format "%d days ago" (/ s 86400))))))

;;;###autoload
(defun +info/continue ()
  "Continue reading a manual, where you left it; most recent first."
  (interactive)
  (let (rows)
    (maphash (lambda (k p) (push (cons k p) rows)) (+info--progress))
    (unless rows (user-error "No manual read yet (C-h i)"))
    (setq rows (sort rows (lambda (a b) (> (plist-get (cdr a) :time) (plist-get (cdr b) :time)))))
    (let* ((choices (mapcar (lambda (r)
                              (let* ((p (cdr r)) (total (or (plist-get p :total) 0))
                                     (seen (length (plist-get p :seen))))
                                (cons (format "%-22s %3d%%  %-40s %s" (car r)
                                              (round (* 100.0 (/ seen (float (max 1 total)))))
                                              (truncate-string-to-width (or (plist-get p :node) "") 40 nil nil "…")
                                              (+info--ago (plist-get p :time)))
                                      (car r))))
                            rows))
           (manual (cdr (assoc (completing-read "Continue reading: " choices nil t) choices))))
      (info manual))))

;;;; This configuration's manuals in C-h i

(defvar +info-own-manuals
  '(("doom-config" "lisp/README.org" "This Doom Emacs configuration: what it adds and how to learn it")
    ("org-roam-here" "docs/org-roam-here.org" "Org-roam as configured here")
    ("well-formed" "docs/well-formed.org" "well-formed, the writing assistant"))
  "(NAME ORG-FILE (from home/doom) DESCRIPTION) of the manuals built for C-h i.")

(defvar +info--root
  (file-truename (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
  "home/doom, where docs/ and lisp/README.org are (set when this file loads).")

(defun +info-own-manuals-dir ()
  "Build (when their Org changed) this configuration's manuals and a `dir'
listing them; return the directory."
  (let* ((root +info--root)
         (dir (expand-file-name "docs/" doom-cache-dir)))
    (make-directory dir t)
    (with-temp-file (expand-file-name "dir" dir)
      (insert "This is the file .../info/dir, which contains the\ntopmost node of the Info hierarchy.\n\n"
              "\x1f\nFile: dir,\tNode: Top\tThis is the top of the INFO tree\n\n* Menu:\n\n"
              "This configuration\n")
      (pcase-dolist (`(,name ,org ,desc) +info-own-manuals)
        (let ((org (expand-file-name org root)))
          (when (and (file-exists-p org) (ignore-errors (+docs--info-of org name)))
            (insert (format "* %s: (%s).%s%s.\n" name name (make-string (max 1 (- 22 (length name))) ?\s) desc))))))
    dir))

(defun +info-add-own-manuals ()
  (when-let* ((dir (ignore-errors (+info-own-manuals-dir))))
    (add-to-list 'Info-additional-directory-list dir)))

;; Built when you open Info's directory or a manual (C-h i, M-x info), once
;; per session, and only for a manual whose Org changed: makeinfo and the
;; Org export take seconds, which loading this file mustn't.
(defvar +info--own-added nil)
(defun +info-own-manuals-a (&rest _)
  (unless +info--own-added
    (setq +info--own-added t)
    (+info-add-own-manuals)))
(advice-add 'info :before #'+info-own-manuals-a)
(advice-add 'Info-directory :before #'+info-own-manuals-a)

(map! :leader :desc "Continue reading a manual" "h I" #'+info/continue)
(map! :after info :map Info-mode-map :n "t" #'Info-top-node)

(provide '+info)
;;; +info.el ends here
