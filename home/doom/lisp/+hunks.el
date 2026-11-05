;;; lisp/+hunks.el --- The changes in the fringe, and everything to do with them -*- lexical-binding: t; -*-
;;
;; The colored marks in the fringe (diff-hl, Doom's vc-gutter) are hunks:
;; what changed since the last commit.  Doom moves between them (]d [d) and
;; stages (SPC g s) or reverts (SPC g r) one.  Here:
;;
;; Mouse     click a mark in the fringe: the hunk's diff in a popup, with
;;           buttons (revert, stage, previous, next, ediff, copy original);
;;           right-click a changed line: the actions in a menu.
;; SPC g H   the hunk menu: show its diff, stage, stage parts of it,
;;           unstage it (only this hunk, not the file), revert, commit just
;;           this hunk, ediff, select it, copy the original text, the
;;           history of these lines (git log -L), blame, compare against
;;           any revision (branch, tag, commit) instead of HEAD, marks in
;;           dired, amend view (changes since HEAD^).
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)

(declare-function diff-hl-hunk-overlay-at "ext:diff-hl" (pos))
(declare-function diff-hl-find-current-hunk "ext:diff-hl" ())
(declare-function diff-hl-update "ext:diff-hl" ())
(declare-function diff-hl-stage-current-hunk "ext:diff-hl" ())
(declare-function diff-hl-stage-some "ext:diff-hl" (&optional beg end))
(declare-function diff-hl-revert-hunk "ext:diff-hl" ())
(declare-function diff-hl-mark-hunk "ext:diff-hl" ())
(declare-function diff-hl-next-hunk "ext:diff-hl" (&optional backward))
(declare-function diff-hl-previous-hunk "ext:diff-hl" ())
(declare-function diff-hl-ediff-current-hunk "ext:diff-hl" ())
(declare-function diff-hl-set-reference-rev "ext:diff-hl" (rev))
(declare-function diff-hl-reset-reference-rev "ext:diff-hl" ())
(declare-function diff-hl-show-hunk "ext:diff-hl-show-hunk" ())
(declare-function diff-hl-show-hunk-posframe "ext:diff-hl-show-hunk-posframe" (buffer &optional line))
(declare-function diff-hl-show-hunk-copy-original-text "ext:diff-hl-show-hunk" ())
(declare-function diff-hl-show-hunk-mouse-mode "ext:diff-hl-show-hunk" (&optional arg))
(declare-function diff-hl-dired-mode "ext:diff-hl-dired" (&optional arg))
(declare-function diff-hl-amend-mode "ext:diff-hl-amend" (&optional arg))
(declare-function magit-commit-create "ext:magit-commit" (&optional args))
(declare-function magit-log-buffer-file "ext:magit-log" (&optional follow beg end))
(declare-function magit-blame-addition "ext:magit-blame" (args))
(declare-function magit-git-string "ext:magit-git" (&rest args))
(defvar diff-hl-show-hunk-function)
(defvar diff-hl-reference-revision)
(defvar diff-hl-mode)
(defvar diff-hl-amend-mode)

;;;; Where am I

(defun +hunks--root ()
  (or (and buffer-file-name (locate-dominating-file buffer-file-name ".git"))
      (user-error "Not in a git repository")))

(defun +hunks--on-change-p (&optional pos)
  "Non-nil when POS (point) is on a changed line."
  (and (bound-and-true-p diff-hl-mode) (diff-hl-hunk-overlay-at (or pos (point)))))

;;;; Unstage only this hunk

(defun +hunks--staged-hunks (file root)
  "FILE's staged hunks: (HEADER . ((START COUNT . TEXT) …)), new-side lines."
  (let* ((default-directory root)
         (diff (with-output-to-string
                 (with-current-buffer standard-output
                   (call-process "git" nil t nil "diff" "--cached" "-U0" "--no-color" "--"
                                 (file-relative-name file root)))))
         (pos (string-search "\n@@" diff)))
    (when pos
      (let ((header (substring diff 0 (1+ pos)))
            (hunks (let ((body (substring diff (1+ pos))) (starts nil) (i 0))
                     ;; Each hunk starts with a line "@@ …".
                     (while (setq i (string-match "^@@ " body i))
                       (push i starts) (setq i (1+ i)))
                     (setq starts (nreverse starts))
                     (cl-loop for (s e) on starts collect (substring body s e)))))
        (cons header
              (mapcar (lambda (h)
                        (string-match "\\`@@ -[0-9]+\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@" h)
                        (cl-list* (string-to-number (match-string 1 h))
                                  (if (match-string 2 h) (string-to-number (match-string 2 h)) 1)
                                  h))
                      hunks))))))

(defun +hunks/unstage ()
  "Unstage the staged hunk at point (only it; the rest stays staged)."
  (interactive)
  (let* ((root (+hunks--root))
         (staged (or (+hunks--staged-hunks buffer-file-name root) (user-error "Nothing of this file is staged")))
         (line (line-number-at-pos))
         (hunk (or (cl-find-if (lambda (h) (let ((start (car h)) (n (cadr h)))
                                            (if (zerop n) (memq line (list start (1+ start)))
                                              (and (>= line start) (< line (+ start n))))))
                               (cdr staged))
                   (user-error "No staged change on this line (staged here: lines %s)"
                               (mapconcat (lambda (h) (number-to-string (car h))) (cdr staged) ", "))))
         (patch (make-temp-file "unstage" nil ".patch" (concat (car staged) (cddr hunk)))))
    (unwind-protect
        (let ((default-directory root))
          (with-temp-buffer
            (unless (zerop (call-process "git" nil t nil "apply" "--cached" "--reverse" "--unidiff-zero" patch))
              (user-error "git apply failed: %s" (string-trim (buffer-string))))))
      (delete-file patch))
    (when (fboundp 'diff-hl-update) (diff-hl-update))
    (message "Unstaged the change at line %d" (car hunk))))

;;;; Commit just this hunk, history of these lines

(defun +hunks/commit ()
  "Commit only the hunk at point (stage it, then write the message)."
  (interactive)
  (unless (+hunks--on-change-p) (user-error "No change on this line"))
  (let* ((default-directory (+hunks--root))
         (others (string-trim (shell-command-to-string "git diff --cached --name-only"))))
    (when (and (not (string-empty-p others))
               (not (y-or-n-p (format "Already staged too: %s. Commit those with it? "
                                      (string-join (split-string others "\n") ", ")))))
      (user-error "Unstage them first (SPC g H u on each, or in magit)"))
    (save-buffer)
    (diff-hl-stage-current-hunk)
    (magit-commit-create)))

(defun +hunks/log ()
  "The history of the hunk's lines (git log -L)."
  (interactive)
  (if (+hunks--on-change-p)
      (pcase-let ((`(,beg . ,end) (diff-hl-find-current-hunk)))
        (magit-log-buffer-file nil (line-number-at-pos beg) (line-number-at-pos (max beg (1- end)))))
    (if (use-region-p)
        (magit-log-buffer-file nil (line-number-at-pos (region-beginning)) (line-number-at-pos (region-end)))
      (magit-log-buffer-file))))

(defun +hunks/compare (rev)
  "Mark changes against REV (a branch, tag or commit) instead of HEAD."
  (interactive (list (completing-read "Compare against (empty: HEAD): "
                                      (split-string (let ((default-directory (+hunks--root)))
                                                      (shell-command-to-string "git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags"))
                                                    "\n" t))))
  (if (string-empty-p rev) (diff-hl-reset-reference-rev) (diff-hl-set-reference-rev rev))
  (message "Fringe shows changes against %s" (if (string-empty-p rev) "HEAD" rev)))

(defun +hunks/dired-marks ()
  "Toggle change marks in dired (files modified, added, …)."
  (interactive)
  (require 'diff-hl-dired)
  (diff-hl-dired-mode 'toggle))

(defun +hunks/amend ()
  "Toggle the amend view: changes since HEAD^ (what an amend would contain)."
  (interactive)
  (require 'diff-hl-amend)
  (diff-hl-amend-mode 'toggle)
  (message "Amend view %s" (if diff-hl-amend-mode "on: changes since HEAD^" "off")))

;;;; The menu

(defun +hunks--describe ()
  (format "Change at line %d%s" (line-number-at-pos)
          (if (bound-and-true-p diff-hl-reference-revision)
              (format " (against %s)" diff-hl-reference-revision) "")))

(transient-define-prefix +hunks-menu ()
  "This change (hunk), and the changes of this file."
  [:description +hunks--describe
   ["This change"
    ("d" "Show its diff" diff-hl-show-hunk)
    ("s" "Stage it" diff-hl-stage-current-hunk)
    ("S" "Stage part of it (region)" diff-hl-stage-some)
    ("u" "Unstage it" +hunks/unstage)
    ("r" "Revert it" diff-hl-revert-hunk)
    ("c" "Commit just it" +hunks/commit)]
   [""
    ("e" "Ediff it" diff-hl-ediff-current-hunk)
    ("v" "Select it" diff-hl-mark-hunk)
    ("w" "Copy the original text" diff-hl-show-hunk-copy-original-text)
    ("l" "History of these lines" +hunks/log)
    ("b" "Blame" magit-blame-addition)]
   ["Move"
    ("n" "Next change" diff-hl-next-hunk :transient t)
    ("p" "Previous change" diff-hl-previous-hunk :transient t)]
   ["View"
    ("R" "Compare against a revision…" +hunks/compare)
    ("a" "Amend view (since HEAD^)" +hunks/amend)
    ("D" "Change marks in dired" +hunks/dired-marks)]])

;;;; Mouse: right-click a changed line

(defun +hunks-context-menu (menu click)
  "The change actions, when right-clicking a changed line."
  (let ((pos (posn-point (event-start click))))
    (when (and pos (+hunks--on-change-p pos))
      (save-excursion
        (goto-char pos)
        (define-key-after menu [hunk-show] '(menu-item "Show this change" diff-hl-show-hunk))
        (define-key-after menu [hunk-stage] '(menu-item "Stage this change" diff-hl-stage-current-hunk))
        (define-key-after menu [hunk-unstage] '(menu-item "Unstage this change" +hunks/unstage))
        (define-key-after menu [hunk-revert] '(menu-item "Revert this change" diff-hl-revert-hunk))
        (define-key-after menu [hunk-commit] '(menu-item "Commit just this change" +hunks/commit))
        (define-key-after menu [hunk-log] '(menu-item "History of these lines" +hunks/log))
        (define-key-after menu [hunk-more] '(menu-item "More… (SPC g H)" +hunks-menu))
        (define-key-after menu [hunk-sep] '(menu-item "--")))))
  menu)

(add-hook 'context-menu-functions #'+hunks-context-menu)

;;;; The popup: a child frame like the completion popup; the fringe clicks

(with-eval-after-load 'diff-hl-show-hunk
  (when (and (display-graphic-p) (require 'posframe nil t))
    (setq diff-hl-show-hunk-function #'diff-hl-show-hunk-posframe)))

(defun +hunks-mouse-h ()
  "Clicks on fringe marks show the change (buffer-local mode)."
  (require 'diff-hl-show-hunk)
  (diff-hl-show-hunk-mouse-mode (if diff-hl-mode 1 -1)))
(add-hook 'diff-hl-mode-hook #'+hunks-mouse-h)

(map! :leader :desc "This change (hunk)…" "g H" #'+hunks-menu)

(provide '+hunks)
;;; +hunks.el ends here
