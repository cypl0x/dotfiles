;;; lisp/+atuin-ai.el --- Atuin AI from Emacs: ask, then run it here, in a terminal or in the background -*- lexical-binding: t; -*-
;;
;; Atuin's AI is the box `?' opens at an empty zsh prompt: describe what
;; you want, Enter runs the command it suggests, Tab puts it on the prompt.
;; The same box, from anywhere in Emacs:
;;
;;   SPC !        ask (the region, if active, is sent as the question)
;;   SPC u SPC !  ask; a command runs the other way (see below)
;;   SPC o !      the menu: ask, ask in the background, a question typed
;;                first, which way commands run
;;   ?            at an empty prompt of M-!, M-&, compile, eshell and
;;                shell, as in zsh (in a terminal zsh's own `?' is there)
;;
;; It is Atuin's own box (`atuin ai inline --hook', your Atuin Hub login and
;; model, its tools and sessions) in a terminal below; what you chose in it
;; comes back to Emacs:
;;
;;   Enter (run)    in a shell buffer: run there, as zsh does.  From a
;;                  shell-command prompt: run as that command.  Elsewhere:
;;                    terminal    a fresh terminal runs it, and stays a shell
;;                    background  it runs out of sight (compile, so it is
;;                                in Atuin's history too); when it ends the
;;                                echo area says how and its last line, a
;;                                desktop notification too if Emacs isn't
;;                                focused; its buffer keeps all the output
;;   Tab (insert)   onto the shell's prompt or into the shell-command
;;                  prompt; elsewhere M-!-style, to edit before it runs
;;   an answer      the echo area, or a buffer when it is long
;;
;; Commands it runs from Emacs are recorded in Atuin's history (+atuin.el).
;; Asked from a remote (TRAMP) directory, the box runs here (Atuin is
;; here), the command there.
;;
;; Atuin AI rates each command it suggests (low, medium, high risk); that
;; rating, read from its own record of the conversation, is asked about
;; before a high-risk command runs in the background, where you wouldn't
;; watch it (`+atuin-ai-confirm'): there, in a terminal, or not at all.
;; A background command that failed: SPC o ! w asks Atuin AI why, with
;; the command, how it ended and its last output as the question.  Tab in
;; Org or Markdown puts the command in as a shell block.
;; Every box turn goes into familiar's history (SPC A j), tagged atuin_hub.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ansi-color)

(declare-function ghostel-exec "ext:ghostel" (buffer program &optional args identity))
(declare-function ghostel-send-string "ext:ghostel" (string))
(declare-function ghostel "ext:ghostel" (&optional arg))
(declare-function vterm-send-return "ext:vterm" ())
(declare-function eat-term-send-string "ext:eat" (terminal string))
(declare-function eshell-send-input "esh-mode" (&optional use-region queue-p no-newline))
(declare-function comint-send-input "comint" (&optional no-newline artificial))
(declare-function notifications-notify "notifications" (&rest params))
(declare-function +atuin--insert-in-shell "+atuin" (command))
(defvar eat-terminal)
(defvar ghostel-buffer-name)
(defvar ghostel-exit-functions)
(defvar eshell-last-output-end)
(defvar compilation-save-buffers-predicate)

(defgroup +atuin-ai nil "Atuin AI from Emacs." :group 'external)

(defcustom +atuin-ai-run 'terminal
  "How a command you run from Atuin AI's box runs, outside shell buffers
and prompts: `terminal' (a fresh terminal, which stays a shell) or
`background' (out of sight; you hear back when it ends).
\\[universal-argument] before asking picks the other one."
  :type '(choice (const terminal) (const background)))

(defcustom +atuin-ai-answer-lines 2
  "Answers longer than this many lines go to a buffer, not the echo area."
  :type 'natnum)

(defconst +atuin-ai-buffer "*Atuin AI*")
(defvar-local +atuin-ai--command nil "The command this buffer runs.")
(defvar-local +atuin-ai--info nil "What Atuin AI said about it (`+atuin-ai-suggestion').")
;; Kept when the finished run's buffer changes mode (ghostel-compile does).
(put '+atuin-ai--command 'permanent-local t)
(put '+atuin-ai--info 'permanent-local t)
(defvar +atuin-ai--last nil "The buffer of the last background command.")
(defvar +atuin-ai--questions nil "Questions typed with `+atuin-ai/ask-typed'.")
(defvar +atuin-ai--running nil "(BUFFER FILE ORIGIN HOW OPENED) of each open box.")

;;;; What the box said

(defun +atuin-ai-parse (output)
  "OUTPUT of `atuin ai inline --hook' (its stderr) as (KIND . TEXT): KIND
is execute, insert, print or cancel; the protocol is `atuin ai init zsh's.
Anything else it printed (an error, say) comes back as an answer."
  (let ((out (string-trim-right (or output "") "\n+")))
    (if (string-match "__atuin_ai_\\(print\\|cancel\\|execute\\|insert\\)__:?" out)
        (let ((kind (intern (match-string 1 out)))
              (text (substring out (match-end 0))))
          (if (eq kind 'cancel) (list 'cancel) (cons kind text)))
      (if (string-blank-p out) (list 'cancel) (cons 'print out)))))

;;;; Where you asked from

(defun +atuin-ai--shell-p (buffer)
  (with-current-buffer buffer
    (derived-mode-p 'eshell-mode 'comint-mode 'vterm-mode 'ghostel-mode 'eat-mode)))

(defun +atuin-ai--origin ()
  "Where the question is asked: buffer, window, directory (where commands
run, remote ones too), the box's directory (local: Atuin is here), prompt
or not."
  (list :buffer (current-buffer) :window (selected-window)
        :dir default-directory
        :box-dir (if (file-remote-p default-directory) (expand-file-name "~/") default-directory)
        :minibuffer (minibufferp)))

;;;; The box

(defun +atuin-ai--launch (question origin how)
  "Atuin AI's box in a terminal below, QUESTION (if any) already sent.
When it closes, what was chosen is done for ORIGIN, commands run HOW."
  (require 'ghostel)
  (let* ((file (make-temp-file "atuin-ai-" nil ".out"))
         (default-directory (plist-get origin :box-dir))
         (buf (generate-new-buffer +atuin-ai-buffer)))
    (with-current-buffer buf (setq default-directory (plist-get origin :box-dir)))
    ;; Known before it can close (`+atuin-ai--exit-h').  Ghostel buffers
    ;; start in Evil's insert state by themselves: keys go to the box.
    (push (list buf file origin how (float-time)) +atuin-ai--running)
    (let ((enable-recursive-minibuffers t))
      (pop-to-buffer buf))
    ;; stdout is the terminal (the box); the choice goes to stderr.
    (ghostel-exec buf "sh"
                  (list "-c" "exec atuin ai inline --hook ${1:+\"$1\"} 2>\"$2\""
                        "atuin-ai" (or question "") file))
    buf))

(defun +atuin-ai--exit-h (buffer _event)
  "A box closed: do what was chosen in it."
  (when-let* ((box (assq buffer +atuin-ai--running)))
    (setq +atuin-ai--running (delq box +atuin-ai--running))
    (pcase-let ((`(,_ ,file ,origin ,how ,opened) box))
      (let ((result (+atuin-ai-parse
                     (with-temp-buffer
                       (ignore-errors (insert-file-contents file))
                       (buffer-string)))))
        (ignore-errors (delete-file file))
        (when-let* ((w (get-buffer-window buffer t)))
          (ignore-errors (delete-window w)))
        ;; Out of the sentinel before acting.
        (run-at-time 0 nil #'+atuin-ai--act result origin how opened)))))

(add-hook 'ghostel-exit-functions #'+atuin-ai--exit-h)

(defun +atuin-ai--back (origin)
  "Select where the question was asked, if it is still there."
  (let ((win (plist-get origin :window)))
    (when (window-live-p win) (select-window win))
    (when (buffer-live-p (plist-get origin :buffer))
      (set-buffer (plist-get origin :buffer)))))

(defun +atuin-ai--act (result origin how &optional opened)
  "Do what RESULT (from `+atuin-ai-parse') says, for ORIGIN.
OPENED: when the box opened (to find what Atuin AI said about a command)."
  (+atuin-ai--back origin)
  (+atuin-ai--record result opened)
  (pcase result
    (`(cancel) nil)
    (`(print . ,text) (+atuin-ai--answer text))
    (`(execute . ,command) (+atuin-ai--execute command origin how opened))
    (`(insert . ,command) (+atuin-ai--insert command origin how))))

;;;; What Atuin AI said about a command

(defcustom +atuin-ai-sessions-db (expand-file-name "~/.local/share/atuin/ai_sessions.db")
  "Atuin AI's conversations (read only, to learn how risky a command is)."
  :type 'file)

(defcustom +atuin-ai-confirm '("high")
  "Risk levels (Atuin AI's: low, medium, high) that ask before a command
runs in the background, where you wouldn't see it start."
  :type '(repeat string))

(defun +atuin-ai--open-db ()
  "Atuin's sessions database, read only where `sqlite-open' offers that
(newer Emacs; it is only ever read here either way)."
  (if (> (or (cdr (func-arity #'sqlite-open)) 0) 1)
      ;; Only reached where it takes READONLY; older ones would warn.
      (with-no-warnings (sqlite-open +atuin-ai-sessions-db t))
    (sqlite-open +atuin-ai-sessions-db)))

(defun +atuin-ai-suggestion (command &optional since)
  "What Atuin AI said when it suggested COMMAND (since SINCE, seconds):
\(:danger LEVEL :danger-notes TEXT :confidence LEVEL :description TEXT),
from its own record of the conversation; nil if it isn't there.  The
newest suggestion when none is COMMAND exactly (the hook can respell it)."
  (when (and (fboundp 'sqlite-available-p) (sqlite-available-p)
             (file-readable-p +atuin-ai-sessions-db))
    (ignore-errors
      (let ((db (+atuin-ai--open-db)))
        (unwind-protect
            (let* ((inputs
                    (mapcar (lambda (row)
                              (alist-get 'input (json-parse-string (car row) :object-type 'alist)))
                            (sqlite-select
                             db "select event_data from session_events
                                 where event_type = 'tool_call' and created_at >= ?
                                   and event_data like '%\"suggest_command\"%'
                                 order by created_at desc limit 20"
                             (list (floor (or since 0))))))
                   (same (lambda (i) (equal (+atuin-ai--one-line (alist-get 'command i ""))
                                            (+atuin-ai--one-line command))))
                   (input (or (seq-find same inputs) (car inputs))))
              (when input
                (list :danger (alist-get 'danger input)
                      :danger-notes (alist-get 'danger_notes input)
                      :confidence (alist-get 'confidence input)
                      :description (alist-get 'description input))))
          (sqlite-close db))))))

(defun +atuin-ai-conversation (since)
  "What was said in the box since SINCE (seconds), oldest first:
\((you . TEXT) (ai . TEXT) (call . (NAME . INPUT)) …), from Atuin's record."
  (when (and (fboundp 'sqlite-available-p) (sqlite-available-p)
             (file-readable-p +atuin-ai-sessions-db))
    (ignore-errors
      (let ((db (+atuin-ai--open-db)))
        (unwind-protect
            (mapcar (lambda (row)
                      (let ((data (json-parse-string (cadr row) :object-type 'alist)))
                        (pcase (car row)
                          ("user_message" (cons 'you (alist-get 'content data)))
                          ("text" (cons 'ai (alist-get 'content data)))
                          (_ (cons 'call (cons (alist-get 'name data) (alist-get 'input data)))))))
                    (sqlite-select
                     db "select event_type, event_data from session_events
                         where created_at >= ?
                           and event_type in ('user_message', 'text', 'tool_call')
                         order by created_at, rowid"
                     (list (floor since))))
          (sqlite-close db))))))

(defun +atuin-ai--call-line (call)
  "CALL (NAME . INPUT) of Atuin AI as one line for the history."
  (pcase-let ((`(,name . ,input) call))
    (let ((command (and (listp input) (alist-get 'command input)))
          (danger (and (listp input) (alist-get 'danger input))))
      (format "%s: %s%s" name
              (if command (+atuin-ai--one-line command)
                (truncate-string-to-width (format "%s" (if input (json-serialize input) "")) 100 nil nil "…"))
              (if danger (format "  (%s risk)" danger) "")))))

(defun +atuin-ai--record (result since)
  "The box's turn (asked since SINCE, ended in RESULT) into familiar's
history, next to the M-ß turns (SPC A j)."
  (when (and since (require 'familiar-history nil t) (fboundp 'familiar-history-record))
    (ignore-errors
      (let* ((said (+atuin-ai-conversation since))
             (asked (mapcar #'cdr (seq-filter (lambda (e) (eq (car e) 'you)) said))))
        (when asked
          (familiar-history-record
           :prompt (string-join asked "\n\n")
           :answer (string-join
                    (delq nil (append
                               (mapcar #'cdr (seq-filter (lambda (e) (eq (car e) 'ai)) said))
                               (list (pcase result
                                       (`(execute . ,c) (format "→ run: %s" c))
                                       (`(insert . ,c) (format "→ inserted: %s" c))))))
                    "\n\n")
           :calls (mapcar (lambda (e) (+atuin-ai--call-line (cdr e)))
                          (seq-filter (lambda (e) (eq (car e) 'call)) said))
           :task "atuin-hub" :model "Atuin AI (Hub)"))))))

(defun +atuin-ai--confirm (command info)
  "Whether COMMAND, rated in INFO, may run in the background: background,
terminal (to watch it instead) or nil."
  (let ((danger (plist-get info :danger)))
    (if (not (member danger +atuin-ai-confirm))
        'background
      (pcase (car (read-multiple-choice
                   (format "Atuin AI rates `%s' %s risk%s.  Run it"
                           (+atuin-ai--one-line command) danger
                           (if-let* ((n (plist-get info :danger-notes))) (format " (%s)" n) ""))
                   '((?b "in the background" "Out of sight, as you asked")
                     (?t "in a terminal" "Where you watch it")
                     (?n "not at all" "Nothing runs"))))
        (?b 'background) (?t 'terminal) (_ nil)))))

;;;; Doing it

(defun +atuin-ai--answer (text)
  (let ((text (string-trim (ansi-color-apply text))))
    (if (<= (length (split-string text "\n")) +atuin-ai-answer-lines)
        (message "%s" text)
      (with-current-buffer (get-buffer-create "*Atuin AI answer*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert text "\n")
          (goto-char (point-min)))
        (special-mode)
        (display-buffer (current-buffer))))))

(defun +atuin-ai--in-shell (buffer command run)
  "COMMAND onto BUFFER's shell prompt; RUN: and run it.  Nil if no shell."
  (with-current-buffer buffer
    (when (and (+atuin-ai--shell-p buffer) (+atuin--insert-in-shell command))
      (when run
        (cond ((derived-mode-p 'eshell-mode) (eshell-send-input))
              ((derived-mode-p 'comint-mode) (comint-send-input))
              ((derived-mode-p 'vterm-mode) (vterm-send-return))
              ((derived-mode-p 'ghostel-mode) (ghostel-send-string "\r"))
              ((derived-mode-p 'eat-mode) (eat-term-send-string eat-terminal "\r"))))
      t)))

(defun +atuin-ai--in-prompt (origin command run)
  "COMMAND into the shell-command prompt of ORIGIN; RUN: and submit it."
  (when (and (plist-get origin :minibuffer) (active-minibuffer-window))
    (select-window (active-minibuffer-window))
    (delete-minibuffer-contents)
    (insert command)
    (when run (exit-minibuffer))
    t))

(defun +atuin-ai--execute (command origin how &optional opened)
  (or (+atuin-ai--in-prompt origin command t)
      (+atuin-ai--in-shell (plist-get origin :buffer) command t)
      (let* ((default-directory (plist-get origin :dir))
             (info (+atuin-ai-suggestion command opened))
             (how (if (eq how 'background) (+atuin-ai--confirm command info) how)))
        (pcase how
          ('background (+atuin-ai-background command info))
          ('terminal (+atuin-ai-terminal command))
          (_ (message "Not run: %s" (+atuin-ai--one-line command)))))))

(defun +atuin-ai--in-document (buffer command)
  "COMMAND as a shell block at point, in an Org or Markdown BUFFER."
  (with-current-buffer buffer
    (when-let* ((block (cond ((derived-mode-p 'org-mode) "#+begin_src sh\n%s\n#+end_src\n")
                             ((derived-mode-p 'markdown-mode) "```sh\n%s\n```\n"))))
      (unless (bolp) (end-of-line) (insert "\n"))
      (insert (format block command))
      t)))

(defun +atuin-ai--insert (command origin how)
  (or (+atuin-ai--in-prompt origin command nil)
      (+atuin-ai--in-shell (plist-get origin :buffer) command nil)
      (+atuin-ai--in-document (plist-get origin :buffer) command)
      (let ((default-directory (plist-get origin :dir)))
        (+atuin-ai--execute (read-shell-command
                             (format "Run in %s: " (abbreviate-file-name default-directory))
                             command)
                            (list :dir default-directory) how))))

(defun +atuin-ai--one-line (command)
  "COMMAND on one line, for names and messages."
  (string-trim (replace-regexp-in-string "[ \t]*\n[ \t]*" " " command)))

(defun +atuin-ai-terminal (command)
  "Run COMMAND in a fresh terminal in `default-directory'; it stays a shell."
  (require 'ghostel)
  (let* ((ghostel-buffer-name (format "*ghostel: %s*" (truncate-string-to-width (+atuin-ai--one-line command) 40 nil nil "…")))
         (buf (ghostel '(4))))
    (with-current-buffer buf (ghostel-send-string (concat command "\r")))
    buf))

(defun +atuin-ai-background (command &optional info)
  "Run COMMAND out of sight in `default-directory' (a remote one too);
report when it ends.  INFO: what Atuin AI said about it (its risk)."
  (let* ((name (format "*atuin: %s*" (truncate-string-to-width (+atuin-ai--one-line command) 50 nil nil "…")))
         (compilation-save-buffers-predicate #'ignore)   ; save nothing of yours
         (display-buffer-overriding-action '(display-buffer-no-window (allow-no-window . t)))
         (buf (compilation-start command nil (lambda (_) name))))
    (with-current-buffer buf
      (setq-local +atuin-ai--command command)
      (setq-local +atuin-ai--info info)
      (add-hook 'compilation-finish-functions #'+atuin-ai--report nil t))
    (message "Running in the background%s: %s"
             (if (file-remote-p default-directory)
                 (format " on %s" (file-remote-p default-directory 'host)) "")
             (+atuin-ai--one-line command))
    buf))

(defun +atuin-ai-output (buffer &optional lines)
  "The last LINES (default 30) BUFFER's command printed."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (let ((end (if (re-search-backward "^Compilation \\(?:finished\\|exited\\|interrupt\\|killed\\)" nil t)
                     (match-beginning 0) (point-max))))
        (goto-char end)
        (forward-line (- (or lines 30)))
        (string-trim (buffer-substring-no-properties (point) end))))))

(defun +atuin-ai-last-line (buffer)
  "The last line BUFFER's command printed (before the compile footer)."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (when (re-search-backward "^Compilation \\(?:finished\\|exited\\|interrupt\\|killed\\)" nil t)
        (goto-char (match-beginning 0)))
      (skip-chars-backward " \t\n")
      (let ((line (string-trim (buffer-substring-no-properties (line-beginning-position) (point)))))
        (unless (or (string-empty-p line)
                    (string-prefix-p "Compilation started" line)
                    (equal line +atuin-ai--command))
          line)))))

(defun +atuin-ai--report (buffer status)
  "Say how the background command in BUFFER ended (STATUS from compile)."
  (let* ((ok (string-prefix-p "finished" status))
         (command (buffer-local-value '+atuin-ai--command buffer))
         (danger (plist-get (buffer-local-value '+atuin-ai--info buffer) :danger))
         (last (+atuin-ai-last-line buffer))
         (text (format "%s %s%s%s" (if ok "✔" "✘") (+atuin-ai--one-line command)
                       (if (member danger '("medium" "high")) (format " [%s risk]" danger) "")
                       (if last (concat "  →  " last) ""))))
    (message "%s  (%s)" (propertize text 'face (if ok 'success 'error))
             (substitute-command-keys
              (if ok "its output: \\[+atuin-ai/last-output]"
                "its output: \\[+atuin-ai/last-output], why: \\[+atuin-ai/why]")))
    (setq +atuin-ai--last buffer)
    (when (and (not (eq (frame-focus-state) t))
               (require 'notifications nil t))
      (ignore-errors
        (notifications-notify :title (if ok "Done" "Failed") :body text
                              :app-name "Emacs")))))

(defun +atuin-ai/last-output ()
  "The output of the last command run in the background."
  (interactive)
  (if (buffer-live-p +atuin-ai--last)
      (pop-to-buffer +atuin-ai--last)
    (user-error "No background command yet")))

(defun +atuin-ai/why (&optional buffer)
  "Ask Atuin AI why the last background command (or BUFFER's) failed:
the command, where, how it ended and its last output are the question."
  (interactive)
  (let ((buf (or buffer +atuin-ai--last)))
    (unless (buffer-live-p buf) (user-error "No background command yet"))
    (let* ((command (buffer-local-value '+atuin-ai--command buf))
           (dir (buffer-local-value 'default-directory buf))
           (status (with-current-buffer buf
                     (save-excursion
                       (goto-char (point-max))
                       (when (re-search-backward "^Compilation \\(.*\\) at " nil t)
                         (match-string-no-properties 1)))))
           (output (+atuin-ai-output buf 30))
           (question (format "This failed (%s) in %s:\n%s\nIts last output:\n%s\nWhy, and what should I run instead?"
                             (or status "failed") (abbreviate-file-name dir) command
                             (truncate-string-to-width output 1500 nil nil "…"))))
      (let ((default-directory dir))
        (+atuin-ai--launch question (+atuin-ai--origin) +atuin-ai-run)))))

;;;; Commands

;;;###autoload
(defun +atuin-ai/ask (&optional other question)
  "Atuin AI's box (the `?' of zsh), from here.  The region is the question.
A command you run from it runs here if this is a shell or a shell-command
prompt, else as `+atuin-ai-run' says (OTHER, \\[universal-argument]: the
other way).  QUESTION is sent right away."
  (interactive (list current-prefix-arg
                     (when (use-region-p)
                       (prog1 (buffer-substring-no-properties (region-beginning) (region-end))
                         (deactivate-mark)))))
  (+atuin-ai--launch question (+atuin-ai--origin)
                     (if other (if (eq +atuin-ai-run 'terminal) 'background 'terminal)
                       +atuin-ai-run)))

(defun +atuin-ai/ask-background (&optional question)
  "Ask; a command you run from the box runs in the background."
  (interactive)
  (+atuin-ai--launch question (+atuin-ai--origin) 'background))

(defun +atuin-ai/ask-terminal (&optional question)
  "Ask; a command you run from the box runs in a fresh terminal."
  (interactive)
  (+atuin-ai--launch question (+atuin-ai--origin) 'terminal))

(defun +atuin-ai/ask-typed (question)
  "Type the QUESTION here first (history: M-p), then the box answers it."
  (interactive (list (read-string "Ask Atuin AI: " nil '+atuin-ai--questions)))
  (+atuin-ai--launch question (+atuin-ai--origin) +atuin-ai-run))

(defun +atuin-ai--empty-input-p ()
  "Whether the prompt here has nothing typed yet."
  (cond ((minibufferp) (string-empty-p (minibuffer-contents)))
        ((derived-mode-p 'eshell-mode)
         (string-blank-p (buffer-substring eshell-last-output-end (point-max))))
        ((derived-mode-p 'comint-mode)
         (when-let* ((proc (get-buffer-process (current-buffer))))
           (string-blank-p (buffer-substring (process-mark proc) (point-max)))))))

(defun +atuin-ai/question-mark (n)
  "At an empty prompt, Atuin AI's box (as `?' in zsh); else insert `?'."
  (interactive "p")
  (if (+atuin-ai--empty-input-p)
      (+atuin-ai/ask)
    (self-insert-command n)))

(defun +atuin-ai/toggle-run ()
  "Switch `+atuin-ai-run' between terminal and background."
  (interactive)
  (setq +atuin-ai-run (if (eq +atuin-ai-run 'terminal) 'background 'terminal))
  (message "Atuin AI commands run: %s" +atuin-ai-run))

(transient-define-prefix +atuin-ai-menu ()
  "Atuin AI from Emacs."
  [:description (lambda () (format "Atuin AI   commands run: %s" +atuin-ai-run))
   ["Ask"
    ("!" "Ask (region: the question)"    +atuin-ai/ask)
    ("t" "Ask; run in a terminal"        +atuin-ai/ask-terminal)
    ("b" "Ask; run in the background"    +atuin-ai/ask-background)
    ("q" "Type the question first…"      +atuin-ai/ask-typed)]
   ["Then"
    ("o" "Last background output"        +atuin-ai/last-output)
    ("w" "Why did it fail?"              +atuin-ai/why)
    ("r" "Switch how commands run"       +atuin-ai/toggle-run :transient t)
    ("h" "Shell history (Atuin)"         +atuin/history)]])

(when (fboundp 'set-popup-rule!)          ; Doom's popups
  (set-popup-rule! "^\\*Atuin AI\\*" :side 'bottom :size 0.4 :select t :quit nil :ttl 0 :modeline nil)
  (set-popup-rule! "^\\*Atuin AI answer\\*" :side 'bottom :size 0.3 :select nil :quit t))

(map! :leader
      :desc "Ask the shell (Atuin AI)" "!" #'+atuin-ai/ask
      (:prefix "o"
       :desc "Atuin AI menu" "!" #'+atuin-ai-menu))
(map! :map minibuffer-local-shell-command-map "?" #'+atuin-ai/question-mark)
(map! :after eshell :map eshell-mode-map :i "?" #'+atuin-ai/question-mark)
(map! :after shell :map shell-mode-map :i "?" #'+atuin-ai/question-mark)

(provide '+atuin-ai)
;;; +atuin-ai.el ends here
