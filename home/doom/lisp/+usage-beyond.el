;;; lisp/+usage-beyond.el --- What you do outside Emacs, for suggestions -*- lexical-binding: t; -*-
;;
;; +usage counts what you do in Emacs.  This reads what you do around it,
;; from what already records it, and records what nothing did (Hyprland):
;;
;;   shell     Atuin's history (read only): programs, repeated long
;;             commands, what fails, directories, nix and git
;;   desktop   Hyprland: which window has focus, for how long, which
;;             switches you repeat, workspace changes; recorded here from
;;             Hyprland's event socket while +usage-mode is on
;;   browser   Firefox's history: visits per site (domains only, never
;;             addresses or titles)
;;   AI        your prompts: to Claude Code (its transcripts in
;;             ~/.claude), Codex (~/.codex) and familiar (Emacs): how many,
;;             where, how they start, the ones you repeat
;;   tmux      its sessions and windows, when it runs
;;
;;   M-x +usage/beyond               the report, per category
;;   M-x +usage/suggest-everywhere   suggestions per category, and
;;                                   workflows across tools
;;   +usage/suggest and +usage/tip   see the same summary
;;
;; Read on demand, local.  Only what a report or a suggestion shows leaves
;; Emacs, and only when you ask the model (the summary, not the data).
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar +usage-mode)
(defvar +usage-evidence-functions)
(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin model))

(defvar +usage-beyond-days 30 "Days read back.")

(defvar +usage-beyond-sources '(shell desktop browser ai tmux)
  "Categories read; drop one to leave it out of reports and suggestions.")

(defun +usage-beyond--since ()
  (- (float-time) (* 86400 +usage-beyond-days)))

(defun +usage-beyond--top (table n)
  "The N largest entries of hash TABLE: ((KEY . COUNT) …)."
  (let (rows)
    (maphash (lambda (k v) (push (cons k v) rows)) table)
    (seq-take (sort rows (lambda (a b) (> (cdr a) (cdr b)))) n)))

;;;; Shell: Atuin

(defvar +usage-beyond-atuin-db (expand-file-name "~/.local/share/atuin/history.db"))

(defun +usage-beyond--atuin-rows ()
  "Atuin's commands of the last `+usage-beyond-days' days.
Each is (COMMAND EXIT SECONDS CWD TIME)."
  (when (and (file-readable-p +usage-beyond-atuin-db) (sqlite-available-p))
    (let ((db (sqlite-open +usage-beyond-atuin-db)))
      (unwind-protect
          (sqlite-select db "SELECT command, exit, duration / 1e9, cwd, timestamp / 1e9 FROM history
                             WHERE deleted_at IS NULL AND timestamp > ? ORDER BY timestamp"
                         (list (* (+usage-beyond--since) 1e9)))
        (sqlite-close db)))))

(defun +usage-beyond--program (command)
  "The program COMMAND runs (after sudo, env assignments, command)."
  (let ((words (split-string command)))
    (while (and words (or (member (car words) '("sudo" "command" "time" "nohup" "exec"))
                          (string-match-p "\\`[A-Z_]+=" (car words))))
      (pop words))
    (and words (file-name-nondirectory (car words)))))

(defun +usage-beyond--command-key (command)
  "COMMAND as counted: home as ~, `\\#' as `#', runs of space as one.
So \"/home/me/bin/x  sync\" and \"~/bin/x sync\" count as one command."
  (let ((home (regexp-quote (directory-file-name (expand-file-name "~")))))
    (string-trim
     (replace-regexp-in-string
      "[ \t\n]+" " "
      (string-replace "\\#" "#"
                      (replace-regexp-in-string
                       (concat "\\(?:\\`\\|[ =:]\\)\\(" home "\\)\\(?:/\\| \\|\\'\\)")
                       "~" command nil nil 1))))))

(defun +usage-beyond-shell (&optional rows)
  "The shell summary (Org), from ROWS (default: Atuin's)."
  (when-let* ((rows (or rows (+usage-beyond--atuin-rows))))
    (let ((programs (make-hash-table :test #'equal))
          (fails (make-hash-table :test #'equal))
          (failed (make-hash-table :test #'equal))
          (long (make-hash-table :test #'equal))
          (dirs (make-hash-table :test #'equal))
          (git (make-hash-table :test #'equal))
          (nix (make-hash-table :test #'equal))
          (nix-time 0.0) (cds 0)
          (days (max 1 (/ (- (float-time) (nth 4 (car rows))) 86400.0))))
      (pcase-dolist (`(,cmd ,exit ,secs ,cwd ,_) rows)
        (let ((prog (+usage-beyond--program cmd))
              (key (+usage-beyond--command-key cmd)))
          (when prog
            ;; Leaving a shell isn't using a program.
            (unless (member prog '("exit" "logout"))
              (cl-incf (gethash prog programs 0)))
            ;; 130: C-c.  A session (ssh, a shell, an editor) ends with the status of
            ;; whatever ran last in it: not a failure of its own.
            (when (and (integerp exit) (/= exit 0) (/= exit 130)
                       (not (member prog '("exit" "logout" "ssh" "mosh" "tmux" "emacs" "nvim" "vim" "zsh" "bash" "claude")))
                       (not (string-match-p "\\`nix \\(?:develop\\|shell\\|run\\)" cmd)))
              (cl-incf (gethash prog fails 0))
              (cl-incf (gethash key failed 0)))
            (when (>= (length key) 25) (cl-incf (gethash key long 0)))
            (cl-incf (gethash (abbreviate-file-name (or cwd "?")) dirs 0))
            (when (member prog '("cd" "z" "zi")) (cl-incf cds))
            (when (equal prog "git")
              (cl-incf (gethash (or (cadr (split-string cmd)) "") git 0)))
            (when (member prog '("nix" "nrs" "nrsi" "nixos-rebuild" "home-manager" "nix-shell" "nix-build"))
              (let ((sub (string-join (seq-take (split-string cmd) (if (equal prog "nix") 2 1)) " ")))
                (cl-incf (gethash sub nix 0))
                ;; Waiting: builds and switches, not the shells nix opens.
                (unless (string-match-p "\\`nix \\(?:develop\\|shell\\|run\\)" cmd)
                  (cl-incf nix-time (max 0 (or secs 0)))))))))
      (concat
       (format "* Shell (Atuin, %d commands in %d days, %.0f a day)\n" (length rows) (round days)
               (/ (length rows) days))
       "Programs, most used (failures: exit ≠ 0, not C-c):\n"
       (mapconcat (lambda (p) (format "- %s ×%d%s" (car p) (cdr p)
                                      (let ((f (gethash (car p) fails 0)))
                                        (if (> f 0) (format ", failed ×%d (%d%%)" f (/ (* 100 f) (cdr p))) ""))))
                  (+usage-beyond--top programs 15) "\n")
       "\nLong commands typed again and again (alias or script candidates):\n"
       (mapconcat (lambda (c) (format "- ×%d  %s" (cdr c) (truncate-string-to-width (car c) 110 nil nil "…")))
                  (seq-filter (lambda (c) (>= (cdr c) 3)) (+usage-beyond--top long 10)) "\n")
       "\nCommands that failed most:\n"
       (mapconcat (lambda (c) (format "- ×%d  %s" (cdr c) (truncate-string-to-width (car c) 110 nil nil "…")))
                  (+usage-beyond--top failed 8) "\n")
       (format "\nDirectories worked in most (cd/z ×%d):\n" cds)
       (mapconcat (lambda (d) (format "- %s ×%d" (car d) (cdr d))) (+usage-beyond--top dirs 8) "\n")
       "\ngit: " (mapconcat (lambda (g) (format "%s ×%d" (car g) (cdr g))) (+usage-beyond--top git 10) ", ")
       (format "\nnix (%.0f min waited for builds and switches): " (/ nix-time 60))
       (mapconcat (lambda (n) (format "%s ×%d" (car n) (cdr n))) (+usage-beyond--top nix 8) ", ")
       "\n"))))

;;;; Desktop: Hyprland's events, recorded

(defvar +usage-beyond-desktop-directory (locate-user-emacs-file "usage-desktop/")
  "Where the desktop is recorded, one file a day.")

(defvar +usage-beyond--desktop (list :focus nil :time nil :switch nil :workspace 0 :back 0)
  "Today's desktop counts not yet saved (alists, merged into the day's file).")
(defvar +usage-beyond--current nil "The focused window's class, and since when: (CLASS . TIME).")
(defvar +usage-beyond--previous nil "The class before it, and when it lost focus: (CLASS . TIME).")
(defvar +usage-beyond--hypr nil "The connection to Hyprland's event socket.")
(defvar +usage-beyond--partial "" "An event line not complete yet.")

(defun +usage-beyond--bump (key item n)
  (let ((alist (plist-get +usage-beyond--desktop key)))
    (setf (alist-get item alist 0 nil #'equal) (+ n (alist-get item alist 0 nil #'equal)))
    (setq +usage-beyond--desktop (plist-put +usage-beyond--desktop key alist))))

(defun +usage-beyond-desktop-event (line &optional now)
  "Count Hyprland event LINE (at NOW)."
  (let ((now (or now (float-time))))
    (cond
     ((string-match "\\`activewindow>>\\([^,]*\\)," line)
      (let ((class (match-string 1 line)))
        (unless (or (string-empty-p class) (equal class (car +usage-beyond--current)))
          (when-let* ((cur +usage-beyond--current))
            (+usage-beyond--bump :time (car cur) (- now (cdr cur)))
            (+usage-beyond--bump :switch (cons (car cur) class) 1)
            ;; Back within 10 s to where you were: a glance, often a lookup.
            (when (and +usage-beyond--previous (equal (car +usage-beyond--previous) class)
                       (< (- now (cdr cur)) 10))
              (setq +usage-beyond--desktop
                    (plist-put +usage-beyond--desktop :back (1+ (plist-get +usage-beyond--desktop :back)))))
            (setq +usage-beyond--previous (cons (car cur) now)))
          (+usage-beyond--bump :focus class 1)
          (setq +usage-beyond--current (cons class now)))))
     ((string-match-p "\\`workspace>>" line)
      (setq +usage-beyond--desktop
            (plist-put +usage-beyond--desktop :workspace (1+ (plist-get +usage-beyond--desktop :workspace))))))))

(defun +usage-beyond--hypr-filter (_proc text)
  (let ((lines (split-string (concat +usage-beyond--partial text) "\n")))
    (setq +usage-beyond--partial (car (last lines)))
    (mapc #'+usage-beyond-desktop-event (butlast lines))))

(defun +usage-beyond--merge (a b)
  "Desktop counts A and B added up."
  (let ((out (copy-sequence a)))
    (dolist (key '(:focus :time :switch))
      (let ((alist (copy-alist (plist-get out key))))
        (pcase-dolist (`(,k . ,v) (plist-get b key))
          (setf (alist-get k alist 0 nil #'equal) (+ v (alist-get k alist 0 nil #'equal))))
        (setq out (plist-put out key alist))))
    (dolist (key '(:workspace :back))
      (setq out (plist-put out key (+ (or (plist-get out key) 0) (or (plist-get b key) 0)))))
    out))

(defun +usage-beyond--desktop-read (file)
  (when (file-readable-p file)
    (with-temp-buffer (insert-file-contents file) (ignore-errors (read (current-buffer))))))

(defun +usage-beyond-desktop-save ()
  "Add the counts not saved yet to today's file."
  (when (or (plist-get +usage-beyond--desktop :focus) (> (plist-get +usage-beyond--desktop :workspace) 0))
    (make-directory +usage-beyond-desktop-directory t)
    (let ((file (expand-file-name (format-time-string "%F.eld") +usage-beyond-desktop-directory))
          (print-length nil) (print-level nil))
      (let ((merged (+usage-beyond--merge (or (+usage-beyond--desktop-read file)
                                              (list :focus nil :time nil :switch nil :workspace 0 :back 0))
                                          +usage-beyond--desktop)))
        (with-temp-file file (prin1 merged (current-buffer))))
      (setq +usage-beyond--desktop (list :focus nil :time nil :switch nil :workspace 0 :back 0)))))

(defun +usage-beyond--hypr-socket ()
  (when-let* ((sig (getenv "HYPRLAND_INSTANCE_SIGNATURE")))
    (let ((path (expand-file-name (format "hypr/%s/.socket2.sock" sig)
                                  (or (getenv "XDG_RUNTIME_DIR") (format "/run/user/%d" (user-uid))))))
      (and (file-exists-p path) path))))

(defvar +usage-beyond--timer nil)

(defun +usage-beyond-desktop-start ()
  "Record Hyprland's focus and workspace events."
  (when-let* (((not (process-live-p +usage-beyond--hypr)))
              (socket (+usage-beyond--hypr-socket)))
    (setq +usage-beyond--hypr
          (make-network-process :name "+usage-hyprland" :family 'local :service socket
                                :noquery t :coding 'utf-8 :filter #'+usage-beyond--hypr-filter))
    (unless +usage-beyond--timer
      (setq +usage-beyond--timer (run-with-idle-timer 300 t #'+usage-beyond-desktop-save)))
    (add-hook 'kill-emacs-hook #'+usage-beyond-desktop-save)))

(defun +usage-beyond-desktop-stop ()
  (when (process-live-p +usage-beyond--hypr) (delete-process +usage-beyond--hypr))
  (when +usage-beyond--timer (cancel-timer +usage-beyond--timer) (setq +usage-beyond--timer nil))
  (+usage-beyond-desktop-save))

(defun +usage-beyond--desktop-setup-h ()
  ;; The main daemon only: a second Emacs would count every event twice.
  (if (and (bound-and-true-p +usage-mode) (eq (daemonp) t))
      (ignore-errors (+usage-beyond-desktop-start))
    (+usage-beyond-desktop-stop)))
(add-hook '+usage-mode-hook #'+usage-beyond--desktop-setup-h)
(when (bound-and-true-p +usage-mode) (+usage-beyond--desktop-setup-h))

(defun +usage-beyond-desktop ()
  "The desktop summary (Org), from the recorded days."
  (let ((total (list :focus nil :time nil :switch nil :workspace 0 :back 0)) (days 0))
    (dotimes (i +usage-beyond-days)
      (when-let* ((d (+usage-beyond--desktop-read
                      (expand-file-name (format-time-string "%F.eld" (time-subtract nil (* 86400 i)))
                                        +usage-beyond-desktop-directory))))
        (cl-incf days)
        (setq total (+usage-beyond--merge total d))))
    (setq total (+usage-beyond--merge total +usage-beyond--desktop))
    (when (plist-get total :focus)
      (let ((time (make-hash-table :test #'equal)) (switch (make-hash-table :test #'equal)))
        (pcase-dolist (`(,k . ,v) (plist-get total :time)) (puthash k v time))
        (pcase-dolist (`(,k . ,v) (plist-get total :switch)) (puthash k v switch))
        (concat
         (format "* Desktop (Hyprland, %d day%s recorded)\n" (max 1 days) (if (> days 1) "s" ""))
         "Time with focus:\n"
         (mapconcat (lambda (c) (format "- %s %s" (car c) (+usage-beyond--duration (cdr c))))
                    (+usage-beyond--top time 8) "\n")
         "\nSwitches you repeat (from → to):\n"
         (mapconcat (lambda (s) (format "- %s → %s ×%d" (caar s) (cdar s) (cdr s)))
                    (+usage-beyond--top switch 8) "\n")
         (format "\nWorkspace changes: %d.  Back within 10 s to the window before (a glance): ×%d\n"
                 (plist-get total :workspace) (plist-get total :back)))))))

(defun +usage-beyond--duration (secs)
  (cond ((< secs 120) (format "%ds" (round secs)))
        ((< secs 7200) (format "%dmin" (round secs 60)))
        (t (format "%.1fh" (/ secs 3600.0)))))

;;;; Browser: Firefox, sites only

(defun +usage-beyond--firefox-db ()
  "The most recently used Firefox profile's places.sqlite."
  (car (sort (file-expand-wildcards (expand-file-name "~/.mozilla/firefox/*/places.sqlite"))
             (lambda (a b) (time-less-p (file-attribute-modification-time (file-attributes b))
                                        (file-attribute-modification-time (file-attributes a)))))))

(defun +usage-beyond--firefox-hosts ()
  "Visits per site since `+usage-beyond-days' ago: ((HOST . VISITS) …).
Firefox locks its database while it runs: a copy is read."
  (when-let* ((db (+usage-beyond--firefox-db))
              ((sqlite-available-p)))
    (let ((dir (make-temp-file "places" t)))
      (unwind-protect
          (progn
            (copy-file db (expand-file-name "places.sqlite" dir))
            (when (file-exists-p (concat db "-wal"))
              (copy-file (concat db "-wal") (expand-file-name "places.sqlite-wal" dir)))
            (let ((h (sqlite-open (expand-file-name "places.sqlite" dir))))
              (unwind-protect
                  (mapcar (lambda (r) (cons (car r) (cadr r)))
                          (sqlite-select h "SELECT p.rev_host, count(*) n FROM moz_historyvisits v
                                            JOIN moz_places p ON p.id = v.place_id
                                            WHERE v.visit_date > ? AND p.rev_host IS NOT NULL
                                            GROUP BY p.rev_host ORDER BY n DESC LIMIT 25"
                                         (list (* (+usage-beyond--since) 1e6))))
                (sqlite-close h))))
        (delete-directory dir t)))))

(defun +usage-beyond-browser (&optional hosts)
  "The browser summary (Org), from HOSTS (default: Firefox's)."
  (when-let* ((hosts (or hosts (+usage-beyond--firefox-hosts))))
    (concat (format "* Browser (Firefox, last %d days; sites only)\n" +usage-beyond-days)
            (mapconcat (lambda (h)
                         ;; rev_host is the host reversed with a trailing dot: "gro.sexin."
                         (format "- %s ×%d" (string-remove-prefix "www." (string-trim (reverse (car h)) "\\." "\\."))
                                 (cdr h)))
                       (seq-take (seq-remove (lambda (h) (member (car h) '("." ""))) hosts) 15)
                       "\n")
            "\n")))

;;;; AI prompts

(defvar +usage-beyond--prompt-cache (make-hash-table :test #'equal)
  "Transcript file → (MTIME . PROMPTS), PROMPTS a list of (TIME PROJECT TEXT).")

(defconst +usage-beyond--jq
  (concat "select(.type==\"user\" and (.isMeta|not) and (.isCompactSummary|not)) "
          "| [.timestamp, (.cwd // \"\"), (if (.message.content|type)==\"string\" then .message.content "
          "else ([.message.content[]? | select(.type==\"text\") | .text] | join(\" \")) end)] | @json")
  "The user's own prompts in a Claude Code transcript line.")

(defconst +usage-beyond--jq-codex
  (concat "select(.type==\"response_item\" and .payload.role==\"user\") "
          "| [.timestamp, \"codex\", ([.payload.content[]? | select(.type==\"input_text\") | .text] | join(\" \"))] | @json")
  "The user's own prompts in a Codex transcript line.")

(defun +usage-beyond--prompt-p (text)
  "Non-nil when TEXT is something typed, not a harness message."
  (and (stringp text) (not (string-empty-p (string-trim text)))
       (not (string-match-p "\\`[ \n]*\\(?:<\\|Stop hook feedback\\|\\[Request interrupted\\|Caveat:\\|A session-scoped Stop hook\\|This session is being continued\\|[Uu]nknown skill:\\)" text))))

(defun +usage-beyond--file-prompts (file &optional codex)
  "The prompts in transcript FILE (CODEX: a Codex one).
Cached while the file doesn't change."
  (let ((mtime (file-attribute-modification-time (file-attributes file)))
        (hit (gethash file +usage-beyond--prompt-cache)))
    (if (and hit (equal (car hit) mtime)) (cdr hit)
      (let (prompts)
        (with-temp-buffer
          (when (eql 0 (call-process "jq" nil t nil "-r" (if codex +usage-beyond--jq-codex +usage-beyond--jq) file))
            (goto-char (point-min))
            (while (not (eobp))
              (when-let* ((row (ignore-errors (json-parse-string (buffer-substring (point) (line-end-position))
                                                                 :array-type 'list))))
                (when (+usage-beyond--prompt-p (nth 2 row))
                  (push (list (nth 0 row) (file-name-nondirectory (directory-file-name (nth 1 row)))
                              (truncate-string-to-width (string-trim (nth 2 row)) 300))
                        prompts)))
              (forward-line 1))))
        (setq prompts (nreverse prompts))
        (puthash file (cons mtime prompts) +usage-beyond--prompt-cache)
        prompts))))

(defun +usage-beyond--agent-prompts ()
  "Prompts to Claude Code and Codex in the last `+usage-beyond-days' days:
\(TOOL TIME PROJECT TEXT)."
  (when (executable-find "jq")
    (let ((since (+usage-beyond--since)) out)
      (dolist (spec '((claude . "~/.claude/projects/*/*.jsonl") (codex . "~/.codex/sessions/*/*/*/*.jsonl")))
        (dolist (file (file-expand-wildcards (expand-file-name (cdr spec))))
          (when (> (float-time (file-attribute-modification-time (file-attributes file))) since)
            (dolist (p (+usage-beyond--file-prompts file (eq (car spec) 'codex)))
              (push (cons (car spec) p) out)))))
      out)))

(defvar familiar-history-directory)

(defun +usage-beyond--familiar-count ()
  "Turns in familiar's history (Emacs) this month and last: ((TASK . N) …)."
  (when (and (boundp 'familiar-history-directory) (stringp familiar-history-directory)
             (file-directory-p familiar-history-directory))
    (let ((tasks (make-hash-table :test #'equal)))
      (dolist (file (seq-take (reverse (directory-files familiar-history-directory t "\\.org\\'")) 2))
        (with-temp-buffer
          (insert-file-contents file)
          (while (re-search-forward "^:TASK: +\\(.+\\)$" nil t)
            (cl-incf (gethash (match-string 1) tasks 0)))))
      (+usage-beyond--top tasks 10))))

(defun +usage-beyond-ai (&optional prompts)
  "The AI summary (Org), from PROMPTS (default: the transcripts')."
  (let ((prompts (or prompts (+usage-beyond--agent-prompts)))
        (familiar (+usage-beyond--familiar-count)))
    (when (or prompts familiar)
      (let ((projects (make-hash-table :test #'equal))
            (openers (make-hash-table :test #'equal))
            (same (make-hash-table :test #'equal))
            (tools (make-hash-table :test #'equal))
            (total-len 0))
        (pcase-dolist (`(,tool ,_ ,project ,text) prompts)
          (cl-incf (gethash (symbol-name tool) tools 0))
          (cl-incf (gethash project projects 0))
          (cl-incf total-len (length text))
          (let ((words (split-string (downcase text) "[^[:alnum:]'-]+" t)))
            (when words (cl-incf (gethash (string-join (seq-take words 2) " ") openers 0))))
          (cl-incf (gethash (truncate-string-to-width
                             (replace-regexp-in-string "[ \t\n]+" " " (downcase (string-trim text))) 70)
                            same 0)))
        (concat
         (format "* AI prompts (last %d days)\n" +usage-beyond-days)
         (if prompts
             (concat
              (format "To coding agents: %s; %d characters on average.\n"
                      (mapconcat (lambda (tl) (format "%s ×%d" (car tl) (cdr tl))) (+usage-beyond--top tools 3) ", ")
                      (/ total-len (max 1 (length prompts))))
              "Per project: " (mapconcat (lambda (p) (format "%s ×%d" (car p) (cdr p))) (+usage-beyond--top projects 8) ", ")
              "\nHow they start: " (mapconcat (lambda (o) (format "\"%s\" ×%d" (car o) (cdr o)))
                                             (+usage-beyond--top openers 10) ", ")
              "\nTyped more than once (a command or skill candidate):\n"
              (mapconcat (lambda (s) (format "- ×%d  %s" (cdr s) (car s)))
                         (seq-filter (lambda (s) (>= (cdr s) 2)) (+usage-beyond--top same 10)) "\n")
              "\n")
           "")
         (if familiar
             (concat "In Emacs (familiar, this month and last): "
                     (mapconcat (lambda (f) (format "%s ×%d" (car f) (cdr f))) familiar ", ") "\n")
           ""))))))

;;;; tmux

(defun +usage-beyond-tmux ()
  "tmux's sessions and windows, when it runs (it keeps no history)."
  (when (executable-find "tmux")
    (with-temp-buffer
      (when (eql 0 (call-process "tmux" nil t nil "list-windows" "-a" "-F" "#{session_name}\t#{window_name}\t#{pane_current_command}"))
        (let ((lines (split-string (buffer-string) "\n" t)))
          (concat (format "* tmux (now: %d windows)\n" (length lines))
                  (mapconcat (lambda (l) (concat "- " (string-replace "\t" " · " l))) lines "\n")
                  "\n"))))))

;;;; Reports

(defun +usage-beyond-summary ()
  "Everything outside Emacs, one Org section per category that has data."
  (mapconcat #'identity
             (delq nil (mapcar (lambda (src)
                                 (when (memq src +usage-beyond-sources)
                                   (condition-case err
                                       (funcall (intern (format "+usage-beyond-%s" src)))
                                     (error (format "* %s: not read (%s)\n" src (error-message-string err))))))
                               '(shell desktop browser ai tmux)))
             "\n"))

(defun +usage/beyond ()
  "What you do outside Emacs: shell, desktop, browser, AI prompts, tmux."
  (interactive)
  (message "Reading the shell, desktop, browser and AI histories…")
  (let ((text (+usage-beyond-summary)))
    (with-current-buffer (get-buffer-create "*usage beyond Emacs*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "#+title: What you do outside Emacs\n\n"
                "M-x +usage/suggest-everywhere asks for suggestions from this (the summary goes to the model).\n\n"
                text))
      (org-mode)
      (read-only-mode 1)
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))
    (message nil)))

(defun +usage/suggest-everywhere ()
  "Suggestions per category (shell, desktop, browser, AI, Emacs), then
workflows across tools: do X in tool Y, with Z's integration, to skip W."
  (interactive)
  (unless (fboundp 'familiar-ask) (user-error "familiar-ask isn't available"))
  (familiar-ask
   (concat "Here is how I work, from local records: my Emacs use and, outside Emacs, my shell (Atuin), "
           "desktop (Hyprland), browser (sites only), AI prompts and tmux.  For each category, the two or "
           "three changes with the most effect, concrete (the alias, key, bind, script, setting, with what "
           "it saves by the counts).  Then up to three workflows across tools: \"do X in tool Y with Z's "
           "integration, to skip W\" (I use Doom Emacs, zsh with Atuin, kitty, Hyprland, Firefox, Claude "
           "Code, NixOS with flakes).  Only what the data supports.\n\n"
           (let ((+usage-evidence-functions (remq #'+usage-beyond--evidence +usage-evidence-functions)))
             (if (fboundp '+usage-evidence) (+usage-evidence) ""))
           "\n\n" (+usage-beyond-summary))
   t))

(defvar +usage-beyond--summary-cache nil "(TIME . SUMMARY), for the suggestions.")

(defun +usage-beyond--evidence ()
  "For +usage/suggest and +usage/tip: the summary of what happens outside Emacs.
Reused for ten minutes: reading the transcripts the first time takes seconds."
  (let ((s (if (and +usage-beyond--summary-cache
                    (< (- (float-time) (car +usage-beyond--summary-cache)) 600))
               (cdr +usage-beyond--summary-cache)
             (cdr (setq +usage-beyond--summary-cache
                        (cons (float-time) (+usage-beyond-summary)))))))
    (unless (string-empty-p s) (concat "Outside Emacs:\n\n" s))))

(with-eval-after-load '+usage
  (add-to-list '+usage-evidence-functions #'+usage-beyond--evidence t))
(when (boundp '+usage-evidence-functions)
  (add-to-list '+usage-evidence-functions #'+usage-beyond--evidence t))

(provide '+usage-beyond)
;;; +usage-beyond.el ends here
