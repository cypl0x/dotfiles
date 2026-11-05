;;; familiar-history.el --- Every AI turn, in one Org history -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; One record of what was asked and answered, wherever: M-ß, ß in the
;; shell (the Atuin server), OpenAI-compatible clients, familiar's tasks
;; (explain, review, commit messages...).  Monthly Org files under
;; `familiar-history-directory', one heading per turn:
;;
;;   * Which ripgrep is in unstable?                        :openai:
;;     :PROPERTIES:
;;     :TIME:   [2026-11-04 Wed 13:50]
;;     :TASK:   openai     :MODEL: claude-haiku-5-5
;;     :TOKENS: 120 in, 35 out     :COST: 0.000161
;;     :LINK:   (M-ß turns: the conversation they belong to)
;;     :END:
;;     #+begin_quote ... the question ... #+end_quote
;;     the answer (in an example block)
;;
;; What was asked and what came back; not system prompts or the Emacs
;; context sent along (the M-ß conversation files keep that).
;;
;;   SPC A j / M-x familiar-history          search all turns
;;   M-x familiar-history-open               this month's file
;;   C-c C-r (on a turn) / familiar-history-replay   ask it again (M-ß)
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function org-escape-code-in-string "org-src" (s))
(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin))
(declare-function consult-ripgrep "ext:consult" (&optional dir initial))
(declare-function org-back-to-heading "org" (&optional invisible-ok))

(defgroup familiar-history nil
  "One Org history of every AI turn."
  :group 'familiar)

(defcustom familiar-history-directory (locate-user-emacs-file "familiar-history/")
  "Where the history lives: one Org file per month."
  :type 'directory)

(defcustom familiar-history-enabled t
  "Whether turns are recorded."
  :type 'boolean)

(defun familiar-history-file (&optional time)
  "The history file for the month of TIME (default now)."
  (expand-file-name (format-time-string "%Y-%m.org" time) familiar-history-directory))

(defun familiar-history--block (text)
  "TEXT inside an example block, escaped so no line becomes Org structure."
  (require 'org-src)
  (concat "#+begin_example\n"
          (org-escape-code-in-string (string-trim-right (or text "")))
          "\n#+end_example\n"))

(defun familiar-history--title (prompt)
  "A heading from PROMPT: its first non-empty line, at most 80 characters."
  (let ((line (or (seq-find (lambda (l) (not (string-blank-p l)))
                            (split-string (or prompt "") "\n"))
                  "(empty)")))
    (truncate-string-to-width (string-trim (replace-regexp-in-string "[][]" "" line))
                              80 nil nil "…")))

(cl-defun familiar-history-record (&key prompt answer task model tokens cost link calls time)
  "Append one turn: PROMPT and ANSWER, by TASK on MODEL.
TOKENS is a plist (:input :output), COST a number, LINK an Org link to
the conversation, CALLS a list of strings (tool calls made), TIME when."
  (when familiar-history-enabled
    (let* ((time (or time (current-time)))
           (file (familiar-history-file time))
           (tag (replace-regexp-in-string "[^[:alnum:]_@]" "_" (format "%s" (or task "ask")))))
      (make-directory familiar-history-directory t)
      (with-file-modes #o600
        (unless (file-exists-p file)
          (write-region (format-time-string "#+title: familiar history %Y-%m\n#+startup: overview\n\n" time)
                        nil file nil 'silent))
        (write-region
         (concat
          (format "* %s  :%s:\n:PROPERTIES:\n" (familiar-history--title prompt) tag)
          (format-time-string ":TIME:     [%F %a %R]\n" time)
          (format ":TASK:     %s\n:MODEL:    %s\n" (or task "ask") (or model ""))
          (if tokens
              (format ":TOKENS:   %s in, %s out\n"
                      (or (plist-get tokens :input) 0) (or (plist-get tokens :output) 0))
            "")
          (if cost (format ":COST:     %.6f\n" cost) "")
          (if link (format ":LINK:     %s\n" link) "")
          ":END:\n"
          "#+begin_quote\n" (org-escape-code-in-string (string-trim (or prompt ""))) "\n#+end_quote\n"
          (if calls (concat (mapconcat (lambda (c) (concat "- " c)) calls "\n") "\n") "")
          (if (string-blank-p (or answer "")) "" (familiar-history--block answer))
          "\n")
         nil file 'append 'silent)))))

(defun familiar-history-prompt-text (prompt)
  "The last thing the user said in PROMPT.
PROMPT is as `gptel-request' takes it: a string or a list of turns."
  (cond ((stringp prompt) prompt)
        ((consp prompt)
         ;; Turns alternate from the user: the last user turn.
         (nth (* 2 (/ (1- (length prompt)) 2)) prompt))
        (t "")))

;;;; Looking back

(defcustom familiar-history-transcript-roots
  '("~/.claude/transcripts" "~/.agent-shell/transcripts" "~/dotfiles" "~/dev" "~/todo")
  "Where agent transcripts are.
Directories, or roots searched (depth 4) for per-project
.agent-shell/transcripts.  The same places agent-recall indexes."
  :type '(repeat directory))

(defvar familiar-history--transcripts nil "Transcript directories, found once.")

(defun familiar-history-transcript-directories ()
  "Directories holding agent-shell and Claude Code transcripts."
  (or familiar-history--transcripts
      (setq familiar-history--transcripts
            (delete-dups
             (cl-loop for root in familiar-history-transcript-roots
                      for dir = (expand-file-name root)
                      when (file-directory-p dir)
                      append (if (equal (file-name-nondirectory (directory-file-name dir)) "transcripts")
                                 (list dir)
                               (seq-filter
                                (lambda (d) (string-suffix-p "/.agent-shell/transcripts" (directory-file-name d)))
                                (and (executable-find "fd")
                                     (process-lines-ignore-status
                                      "fd" "--hidden" "--no-ignore" "--type" "d" "--max-depth" "4"
                                      "--absolute-path" "^transcripts$" dir)))))))))

;;;###autoload
(defun familiar-history (&optional only-history)
  "Search every recorded turn, and the agent transcripts too.
With ONLY-HISTORY (prefix arg), just familiar's history."
  (interactive "P")
  (make-directory familiar-history-directory t)
  (if (fboundp 'consult-ripgrep)
      (consult-ripgrep (if only-history familiar-history-directory
                         (cons familiar-history-directory
                               (familiar-history-transcript-directories))))
    (let ((default-directory familiar-history-directory))
      (call-interactively #'rgrep))))

;;;###autoload
(defun familiar-history-open ()
  "This month's history."
  (interactive)
  (find-file (familiar-history-file))
  (goto-char (point-max)))

;;;###autoload
(defun familiar-history-replay ()
  "Ask the turn at point again, in a fresh M-ß conversation."
  (interactive)
  (let ((prompt (save-excursion
                  (org-back-to-heading t)
                  (when (re-search-forward "^#\\+begin_quote\n\\(\\(?:.\\|\n\\)*?\\)\n#\\+end_quote" nil t)
                    (replace-regexp-in-string "^," "" (match-string-no-properties 1))))))
    (unless prompt (user-error "No turn here"))
    (familiar-ask prompt t)))

(defvar-keymap familiar-history-mode-map
  "C-c C-r" #'familiar-history-replay)

(define-minor-mode familiar-history-mode
  "In a familiar history file: \\[familiar-history-replay] asks a turn again."
  :lighter " ✦hist")

;; A minor mode, not `local-set-key': Org buffers share one keymap, and
;; C-c C-r is `org-reveal' everywhere else.
(defun familiar-history--mode-h ()
  "Turn on `familiar-history-mode' in files of `familiar-history-directory'."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name familiar-history-directory))
    (familiar-history-mode 1)))
(add-hook 'org-mode-hook #'familiar-history--mode-h)

(provide 'familiar-history)
;;; familiar-history.el ends here
