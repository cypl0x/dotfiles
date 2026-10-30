;;; lisp/+workflow.el --- Your shell loops, as project commands -*- lexical-binding: t; -*-
;;
;; Built from atuin evidence (2026-10-30, last 4000 commands):
;;   git pull <inari>:dev/<project> main   ≈350×  → SPC p u
;;   nix develop -c just …  (per project)   ≈300×  → SPC p h
;;   both, back to back                     ≈150×  → SPC p P
;;   rm X.gcl; git-closure b .; mv → .txt   ≈220×  → SPC p G
;;
;; Run commands are not configured anywhere: SPC p h offers the commands
;; that succeeded in this project's root, most frequent first, straight from
;; atuin, so the list follows what you actually do.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function magit-run-git-async "magit-process" (&rest args))
(declare-function magit-get-current-branch "magit-git" ())

(defvar +workflow-peer-format "cypl0x@wolfhard.net:/home/cypl0x/dev/%s"
  "Where the peer copy of a project lives; %s is the project directory name.")

(defvar +workflow-history-ignore
  (concat "\\`\\(?:cd\\|z\\|l\\|ls\\|ll\\|la\\|clear\\|exit\\|pwd\\|rm\\|mv\\|cp\\|cat\\|bat"
          "\\|less\\|man\\|tldr\\|which\\|echo\\|vim?\\|nvim\\|emacs\\|code\\|claude"
          "\\|git\\|gs\\|glo\\|lg\\|y\\|du\\|df\\|ps\\|kill\\|pkill\\|ping\\|ssh\\|scp\\|mosh"
          "\\|tmux\\|sudo\\|mkdir\\|touch\\|nix-collect-garbage\\|nh\\)\\_>")
  "Commands never offered as run commands.")

(defvar +workflow-closure-program
  (or (executable-find "git-closure")
      (expand-file-name "~/dev/git-closure/target/release/git-closure"))
  "The git-closure binary.")

(defvar +workflow--last-run (make-hash-table :test #'equal)
  "Project root → last command run there by `+workflow/run'.")

(defun +workflow--root ()
  (or (and (fboundp 'doom-project-root) (doom-project-root))
      (user-error "Not in a project")))

(defun +workflow--name (root)
  (file-name-nondirectory (directory-file-name root)))


;;; Run commands from history

(defun +workflow-history (dir)
  "Successful commands run in DIR per atuin, as (COMMAND . COUNT).
Most frequent first."
  (when (executable-find "atuin")
    (let ((counts (make-hash-table :test #'equal))
          (default-directory (file-name-as-directory (expand-file-name dir))))
      ;; `atuin search' de-duplicates, so it can't count; `history list --cwd'
      ;; lists every run in the current directory.
      (dolist (line (ignore-errors
                      (process-lines "atuin" "history" "list" "--cwd"
                                     "--format" "{exit}\t{command}")))
        (when (string-match "\\`0\t\\(.+\\)" line)
          (let ((cmd (string-trim (match-string 1 line))))
            (unless (or (string-empty-p cmd)
                        (string-match-p +workflow-history-ignore cmd))
              (cl-incf (gethash cmd counts 0))))))
      (sort (cl-loop for k being the hash-keys of counts using (hash-values v)
                     collect (cons k v))
            (lambda (a b) (> (cdr a) (cdr b)))))))

(defun +workflow--read-command (root)
  "Pick a command for ROOT: its history by frequency, the last one first."
  (let* ((hist (+workflow-history root))
         (last (gethash root +workflow--last-run))
         (cands (delete-dups (delq nil (cons last (mapcar #'car hist))))))
    (completing-read
     (format "Run in %s: " (+workflow--name root))
     (lambda (str pred action)
       (if (eq action 'metadata)
           `(metadata (display-sort-function . identity)
                      (annotation-function
                       . ,(lambda (c) (when-let* ((n (cdr (assoc c hist))))
                                        (format "  %d×" n)))))
         (complete-with-action action cands str pred)))
     nil nil nil nil (car cands))))

;;;###autoload
(defun +workflow/run (command)
  "Run COMMAND in the project root as a compilation, in its own buffer.
Interactively, choose from what succeeded there before (atuin), most
frequent first."
  (interactive (list (+workflow--read-command (+workflow--root))))
  (let* ((root (+workflow--root))
         (default-directory root)
         (compilation-buffer-name-function
          (lambda (_) (format "*run: %s*" (+workflow--name root)))))
    (puthash root command +workflow--last-run)
    (compile command)))


;;; Pull from the peer

(defvar +workflow-peer-host-regexp "@\\(?:wolfhard\\.net\\|100\\.94\\.247\\.95\\|inari\\):"
  "A remote URL matching this already points at the peer; it wins over the pattern.")

(defun +workflow--peer-url (root)
  "The peer URL for ROOT: a remote on the peer host, else `+workflow-peer-format'."
  (let ((default-directory root))
    (or (cl-loop for line in (ignore-errors (process-lines "git" "remote" "-v"))
                 for url = (cadr (split-string line))
                 when (and url (string-match-p +workflow-peer-host-regexp url))
                 return url)
        (format +workflow-peer-format (+workflow--name root)))))

;;;###autoload
(defun +workflow/pull-from-peer (&optional then)
  "Fast-forward this project's current branch from its peer copy (via magit).
Calls THEN with no arguments if the pull succeeds."
  (interactive)
  (require 'magit)
  (let* ((root (+workflow--root))
         (default-directory root)
         (url (+workflow--peer-url root))
         (branch (or (magit-get-current-branch) "main"))
         (proc (magit-run-git-async "pull" "--ff-only" url branch)))
    (message "Pulling %s from %s…" branch url)
    ;; :before, so a failing `magit-refresh' in magit's own sentinel (e.g. when
    ;; called from a buffer outside the repo) can't swallow THEN.
    (add-function :before (process-sentinel proc)
                  (lambda (p _)
                    (when (memq (process-status p) '(exit signal))
                      (if (zerop (process-exit-status p))
                          (when then (funcall then))
                        (message "Pull from peer failed; see magit's process buffer ($)")))))
    proc))

;;;###autoload
(defun +workflow/pull-and-run (&optional choose)
  "Pull from the peer, then rerun the last (or most frequent) command.
With prefix arg CHOOSE, pick the command first."
  (interactive "P")
  (let* ((root (+workflow--root))
         (command (if (or choose (not (or (gethash root +workflow--last-run)
                                           (car (car (+workflow-history root))))))
                      (+workflow--read-command root)
                    (or (gethash root +workflow--last-run)
                        (car (car (+workflow-history root)))))))
    (+workflow/pull-from-peer
     (lambda () (let ((default-directory root)) (+workflow/run command))))))


;;; git-closure snapshots

;;;###autoload
(defun +workflow/closure-snapshot ()
  "Write a fresh git-closure snapshot of the project as NAME.gcl.txt in its root.
Replaces the old one, then puts the file's path on the kill ring."
  (interactive)
  (unless (file-executable-p +workflow-closure-program)
    (user-error "git-closure not found: %s" +workflow-closure-program))
  (let* ((root (+workflow--root))
         (default-directory root)
         (out (expand-file-name (concat (+workflow--name root) ".gcl.txt") root)))
    (dolist (f (list out (string-remove-suffix ".txt" out)))
      (when (file-exists-p f) (delete-file f)))
    (message "git-closure: snapshotting %s…" (+workflow--name root))
    (make-process
     :name "git-closure" :buffer (get-buffer-create "*git-closure*") :noquery t
     :command (list +workflow-closure-program "build" "." "--output" out)
     :sentinel (lambda (p _)
                 (unless (process-live-p p)
                   (if (and (zerop (process-exit-status p)) (file-exists-p out))
                       (progn (kill-new out)
                              (message "git-closure: %s (%s), path copied"
                                       (file-name-nondirectory out)
                                       (file-size-human-readable
                                        (file-attribute-size (file-attributes out)))))
                     (pop-to-buffer (process-buffer p))
                     (message "git-closure failed")))))))

(map! :leader
      (:prefix "p"
       :desc "Run from history"       "h" #'+workflow/run
       :desc "Pull from peer"         "u" #'+workflow/pull-from-peer
       :desc "Pull from peer & rerun" "P" #'+workflow/pull-and-run
       :desc "git-closure snapshot"   "G" #'+workflow/closure-snapshot))

(provide '+workflow)
;;; +workflow.el ends here
