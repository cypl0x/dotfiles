;;; lisp/+atuin.el --- Atuin's shell history, in Emacs and from Emacs -*- lexical-binding: t; -*-
;;
;; One history for the terminal and Emacs, both ways:
;;
;; Search   SPC s h    every command Atuin has (all shells, all hosts it
;;                     syncs), newest first, each with where it ran, how it
;;                     ended, how long it took and when:
;;                         nrs     ✔  2m10s  3h   ~/dotfiles
;;                     Narrow (consult): s succeeded, f failed, d run in this
;;                     directory, p in this project, h on this host.  RET:
;;                       in a shell buffer (eshell, shell, vterm, ghostel,
;;                       eat)  → onto its prompt, unrun
;;                       in a shell-command prompt (M-!, M-&, compile) → there
;;                       anywhere else → edit, then run it where it ran
;;          M-r        in M-! / M-& / compile prompts, and in eshell: the same,
;;                     inserting at the prompt
;;          Embark     copy, insert, run here, run where it ran, its
;;                     directory in dired, delete it from the history
;; Record   Commands Emacs runs go into Atuin as the shell's do, with their
;;          directory, exit status and duration, author "emacs": compile
;;          (and recompile, project-compile), M-!, M-&, and eshell.  So the
;;          terminal's Ctrl-R finds what you ran in Emacs.
;; Stats    SPC s H    `atuin stats': what you run most, here and everywhere
;;
;;; Code:

(require 'subr-x)
(require 'project)

(defvar consult--narrow)
(declare-function consult--read "ext:consult")
(declare-function eshell-bol "esh-mode" ())
(declare-function comint-bol "comint" (&optional arg))
(declare-function comint-kill-input "comint" ())
(declare-function vterm-send-string "ext:vterm" (string &optional paste-p))
(declare-function ghostel-send-string "ext:ghostel" (string))
(declare-function eat-term-send-string "ext:eat" (terminal string))
(defvar eat-terminal)
(defvar eshell-last-input-start)
(defvar eshell-last-input-end)
(defvar eshell-last-command-status)
(defvar embark-keymap-alist)

(defvar +atuin-record t
  "Non-nil: commands Emacs runs (compile, M-!, M-&, eshell) go into Atuin.")

(defvar +atuin--project nil "The project root while choosing (for narrowing with p).")

(defvar +atuin-author "emacs"
  "Who ran a recorded command, as Atuin's --author has it.")

;;;; Reading the history

(defun +atuin--entries ()
  "Atuin's history, newest first, as plists:
:command :dir :exit :duration :ago :host :time."
  (unless (executable-find "atuin") (user-error "atuin isn't installed"))
  (with-temp-buffer
    (let ((default-directory "~/")
          (coding-system-for-read 'utf-8))
      (call-process "atuin" nil '(t nil) nil "search" "--print0"
                    "--format" "{time}\t{exit}\t{duration}\t{directory}\t{host}\t{relativetime}\t{command}"))
    (let (entries)
      (dolist (rec (split-string (buffer-string) "\0" t))
        (pcase (split-string rec "\t")
          (`(,time ,exit ,duration ,dir ,host ,ago . ,command)
           (push (list :command (string-join command "\t") :dir dir :exit (string-to-number exit)
                       :duration duration :ago ago :host host :time time)
                 entries))))
      entries)))                        ; atuin lists oldest first

(defun +atuin--candidate (entry)
  "The completion candidate for ENTRY: its command on one line."
  (propertize (replace-regexp-in-string "\n" " ⏎ " (plist-get entry :command))
              '+atuin entry))

(defun +atuin--annotate (cand)
  (when-let* ((e (get-text-property 0 '+atuin cand)))
    (let ((exit (plist-get e :exit)))
      (concat
       (propertize " " 'display '(space :align-to (- right 60)))
       (cond ((zerop exit) (propertize "✔" 'face 'success))
             ((< exit 0) (propertize "…" 'face 'shadow))
             (t (propertize (format "✘%d" exit) 'face 'error)))
       (propertize (format " %7s" (plist-get e :duration)) 'face 'shadow)
       (propertize (format " %5s" (plist-get e :ago)) 'face 'font-lock-comment-face)
       " " (propertize (truncate-string-to-width (abbreviate-file-name (plist-get e :dir)) 30 nil nil "…")
                       'face 'dired-directory)
       (unless (equal (plist-get e :host) (system-name))
         (propertize (concat " @" (plist-get e :host)) 'face 'font-lock-keyword-face))))))

(defun +atuin--narrow-p (cand)
  (let ((e (get-text-property 0 '+atuin cand)))
    (pcase consult--narrow
      (?s (zerop (plist-get e :exit)))
      (?f (> (plist-get e :exit) 0))
      (?d (file-equal-p (plist-get e :dir) default-directory))
      (?h (equal (plist-get e :host) (system-name)))
      (?p (and +atuin--project (string-prefix-p +atuin--project (file-name-as-directory (expand-file-name (plist-get e :dir))))))
      (_ t))))

(defun +atuin--read (prompt)
  "Choose a command from Atuin's history; its entry plist."
  (let* ((dir default-directory)
         (+atuin--project (when-let* ((p (project-current))) (file-name-as-directory (expand-file-name (project-root p)))))
         (cands (mapcar #'+atuin--candidate (+atuin--entries)))
         (cand (if (require 'consult nil t)
                   (consult--read cands
                                  :prompt prompt
                                  :sort nil
                                  :require-match t
                                  :category '+atuin-command
                                  :annotate #'+atuin--annotate
                                  :narrow (list :predicate (lambda (c) (let ((default-directory dir)) (+atuin--narrow-p c)))
                                                :keys '((?s . "Succeeded") (?f . "Failed")
                                                        (?d . "Run here") (?p . "In this project")
                                                        (?h . "This host")))
                                  :history '+atuin--history)
                 (completing-read prompt (lambda (s p a) (if (eq a 'metadata)
                                                             '(metadata (display-sort-function . identity)
                                                                        (annotation-function . +atuin--annotate))
                                                           (complete-with-action a cands s p)))
                                  nil t))))
    (or (get-text-property 0 '+atuin cand)
        (get-text-property 0 '+atuin (or (car (member cand cands)) ""))
        (user-error "Not in the history: %s" cand))))

(defvar +atuin--history nil)

;;;; Using a command

(defun +atuin--insert-in-shell (command)
  "Put COMMAND on the prompt of the shell in this buffer; nil if it has none."
  (cond
   ((derived-mode-p 'eshell-mode)
    (goto-char (point-max)) (eshell-bol) (delete-region (point) (point-max)) (insert command) t)
   ((derived-mode-p 'comint-mode)
    (goto-char (point-max)) (comint-kill-input) (insert command) t)
   ((derived-mode-p 'vterm-mode) (vterm-send-string command) t)
   ((derived-mode-p 'ghostel-mode) (ghostel-send-string command) t)
   ((and (derived-mode-p 'eat-mode) (bound-and-true-p eat-terminal))
    (eat-term-send-string eat-terminal command) t)))

(defun +atuin-run (entry &optional here)
  "Edit ENTRY's command, then run it where it ran (HERE: in this directory)."
  (let* ((dir (if (or here (not (file-directory-p (plist-get entry :dir)))) default-directory
                (file-name-as-directory (plist-get entry :dir))))
         (default-directory dir)
         (command (read-shell-command (format "Run in %s: " (abbreviate-file-name dir))
                                      (plist-get entry :command))))
    (compile command)))

;;;###autoload
(defun +atuin/history ()
  "A command from Atuin's history: onto the shell's prompt, into the
shell-command prompt you're in, or edit and run it (see the file)."
  (interactive)
  (let ((minibuffer (minibufferp))
        (entry (let ((enable-recursive-minibuffers t)) (+atuin--read "Shell history: "))))
    (cond (minibuffer (delete-minibuffer-contents) (insert (plist-get entry :command)))
          ((+atuin--insert-in-shell (plist-get entry :command)))
          (t (+atuin-run entry)))))

;;;###autoload
(defun +atuin/stats (&optional here)
  "What you run most (`atuin stats'); with HERE (prefix), in this directory."
  (interactive "P")
  (let ((dir default-directory)
        (buf (get-buffer-create "*atuin stats*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (default-directory dir))
        (erase-buffer)
        (insert (propertize (format "Atuin: what you run most%s\n\n"
                                    (if here (format " in %s" (abbreviate-file-name dir)) ""))
                            'face 'bold))
        (apply #'call-process "atuin" nil t nil "stats" "--count" "25"
               (and here (list "--cwd" (expand-file-name dir))))
        (ansi-color-apply-on-region (point-min) (point-max)))
      (special-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;; Embark

(defun +atuin--entry-of (cand)
  (or (get-text-property 0 '+atuin cand) (list :command cand :dir default-directory :exit 0)))

(defun +atuin-embark-copy (cand)
  "Copy the command."
  (kill-new (plist-get (+atuin--entry-of cand) :command)))
(defun +atuin-embark-insert (cand)
  "Insert the command at point."
  (insert (plist-get (+atuin--entry-of cand) :command)))
(defun +atuin-embark-run-here (cand)
  "Edit and run the command in this directory."
  (+atuin-run (+atuin--entry-of cand) t))
(defun +atuin-embark-run-there (cand)
  "Edit and run the command where it ran."
  (+atuin-run (+atuin--entry-of cand)))
(defun +atuin-embark-dired (cand)
  "The directory the command ran in."
  (dired (plist-get (+atuin--entry-of cand) :dir)))
(defun +atuin--matches (command)
  "Every history entry `atuin search --delete' would take for COMMAND."
  (let ((default-directory "~/"))
    (with-temp-buffer
      (call-process "atuin" nil '(t nil) nil "search" "--search-mode" "prefix" "--include-duplicates"
                    "--print0" "--format" "{command}" "--" command)
      (split-string (buffer-string) "\0" t))))

(defun +atuin-embark-delete (cand)
  "Delete every run of exactly this command from Atuin's history.
Refuses when Atuin's match would take other commands too."
  (let* ((command (plist-get (+atuin--entry-of cand) :command))
         (matches (+atuin--matches command))
         (others (seq-remove (lambda (m) (equal m command)) matches)))
    (cond
     (others (user-error "Not deleted: Atuin's match would also take %d other command(s), e.g. «%s»"
                         (length (delete-dups others)) (car others)))
     ((yes-or-no-p (format "Delete all %d run(s) of «%s» from Atuin's history? " (length matches) command))
      (let ((default-directory "~/"))
        (call-process "atuin" nil nil nil "search" "--delete" "--search-mode" "prefix" "--" command))
      (message "Deleted from Atuin: %s" command)))))

(defvar-keymap +atuin-embark-map
  :doc "Actions on a command from Atuin's history."
  "w" #'+atuin-embark-copy  "i" #'+atuin-embark-insert  "r" #'+atuin-embark-run-here
  "R" #'+atuin-embark-run-there  "d" #'+atuin-embark-dired  "k" #'+atuin-embark-delete)

(with-eval-after-load 'embark
  (add-to-list 'embark-keymap-alist '(+atuin-command . +atuin-embark-map)))

;;;; Recording what Emacs runs

(defvar +atuin--session nil "This Emacs's Atuin session id.")

(defun +atuin--session ()
  (or +atuin--session
      (setq +atuin--session (string-trim (with-output-to-string
                                           (with-current-buffer standard-output
                                             (call-process "atuin" nil t nil "uuid")))))))

(defun +atuin--start (command)
  "Tell Atuin COMMAND starts in `default-directory'; (ID . START-TIME), or nil."
  (when (and +atuin-record (stringp command) (not (string-blank-p command))
             (not (file-remote-p default-directory)) (executable-find "atuin"))
    (let ((process-environment (cons (concat "ATUIN_SESSION=" (+atuin--session)) process-environment)))
      (with-temp-buffer
        (when (zerop (call-process "atuin" nil '(t nil) nil "history" "start"
                                   "--author" +atuin-author "--" command))
          (let ((id (string-trim (buffer-string))))
            (unless (string-empty-p id) (cons id (current-time)))))))))

(defun +atuin--end (started exit)
  "Tell Atuin the command STARTED (from `+atuin--start') ended with EXIT."
  (when started
    (let ((process-environment (cons (concat "ATUIN_SESSION=" (+atuin--session)) process-environment))
          (default-directory "~/"))
      (make-process :name "atuin-end" :noquery t :buffer nil :connection-type 'pipe
                    :command (list "atuin" "history" "end" "--exit" (number-to-string exit)
                                   "--duration" (format "%d" (* 1e9 (float-time (time-since (cdr started)))))
                                   (car started))))))

;; compile: the command as you gave it (`compilation-arguments'; the process
;; runs comint's "stty …; exec sh -c" wrapper), ended from its sentinel
;; (`compilation-finish-functions' come after the buffer lost the process).
(defun +atuin-compile-start-h (proc)
  (when-let* ((buf (process-buffer proc))
              (command (car (buffer-local-value 'compilation-arguments buf)))
              (started (let ((default-directory (buffer-local-value 'default-directory buf)))
                         (+atuin--start command))))
    (add-function :after (process-sentinel proc)
                  (lambda (p _)
                    (unless (or (process-live-p p) (process-get p '+atuin-ended))
                      (process-put p '+atuin-ended t)
                      (+atuin--end started (process-exit-status p)))))))

;; M-! and M-&: only what you typed (not every internal `shell-command').
(defvar +atuin--in-shell-command nil)
(defun +atuin-shell-command-a (fn command &optional output-buffer error-buffer)
  (if (or +atuin--in-shell-command (not (memq this-command '(shell-command async-shell-command))))
      (funcall fn command output-buffer error-buffer)
    (let* ((+atuin--in-shell-command t)
           (async (string-match-p "[ \t]*&[ \t]*\\'" command))
           (started (+atuin--start (string-trim-right command "[ \t]*&[ \t]*")))
           (result (funcall fn command output-buffer error-buffer)))
      (if (not async)
          (+atuin--end started (if (integerp result) result 0))
        (when-let* ((buf (or output-buffer (bound-and-true-p shell-command-buffer-name-async)))
                    (proc (get-buffer-process (if (bufferp buf) buf (get-buffer buf)))))
          (add-function :after (process-sentinel proc)
                        (lambda (p _)
                          (unless (process-live-p p) (+atuin--end started (process-exit-status p)))))))
      result)))

;; eshell
(defvar-local +atuin--eshell-started nil)
(defun +atuin-eshell-pre-h ()
  (setq +atuin--eshell-started
        (+atuin--start (string-trim (buffer-substring-no-properties eshell-last-input-start
                                                                    (1- eshell-last-input-end))))))
(defun +atuin-eshell-post-h ()
  (when +atuin--eshell-started
    (+atuin--end +atuin--eshell-started (or eshell-last-command-status 0))
    (setq +atuin--eshell-started nil)))

(add-hook 'compilation-start-hook #'+atuin-compile-start-h)
(advice-add 'shell-command :around #'+atuin-shell-command-a)
(add-hook 'eshell-pre-command-hook #'+atuin-eshell-pre-h)
(add-hook 'eshell-post-command-hook #'+atuin-eshell-post-h)

(map! :leader
      :desc "Shell history (Atuin)" "s h" #'+atuin/history
      :desc "Shell stats (Atuin)"   "s H" #'+atuin/stats)
(define-key minibuffer-local-shell-command-map (kbd "M-r") #'+atuin/history)
(map! :after eshell :map eshell-mode-map :i "M-r" #'+atuin/history :n "M-r" #'+atuin/history)

(provide '+atuin)
;;; +atuin.el ends here
