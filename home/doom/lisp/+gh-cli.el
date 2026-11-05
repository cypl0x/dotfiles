;;; lisp/+gh-cli.el --- All of gh in Emacs, and writing to GitHub -*- lexical-binding: t; -*-
;;
;; The GitHub menu (SPC o G, +gh-browse.el) reads; this file acts:
;;
;; Every command   SPC o G x: each of gh's commands and subcommands (read
;;                 from gh's own help, so new ones appear by themselves),
;;                 with its description; flags complete from its --help.
;;                 Output in an Emacs buffer (via `compile', so it lands in
;;                 Atuin too); anything that wants an editor gets this Emacs
;;                 (GH_EDITOR=emacsclient).
;; Writing         issues, comments, pull requests, reviews and gists in a
;;                 Markdown buffer: C-c C-c sends, C-c C-k drops.
;; Issues & PRs    on a row or in a view, . : comment, close/reopen, merge,
;;                 approve, request changes, ready, checkout, work on it
;;                 (a branch named after the issue, assigned to you).
;; Actions         runs with their state, the log of a run (failed steps
;;                 only, or all) where errors jump, watch one live, rerun,
;;                 cancel; workflows: run, enable, disable.
;; Code search     grep across GitHub (this repo, an owner, everywhere):
;;                 RET opens the file in /github at the match.
;; Gists           from the region or buffer; yours, listed and readable.
;; Repositories    fork, create from this directory, edit description and
;;                 topics, .gitignore and license templates.
;; Releases        notes rendered, assets downloaded.
;; Notifications   r marks one read, R all.
;; API             a request (REST or GraphQL) and its JSON, pretty.
;; Locally         Markdown previewed as GitHub renders it (refreshes on
;;                 save); merged or gone branches cleaned up safely.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)

(defvar +gh-browse--list-place)
(defvar +gh-fs-cache-directory)
(defvar +gh-render-images)
(defvar shr-inhibit-images)
(defvar browse-url-handlers)
(defvar gfm-mode-map)
(declare-function +gh-browse--here "+gh-browse" (&optional prompt))
(declare-function +gh-browse--place-at "+gh-browse" (&optional file))
(declare-function +gh-browse--parse "+gh-browse" (target &optional url-only))
(declare-function +gh-browse-open "+gh-browse" (place &optional line))
(declare-function +gh-browse-note "+gh-browse" (kind &rest props))
(declare-function +gh--repo-arg "+gh-browse" (p))
(declare-function +gh--gh "+gh-browse" (&rest args))
(declare-function +gh--json "+gh-browse" (&rest args))
(declare-function +gh--age "+gh-browse" (iso))
(declare-function +gh--remote-place "+gh-browse" (dir))
(declare-function +gh-list-show "+gh-browse" (name format rows &optional place more how))
(declare-function +gh-list--id "+gh-browse" ())
(declare-function +gh-list--sort-number "+gh-browse" (a b))
(declare-function +gh-list-redo "+gh-browse" ())
(declare-function +gh-render-mode "+gh-browse" ())
(declare-function +gh-render--browse "+gh-browse" (url &rest _))
(declare-function +gh/clone "+gh-browse" (&optional kind))
(declare-function +gh-place-owner "+gh-browse" (p))
(declare-function +gh-place-repo "+gh-browse" (p))
(declare-function +gh-place-path "+gh-browse" (p))
(declare-function +gh-place-ref "+gh-browse" (p))
(declare-function +gh-place-make "+gh-browse" (&rest args))
(declare-function shr-insert-document "shr" (dom))
(declare-function libxml-parse-html-region "xml.c" (start end &optional base-url discard-comments))
(declare-function gfm-mode "ext:markdown-mode" ())
(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))
(declare-function json-pretty-print-buffer "json" (&optional minimize))
(declare-function magit-status-setup-buffer "ext:magit-status" (&optional directory))

;;;; Running gh

(defun +gh-cli--env ()
  "The environment for gh: this Emacs as its editor, colors on."
  (append (list "GH_EDITOR=emacsclient" "GH_PROMPT_DISABLED=1" "CLICOLOR_FORCE=1" "GH_FORCE_TTY=120")
          process-environment))

(defun +gh-cli-compile (args &optional dir name)
  "Run gh with ARGS (a list) in a compilation buffer (NAME), in DIR."
  (let* ((default-directory (or dir (if (file-remote-p default-directory) temporary-file-directory default-directory)))
         (process-environment (+gh-cli--env))
         (command (mapconcat #'shell-quote-argument (cons "gh" args) " ")))
    (+gh-browse-note 'gh :command command)
    (compilation-start command 'compilation-mode
                       (lambda (_) (or name (format "*gh %s*" (string-join (seq-take args 2) " ")))))))

(defun +gh-cli-async (args &optional done)
  "Run gh with ARGS in the background; DONE gets the output on success."
  (let ((buf (generate-new-buffer " *gh*"))
        (default-directory temporary-file-directory))
    (make-process :name "gh" :buffer buf :command (cons "gh" args) :noquery t
                  :sentinel (lambda (proc _)
                              (unless (process-live-p proc)
                                (let ((out (with-current-buffer buf (string-trim (buffer-string)))))
                                  (kill-buffer buf)
                                  (if (zerop (process-exit-status proc))
                                      (if done (funcall done out) (message "gh: %s" (car (last (split-string out "\n" t))))))
                                  (unless (zerop (process-exit-status proc))
                                    (message "gh %s failed: %s" (car args) out))))))))

;;;; Every command: the palette

(defvar +gh-cli--commands nil "((\"issue create\" . DESCRIPTION) …), read from gh's help.")

(defun +gh-cli--help-lines (args)
  (with-temp-buffer
    (let ((default-directory temporary-file-directory))
      (apply #'call-process "gh" nil t nil (append args '("--help"))))
    (split-string (buffer-string) "\n")))

(defun +gh-cli--commands-in (args)
  "Commands listed in `gh ARGS --help': ((NAME . DESCRIPTION) …)."
  (let (in out)
    (dolist (line (+gh-cli--help-lines args))
      (cond ((string-match-p "\\`[A-Z][A-Z ]*COMMANDS\\'" line) (setq in t))
            ((string-match-p "\\`[A-Z]" line) (setq in nil))
            ((and in (string-match "\\`  \\([a-z][a-z0-9-]*\\):?\\s-+\\(.*\\)\\'" line))
             (push (cons (match-string 1 line) (match-string 2 line)) out))))
    (nreverse out)))

(defun +gh-cli-commands ()
  "Every gh command and subcommand with its description (cached on disk
per gh version)."
  (or +gh-cli--commands
      (let* ((version (car (split-string (+gh--gh "--version") "\n")))
             (file (expand-file-name (format "gh-commands-%s.eld" (md5 version)) +gh-fs-cache-directory)))
        (setq +gh-cli--commands
              (if (file-exists-p file)
                  (with-temp-buffer (insert-file-contents file) (read (current-buffer)))
                (let ((all (cl-loop for (top . desc) in (+gh-cli--commands-in nil)
                                    for subs = (+gh-cli--commands-in (list top))
                                    collect (cons top desc)
                                    append (mapcar (lambda (s) (cons (concat top " " (car s)) (cdr s))) subs))))
                  (make-directory (file-name-directory file) t)
                  (with-temp-file file (prin1 all (current-buffer)))
                  all))))))

(defun +gh-cli--flags (command)
  "Flags of `gh COMMAND' with their descriptions, from its --help."
  (cl-loop for line in (+gh-cli--help-lines (split-string command))
           when (string-match "\\`\\s-+\\(?:-[a-zA-Z], \\)?\\(--[a-z0-9-]+\\)\\(?: [a-z]+\\)?\\s-+\\(.*\\)\\'" line)
           collect (cons (match-string 1 line) (match-string 2 line))))

(defun +gh/run (command args)
  "Run any gh COMMAND with ARGS (flags complete; output in a buffer)."
  (interactive
   (let* ((cmds (+gh-cli-commands))
          (completion-extra-properties
           (list :annotation-function (lambda (c) (concat "  " (propertize (or (cdr (assoc c cmds)) "") 'face 'shadow)))))
          (command (completing-read "gh " (mapcar #'car cmds) nil t))
          (flags (+gh-cli--flags command))
          (here (ignore-errors (+gh-browse--place-at)))
          (default (when (and here (assoc "--repo" flags)) (format "-R %s " (+gh--repo-arg here))))
          (args (minibuffer-with-setup-hook
                    (lambda ()
                      (setq-local completion-at-point-functions
                                  (list (lambda ()
                                          (let ((beg (save-excursion (skip-chars-backward "-a-z0-9") (point))))
                                            (when (eq (char-after beg) ?-)
                                              (list beg (point) (mapcar #'car flags)
                                                    :annotation-function
                                                    (lambda (f) (concat "  " (cdr (assoc f flags)))))))))))
                  (read-string (format "gh %s (TAB completes flags) " command) default))))
     (list command (split-string-and-unquote args))))
  (+gh-cli-compile (append (split-string command) args)))

;;;; Writing: compose buffers

(defvar-local +gh-compose--send nil "Function of (TITLE BODY) that sends this buffer.")
(defvar-local +gh-compose--title-p nil "Non-nil: the first line is the title.")

(defvar-keymap +gh-compose-mode-map
  "C-c C-c" #'+gh-compose-send  "C-c C-k" #'+gh-compose-cancel)

(define-minor-mode +gh-compose-mode
  "Writing something for GitHub: C-c C-c sends it, C-c C-k drops it."
  :lighter " ✍GitHub")

(defun +gh-compose (name intro send &optional title-p initial)
  "A buffer NAME to write in; INTRO explains; SEND gets (TITLE BODY).
With TITLE-P the first line is the title.  INITIAL: text to start with."
  (let ((buf (generate-new-buffer name)))
    (with-current-buffer buf
      (if (fboundp 'gfm-mode) (gfm-mode) (text-mode))
      (+gh-compose-mode 1)
      (setq +gh-compose--send send +gh-compose--title-p title-p)
      (setq-local header-line-format
                  (list " " (propertize intro 'face 'bold)
                        (propertize (concat (if title-p "   first line: title · " "   ") "C-c C-c send · C-c C-k drop")
                                    'face 'shadow)))
      (when initial (insert initial))
      (goto-char (point-min)))
    (pop-to-buffer buf)
    (when (fboundp 'evil-insert-state) (evil-insert-state))
    buf))

(defun +gh-compose-send ()
  "Send what's written."
  (interactive)
  (let* ((text (string-trim (buffer-string)))
         (title (and +gh-compose--title-p (car (split-string text "\n"))))
         (body (if +gh-compose--title-p (string-trim (string-join (cdr (split-string text "\n")) "\n")) text)))
    (when (and +gh-compose--title-p (string-empty-p (or title ""))) (user-error "The first line (the title) is empty"))
    (funcall +gh-compose--send title body)
    (let ((kill-buffer-query-functions nil)) (set-buffer-modified-p nil) (kill-buffer))))

(defun +gh-compose-cancel ()
  "Drop what's written."
  (interactive)
  (when (or (string-empty-p (string-trim (buffer-string))) (y-or-n-p "Drop this text? "))
    (set-buffer-modified-p nil) (kill-buffer)))

(defun +gh-cli--body-file (body)
  (make-temp-file "gh-body" nil ".md" body))

(defun +gh-cli--send (args body &optional then)
  "gh ARGS with BODY as --body-file, in the background; THEN gets the output."
  (let ((file (+gh-cli--body-file body)))
    (+gh-cli-async (append args (list "--body-file" file))
                   (lambda (out) (delete-file file)
                     (if then (funcall then out) (message "GitHub: %s" (car (last (split-string out "\n" t)))))))))

(defun +gh/issue-create (place)
  "Write a new issue for PLACE's repository."
  (interactive (list (+gh-browse--here)))
  (+gh-compose (format "*new issue: %s*" (+gh--repo-arg place)) (format "New issue in %s" (+gh--repo-arg place))
               (lambda (title body)
                 (+gh-cli--send (list "issue" "create" "-R" (+gh--repo-arg place) "--title" title) body
                                (lambda (url) (kill-new url) (message "Created %s (URL copied)" url))))
               t))

(defun +gh--local-repo-dir ()
  (or (locate-dominating-file default-directory ".git") (user-error "Not in a local git repository")))

(defun +gh/pr-create ()
  "Write a pull request for this local branch (pushes it if needed)."
  (interactive)
  (let* ((dir (+gh--local-repo-dir))
         (default-directory dir)
         (branch (string-trim (shell-command-to-string "git rev-parse --abbrev-ref HEAD")))
         (log (string-trim (shell-command-to-string "git log --format='- %s' @{u}..HEAD 2>/dev/null || git log --format='- %s' -10"))))
    (+gh-compose (format "*new PR: %s*" branch) (format "Pull request from %s" branch)
                 (lambda (title body)
                   (let ((default-directory dir))
                     (+gh-cli--send (list "pr" "create" "--title" title "--head" branch) body
                                    (lambda (url) (kill-new url) (message "Opened %s (URL copied)" url)))))
                 t (concat "\n\n" log))))

(defun +gh/gist-create (beg end &optional public)
  "A gist of the region BEG..END (the buffer without one); PUBLIC with a prefix."
  (interactive (if (use-region-p) (list (region-beginning) (region-end) current-prefix-arg)
                 (list (point-min) (point-max) current-prefix-arg)))
  (let* ((name (if buffer-file-name (file-name-nondirectory buffer-file-name) "snippet.txt"))
         (dir (make-temp-file "gist" t))
         (file (expand-file-name name dir)))
    (write-region beg end file nil 'silent)
    (when (y-or-n-p (format "Create a %s gist of %s (%d characters)? " (if public "PUBLIC" "secret") name (- end beg)))
      (+gh-cli-async (append (list "gist" "create" file) (and public '("--public")))
                     (lambda (url) (delete-directory dir t) (kill-new url) (message "Gist: %s (copied)" url))))))

;;;; Issues and pull requests: actions

(defun +gh-cli--topic ()
  "(KIND NUMBER PLACE) of the issue or PR at point, in a list or a view."
  (let ((id (ignore-errors (+gh-list--id))))
    (cond
     ((memq (car-safe id) '(:issue :pr)) (list (if (eq (car id) :pr) "pr" "issue") (cadr id) (plist-get id :place)))
     ((string-match "\\*GitHub \\(issue\\|pr\\) \\([^#]+\\)#\\([0-9]+\\)\\*" (buffer-name))
      (list (match-string 1 (buffer-name)) (string-to-number (match-string 3 (buffer-name)))
            (+gh-browse--parse (match-string 2 (buffer-name)))))
     (t (user-error "No issue or pull request here")))))

(defun +gh-cli--refresh-later ()
  (let ((buf (current-buffer)))
    (run-at-time 1.5 nil (lambda () (when (buffer-live-p buf)
                                      (with-current-buffer buf
                                        (when (derived-mode-p 'tabulated-list-mode) (ignore-errors (+gh-list-redo)))))))))

(defun +gh/topic-comment ()
  "Comment on the issue or PR at point."
  (interactive)
  (pcase-let ((`(,kind ,n ,p) (+gh-cli--topic)))
    (+gh-compose (format "*comment: %s#%d*" (+gh--repo-arg p) n) (format "Comment on %s#%d" (+gh--repo-arg p) n)
                 (lambda (_ body) (+gh-cli--send (list kind "comment" (number-to-string n) "-R" (+gh--repo-arg p)) body)))))

(defun +gh/topic-close ()
  "Close (or reopen) the issue or PR at point."
  (interactive)
  (pcase-let* ((`(,kind ,n ,p) (+gh-cli--topic))
               (state (plist-get (+gh--json kind "view" (number-to-string n) "-R" (+gh--repo-arg p) "--json" "state") :state))
               (verb (if (equal state "OPEN") "close" "reopen")))
    (when (y-or-n-p (format "%s %s %s#%d? " (capitalize verb) kind (+gh--repo-arg p) n))
      (+gh-cli-async (list kind verb (number-to-string n) "-R" (+gh--repo-arg p)))
      (+gh-cli--refresh-later))))

(defun +gh/pr-merge (method)
  "Merge the PR at point by METHOD (merge, squash, rebase)."
  (interactive (list (completing-read "Merge how? " '("squash" "merge" "rebase") nil t)))
  (pcase-let ((`(,kind ,n ,p) (+gh-cli--topic)))
    (unless (equal kind "pr") (user-error "Not a pull request"))
    (when (y-or-n-p (format "Merge %s#%d (%s)? " (+gh--repo-arg p) n method))
      (+gh-cli-async (list "pr" "merge" (number-to-string n) "-R" (+gh--repo-arg p) (concat "--" method)))
      (+gh-cli--refresh-later))))

(defun +gh/pr-review (verdict)
  "Review the PR at point: VERDICT approve, request-changes or comment."
  (interactive (list (completing-read "Review: " '("approve" "request-changes" "comment") nil t)))
  (pcase-let ((`(,kind ,n ,p) (+gh-cli--topic)))
    (unless (equal kind "pr") (user-error "Not a pull request"))
    (+gh-compose (format "*review: %s#%d*" (+gh--repo-arg p) n) (format "Review (%s) of %s#%d" verdict (+gh--repo-arg p) n)
                 (lambda (_ body) (+gh-cli--send (list "pr" "review" (number-to-string n) "-R" (+gh--repo-arg p)
                                                       (concat "--" verdict))
                                                 body)))))

(defun +gh/pr-ready ()
  "Mark the draft PR at point ready for review."
  (interactive)
  (pcase-let ((`(_ ,n ,p) (+gh-cli--topic)))
    (+gh-cli-async (list "pr" "ready" (number-to-string n) "-R" (+gh--repo-arg p)))))

(defun +gh--clone-dir (p)
  (let ((local (and (ignore-errors (+gh--local-repo-dir))
                    (+gh--remote-place (+gh--local-repo-dir)))))
    (if (and local (equal (+gh--repo-arg local) (+gh--repo-arg p)))
        (+gh--local-repo-dir)
      (let ((dir (expand-file-name (+gh--repo-arg p) (bound-and-true-p +gh-browse-clone-dir))))
        (unless (file-directory-p dir)
          (user-error "No local clone of %s: clone it first (SPC o G C)" (+gh--repo-arg p)))
        dir))))

(defun +gh/pr-checkout ()
  "Check the PR at point out in its local clone, then magit."
  (interactive)
  (pcase-let* ((`(_ ,n ,p) (+gh-cli--topic)) (dir (+gh--clone-dir p)))
    (let ((default-directory dir))
      (+gh-cli-async (list "pr" "checkout" (number-to-string n) "-R" (+gh--repo-arg p))
                     (lambda (_) (let ((default-directory dir))
                                   (if (fboundp 'magit-status-setup-buffer) (magit-status-setup-buffer dir) (dired dir))))))))

(defun +gh/issue-workon ()
  "Work on the issue at point: a branch N-its-title in the local clone,
checked out, and the issue assigned to you."
  (interactive)
  (pcase-let* ((`(,kind ,n ,p) (+gh-cli--topic)))
    (unless (equal kind "issue") (user-error "Not an issue"))
    (let* ((dir (+gh--clone-dir p))
           (title (plist-get (+gh--json "issue" "view" (number-to-string n) "-R" (+gh--repo-arg p) "--json" "title") :title))
           (branch (read-string "Branch: " (format "%d-%s" n (string-trim (replace-regexp-in-string "[^a-z0-9]+" "-" (downcase title)) "-" "-")))))
      (let ((default-directory dir))
        (unless (zerop (call-process "git" nil nil nil "switch" "-c" branch))
          (user-error "git switch -c %s failed in %s" branch dir)))
      (when (y-or-n-p (format "Assign %s#%d to yourself? " (+gh--repo-arg p) n))
        (+gh-cli-async (list "issue" "edit" (number-to-string n) "-R" (+gh--repo-arg p) "--add-assignee" "@me")))
      (if (fboundp 'magit-status-setup-buffer) (magit-status-setup-buffer dir) (dired dir)))))

(transient-define-prefix +gh-topic-menu ()
  "What to do with this issue or pull request."
  [:description (lambda () (pcase-let ((`(,k ,n ,p) (ignore-errors (+gh-cli--topic))))
                             (if n (format "%s %s#%d" (if (equal k "pr") "Pull request" "Issue") (+gh--repo-arg p) n) "GitHub")))
   ["Talk"
    ("c" "Comment" +gh/topic-comment)
    ("x" "Close / reopen" +gh/topic-close)]
   ["Pull request"
    ("a" "Review: approve / changes / comment" +gh/pr-review)
    ("m" "Merge" +gh/pr-merge)
    ("r" "Ready for review" +gh/pr-ready)
    ("k" "Check out locally + magit" +gh/pr-checkout)]
   ["Issue"
    ("w" "Work on it (branch, assign)" +gh/issue-workon)]])

;;;; Actions

(defun +gh--run-icon (status conclusion)
  (pcase (or (and (equal status "completed") conclusion) status)
    ("success" (propertize "✔" 'face 'success)) ("failure" (propertize "✘" 'face 'error))
    ("cancelled" (propertize "⊘" 'face 'shadow)) ("skipped" (propertize "↷" 'face 'shadow))
    ((or "in_progress" "queued" "waiting" "pending") (propertize "…" 'face 'warning))
    (other (or other "?"))))

(defun +gh/runs (&optional place)
  "Actions runs of this repository (PLACE): newest first."
  (interactive)
  (let ((p (or place (+gh-browse--here)
               (+gh--remote-place (+gh--local-repo-dir)))))
    (+gh-list-show (format "*GitHub runs: %s*" (+gh--repo-arg p))
                   [("" 2 nil) ("Workflow" 26 t) ("Branch" 16 t) ("Event" 10 t) ("Age" 6 t) ("Title" 0 nil)]
                   (mapcar (lambda (r)
                             (list (list :run (plist-get r :databaseId) :place p)
                                   (vector (+gh--run-icon (plist-get r :status) (plist-get r :conclusion))
                                           (plist-get r :workflowName) (plist-get r :headBranch) (plist-get r :event)
                                           (+gh--age (plist-get r :createdAt)) (plist-get r :displayTitle))))
                           (+gh--json "run" "list" "-R" (+gh--repo-arg p) "-L" "50" "--json"
                                      "databaseId,status,conclusion,workflowName,headBranch,event,createdAt,displayTitle"))
                   p nil (list #'+gh/runs p))))

(defun +gh-cli--run-at ()
  (let ((id (+gh-list--id)))
    (unless (eq (car id) :run) (user-error "Not a run"))
    (list (number-to-string (cadr id)) (+gh--repo-arg (plist-get id :place)))))

(defun +gh/run-log (&optional all)
  "The log of the run at point: its failed steps (ALL with a prefix)."
  (interactive "P")
  (pcase-let ((`(,id ,repo) (+gh-cli--run-at)))
    (+gh-cli-compile (list "run" "view" id "-R" repo (if all "--log" "--log-failed")) nil
                     (format "*gh run %s log*" id))))

(defun +gh/run-watch ()
  "Watch the run at point live."
  (interactive)
  (pcase-let ((`(,id ,repo) (+gh-cli--run-at)))
    (+gh-cli-compile (list "run" "watch" id "-R" repo "--exit-status") nil (format "*gh run %s watch*" id))))

(defun +gh/run-rerun (&optional all)
  "Rerun the run at point: its failed jobs (ALL with a prefix)."
  (interactive "P")
  (pcase-let ((`(,id ,repo) (+gh-cli--run-at)))
    (when (y-or-n-p (format "Rerun %s jobs of run %s? " (if all "all" "the failed") id))
      (+gh-cli-async (append (list "run" "rerun" id "-R" repo) (unless all '("--failed")))))))

(defun +gh/run-cancel ()
  "Cancel the run at point."
  (interactive)
  (pcase-let ((`(,id ,repo) (+gh-cli--run-at)))
    (when (y-or-n-p (format "Cancel run %s? " id))
      (+gh-cli-async (list "run" "cancel" id "-R" repo)))))

(defun +gh/workflows (&optional place)
  "Workflows of this repository: RET runs one (workflow_dispatch)."
  (interactive)
  (let ((p (or place (+gh-browse--here) (+gh--remote-place (+gh--local-repo-dir)))))
    (+gh-list-show (format "*GitHub workflows: %s*" (+gh--repo-arg p))
                   [("Workflow" 36 t) ("State" 12 t) ("File" 0 nil)]
                   (mapcar (lambda (w) (list (list :workflow (plist-get w :id) :place p :name (plist-get w :name))
                                             (vector (plist-get w :name) (plist-get w :state) (or (plist-get w :path) ""))))
                           (+gh--json "workflow" "list" "-R" (+gh--repo-arg p) "--all" "--json" "id,name,state,path"))
                   p nil (list #'+gh/workflows p))))

(defun +gh/workflow-run ()
  "Run the workflow at point on a ref."
  (interactive)
  (let* ((id (+gh-list--id)) (repo (+gh--repo-arg (plist-get id :place)))
         (ref (read-string "On ref: " "main")))
    (when (y-or-n-p (format "Run %s on %s? " (plist-get id :name) ref))
      (+gh-cli-async (list "workflow" "run" (number-to-string (cadr id)) "-R" repo "--ref" ref)))))

(defun +gh/workflow-toggle ()
  "Enable or disable the workflow at point."
  (interactive)
  (let* ((id (+gh-list--id)) (repo (+gh--repo-arg (plist-get id :place)))
         (on (equal (aref (tabulated-list-get-entry) 1) "active")))
    (when (y-or-n-p (format "%s %s? " (if on "Disable" "Enable") (plist-get id :name)))
      (+gh-cli-async (list "workflow" (if on "disable" "enable") (number-to-string (cadr id)) "-R" repo))
      (+gh-cli--refresh-later))))

;;;; Code search

(defun +gh/grep (query scope)
  "Search code on GitHub for QUERY in SCOPE (this repository, an owner, all)."
  (interactive
   (let* ((here (ignore-errors (+gh-browse--place-at)))
          (q (read-string "Search code: " (thing-at-point 'symbol t)))
          (scope (completing-read "Where: " (delq nil (list (and here (+gh--repo-arg here))
                                                            (and here (concat "owner:" (+gh-place-owner here)))
                                                            "everywhere"))
                                  nil nil)))
     (list q scope)))
  (+gh-browse-note 'search :query (format "code: %s (%s)" query scope))
  (let* ((args (append (list "search" "code" query "-L" "100" "--json" "repository,path,textMatches")
                       (cond ((string-prefix-p "owner:" scope) (list "--owner" (substring scope 6)))
                             ((string-match-p "/" scope) (list "--repo" scope)))))
         (hits (apply #'+gh--json args)))
    (+gh-list-show (format "*GitHub code: %s (%s)*" query scope)
                   [("Repository" 30 t) ("File" 44 t) ("Match" 0 nil)]
                   (mapcar (lambda (h)
                             (let* ((repo (plist-get (plist-get h :repository) :nameWithOwner))
                                    (frag (plist-get (car (plist-get h :textMatches)) :fragment))
                                    (line (car (seq-filter (lambda (l) (string-match-p (regexp-quote query) l))
                                                           (split-string (or frag "") "\n")))))
                               (list (list :code (concat repo ":" (plist-get h :path)) :match (or line query))
                                     (vector repo (plist-get h :path) (string-trim (or line ""))))))
                           hits)
                   nil nil (list #'+gh/grep query scope))))

(defun +gh-cli-open-code ()
  "Open the file of the code hit at point, at the match."
  (let* ((id (+gh-list--id))
         (place (+gh-browse--parse (cadr id))))
    (+gh-browse-open place)
    (goto-char (point-min))
    (when (search-forward (plist-get id :match) nil t)
      (goto-char (match-beginning 0)) (recenter))))

;;;; Gists, repositories, releases, notifications

(defun +gh/gists ()
  "Your gists: RET reads one."
  (interactive)
  (+gh-list-show "*GitHub gists*" [("Description" 50 t) ("Files" 30 nil) ("Updated" 8 t) ("" 0 nil)]
                 (mapcar (lambda (g) (list (list :gist (plist-get g :id))
                                           (vector (or (plist-get g :description) "") (string-join (mapcar (lambda (f) (symbol-name (car f))) (seq-partition (plist-get g :files) 2)) " ")
                                                   (+gh--age (plist-get g :updated_at)) (if (plist-get g :public) "public" "secret"))))
                         (+gh--json "api" "gists?per_page=100"))
                 nil nil (list #'+gh/gists)))

(defun +gh-cli-open-gist (id)
  (let ((text (+gh--gh "gist" "view" id "--raw")))
    (with-current-buffer (get-buffer-create (format "*gist %s*" id))
      (let ((inhibit-read-only t)) (erase-buffer) (insert text))
      (if (fboundp 'gfm-view-mode) (funcall 'gfm-view-mode) (view-mode))
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

(defun +gh/fork ()
  "Fork this repository to your account, then browse the fork."
  (interactive)
  (let ((p (+gh-browse--here)))
    (when (y-or-n-p (format "Fork %s to your account? " (+gh--repo-arg p)))
      (+gh-cli-async (list "repo" "fork" (+gh--repo-arg p) "--clone=false")
                     (lambda (_) (message "Forked %s" (+gh--repo-arg p)))))))

(defun +gh/repo-create (name visibility)
  "Create repository NAME (VISIBILITY) from this local repository and push it."
  (interactive (list (read-string "Repository name: " (file-name-nondirectory (directory-file-name (+gh--local-repo-dir))))
                     (completing-read "Visibility: " '("private" "public" "internal") nil t nil nil "private")))
  (let ((default-directory (+gh--local-repo-dir)))
    (when (y-or-n-p (format "Create %s GitHub repository %s from %s and push? " visibility name default-directory))
      (+gh-cli-compile (list "repo" "create" name (concat "--" visibility) "--source" "." "--push")))))

(defun +gh/repo-edit (description topics)
  "Set this repository's DESCRIPTION and add TOPICS (comma separated)."
  (interactive
   (let* ((p (+gh-browse--here))
          (info (+gh--json "repo" "view" (+gh--repo-arg p) "--json" "description,repositoryTopics")))
     (list (read-string "Description: " (plist-get info :description))
           (read-string "Add topics (comma separated): "))))
  (let ((p (+gh-browse--here)))
    (+gh-cli-async (append (list "repo" "edit" (+gh--repo-arg p) "--description" description)
                           (unless (string-empty-p topics) (list "--add-topic" topics))))))

(defun +gh/template (kind)
  "Insert a .gitignore or license template (KIND) from GitHub at point."
  (interactive (list (completing-read "Template: " '("gitignore" "license") nil t)))
  (let* ((names (split-string (+gh--gh "repo" kind "list") "\n" t))
         (names (mapcar (lambda (l) (car (split-string (string-trim l)))) (seq-remove (lambda (l) (string-match-p "\\`[A-Z ]+\\'" l)) names)))
         (name (completing-read (format "%s: " kind) names nil t)))
    (insert (+gh--gh "repo" kind "view" name))))

(defun +gh-cli-release-notes ()
  "The notes of the release at point, rendered."
  (interactive)
  (let* ((id (+gh-list--id)) (p (plist-get id :place))
         (body (plist-get (+gh--json "release" "view" (cadr id) "-R" (+gh--repo-arg p) "--json" "body") :body)))
    (+gh-cli--render-markdown body (+gh--repo-arg p) (format "*GitHub release %s %s*" (+gh--repo-arg p) (cadr id)))))

(defun +gh-cli-release-download ()
  "Download an asset of the release at point to ~/Downloads."
  (interactive)
  (let* ((id (+gh-list--id)) (p (plist-get id :place))
         (assets (plist-get (+gh--json "release" "view" (cadr id) "-R" (+gh--repo-arg p) "--json" "assets") :assets))
         (name (completing-read "Asset: " (mapcar (lambda (a) (format "%s (%s)" (plist-get a :name) (file-size-human-readable (plist-get a :size))))
                                                 assets)
                                nil t)))
    (+gh-cli-async (list "release" "download" (cadr id) "-R" (+gh--repo-arg p) "-p" (car (split-string name " (")) "-D" (expand-file-name "~/Downloads"))
                   (lambda (_) (message "Downloaded to ~/Downloads")))))

(defun +gh/notifications-read-all ()
  "Mark all notifications read."
  (interactive)
  (when (y-or-n-p "Mark all GitHub notifications read? ")
    (+gh--gh "api" "-X" "PUT" "notifications")
    (message "All read")))

;;;; Rendering Markdown (local buffers too)

(defun +gh-cli--render-markdown (text context name &optional base)
  "TEXT rendered by GitHub (in repository CONTEXT) into buffer NAME."
  (let* ((input (make-temp-file "gh-md" nil ".json" (json-serialize (list :text text :mode "gfm" :context (or context "")))))
         (html (unwind-protect (+gh--gh "api" "markdown" "--input" input) (delete-file input)))
         (buf (get-buffer-create name)))
    (require 'shr)
    (with-current-buffer buf
      (let ((inhibit-read-only t) (pos (point)))
        (erase-buffer)
        (+gh-render-mode)
        (let ((dom (with-temp-buffer (insert html) (libxml-parse-html-region (point-min) (point-max) base)))
              (shr-inhibit-images (not (bound-and-true-p +gh-render-images))))
          (shr-insert-document dom))
        (goto-char (min pos (point-max)))))
    (display-buffer buf)
    buf))

(defun +gh/preview ()
  "This Markdown buffer as GitHub renders it, refreshed on each save."
  (interactive)
  (let* ((src (current-buffer))
         (repo (ignore-errors (+gh--repo-arg (+gh--remote-place (+gh--local-repo-dir)))))
         (name (format "*GitHub preview: %s*" (buffer-name)))
         (render (lambda () (+gh-cli--render-markdown (with-current-buffer src (buffer-string)) repo name))))
    (funcall render)
    (add-hook 'after-save-hook render nil t)
    (message "Preview refreshes when you save")))

;;;; Local branches: clean up what's merged or gone

(defun +gh/clean-branches ()
  "Delete local branches whose PR is merged or closed, or whose upstream
is gone, and that hold no commits you'd lose."
  (interactive)
  (let* ((dir (+gh--local-repo-dir))
         (default-directory dir)
         (current (string-trim (shell-command-to-string "git rev-parse --abbrev-ref HEAD")))
         (done (mapcar (lambda (pr) (plist-get pr :headRefName))
                       (ignore-errors (+gh--json "pr" "list" "--state" "all" "-L" "200" "--json" "headRefName,state"
                                                 "--jq" "[.[] | select(.state != \"OPEN\")]"))))
         (gone (cl-loop for l in (split-string (shell-command-to-string "git branch -vv") "\n" t)
                        when (string-match-p "\\[gone\\]" l)
                        collect (car (split-string (string-trim-left l "[* ]+") " "))))
         (candidates
          (cl-loop for b in (split-string (shell-command-to-string "git for-each-ref --format='%(refname:short)' refs/heads") "\n" t)
                   unless (member b (list current "main" "master"))
                   when (or (member b done) (member b gone))
                   ;; Safe: everything on it is in some remote branch or merged into HEAD.
                   when (string-empty-p (string-trim (shell-command-to-string
                                                       (format "git log --oneline %s --not --remotes HEAD 2>/dev/null"
                                                               (shell-quote-argument b)))))
                   collect b)))
    (if (null candidates)
        (message "Nothing to clean in %s" (abbreviate-file-name dir))
      (when (y-or-n-p (format "Delete %d merged/gone branch(es): %s? " (length candidates) (string-join candidates ", ")))
        (dolist (b candidates) (call-process "git" nil nil nil "branch" "-D" b))
        (message "Deleted %s" (string-join candidates ", "))))))

;;;; API scratch

(defun +gh/api (endpoint &optional method)
  "Call ENDPOINT (REST path, or \"graphql\") with METHOD; show the JSON."
  (interactive (list (read-string "API endpoint (e.g. repos/OWNER/REPO, user, graphql): ")
                     (if current-prefix-arg (completing-read "Method: " '("GET" "POST" "PATCH" "PUT" "DELETE") nil t) "GET")))
  (let* ((args (if (equal endpoint "graphql")
                   (list "api" "graphql" "-f" (concat "query=" (read-string "GraphQL: " "{ viewer { login } }")))
                 (list "api" "-X" (or method "GET") endpoint)))
         (out (apply #'+gh--gh args)))
    (with-current-buffer (get-buffer-create (format "*GitHub API: %s*" endpoint))
      (let ((inhibit-read-only t)) (erase-buffer) (insert out))
      (if (fboundp 'json-ts-mode) (ignore-errors (json-ts-mode)) (js-json-mode))
      (ignore-errors (json-pretty-print-buffer))
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

;;;; Lists: what RET and . do on the new rows

(defun +gh-cli-open-a (fn)
  "Around `+gh-list-open' (FN): open runs, workflows, code hits and gists too."
  (let ((id (ignore-errors (+gh-list--id))))
    (pcase (car-safe id)
      (:run (call-interactively #'+gh/run-log))
      (:workflow (call-interactively #'+gh/workflow-run))
      (:code (+gh-cli-open-code))
      (:gist (+gh-cli-open-gist (cadr id)))
      (_ (funcall fn)))))

(defun +gh/act ()
  "What can be done with the row or page at point."
  (interactive)
  (pcase (car-safe (ignore-errors (+gh-list--id)))
    (:run (+gh-run-menu))
    (:workflow (+gh-workflow-menu))
    (:ref (+gh-release-menu))
    (_ (+gh-topic-menu))))

(transient-define-prefix +gh-run-menu ()
  "This Actions run."
  ["Run"
   ("l" "Log of failed steps (C-u: all)" +gh/run-log)
   ("w" "Watch live" +gh/run-watch)
   ("r" "Rerun failed jobs (C-u: all)" +gh/run-rerun)
   ("x" "Cancel" +gh/run-cancel)])

(transient-define-prefix +gh-workflow-menu ()
  "This workflow."
  ["Workflow"
   ("r" "Run on a ref" +gh/workflow-run)
   ("t" "Enable / disable" +gh/workflow-toggle)])

(transient-define-prefix +gh-release-menu ()
  "This release."
  ["Release"
   ("v" "Notes, rendered" +gh-cli-release-notes)
   ("d" "Download an asset" +gh-cli-release-download)])

(with-eval-after-load '+gh-browse
  (advice-add '+gh-list-open :around #'+gh-cli-open-a))

(defvar +gh-list-mode-map)
(with-eval-after-load '+gh-browse
  (define-key +gh-list-mode-map (kbd ".") #'+gh/act))

;;;; In the GitHub menu

(with-eval-after-load '+gh-browse
  (transient-append-suffix '+gh-menu '(0 0 -1)
    '("x" "Any gh command…" +gh/run))
  (transient-append-suffix '+gh-menu '(0 0 -1)
    '("g" "Grep code on GitHub" +gh/grep))
  (transient-append-suffix '+gh-menu '(0 0 -1)
    '("A" "API request" +gh/api))
  (transient-append-suffix '+gh-menu '(0 0 -1)
    '("N" "Notifications: all read" +gh/notifications-read-all))
  (transient-append-suffix '+gh-menu '(0 1 -1)
    '("I" "New issue" +gh/issue-create))
  (transient-append-suffix '+gh-menu '(0 1 -1)
    '("!" "Actions runs" +gh/runs))
  (transient-append-suffix '+gh-menu '(0 2 -1)
    '("W" "Workflows" +gh/workflows))
  (transient-append-suffix '+gh-menu '(0 2 -1)
    '("F" "Fork" +gh/fork))
  (transient-append-suffix '+gh-menu '(0 2 -1)
    '("E" "Edit description, topics" +gh/repo-edit))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("P" "New pull request (this branch)" +gh/pr-create))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("!" "Actions runs" +gh/runs))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("k" "Gist of region/buffer (C-u public)" +gh/gist-create))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("K" "Your gists" +gh/gists))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("m" "Markdown preview, as GitHub" +gh/preview))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("D" "Clean merged/gone branches" +gh/clean-branches))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("C" "Create repository from here" +gh/repo-create))
  (transient-append-suffix '+gh-menu '(0 3 -1)
    '("T" "Insert .gitignore / license" +gh/template)))

(provide '+gh-cli)
;;; +gh-cli.el ends here
