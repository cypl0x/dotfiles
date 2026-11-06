;;; lisp/+kitty.el --- Your kitty terminals, from Emacs -*- lexical-binding: t; -*-
;;
;; kitty listens on a socket per instance (home/kitty-thinkpad.nix:
;; allow_remote_control, listen_on /run/user/UID/kitty-PID), so Emacs can
;; see and drive every kitty window, not only one it started:
;;
;;   SPC o K         the menu
;;   SPC o K w       go to a kitty window: tab, title, directory, what runs
;;                   there or that it waits at the prompt, how the last
;;                   command ended
;;   SPC o K s       send the region (or the line) to a window, then Enter;
;;                   the window is remembered (C-u: pick another)
;;   SPC o K r       run a command in a new tab, in this buffer's directory
;;                   (in your shell: it lands in its history, the tab stays)
;;   SPC o K n       a new tab here; N a new window
;;   SPC o K k       send keys (ctrl+c, ctrl+d, up …)
;;   SPC o K o       a window's last command output into a buffer (C-u: all
;;                   of its scrollback); there, SPC m a asks the assistant
;;   SPC o K c       cd the window to this buffer's directory
;;   @kitty          in M-ß: the assistant sees your kitty windows and can
;;                   read what they show
;;
;; A window is (SOCKET . ID): ids are per kitty instance.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar +kitty-program "kitten" "The kitty remote-control program.")

(defvar +kitty-timeout 3 "Seconds a kitty command may take (a hung kitty must not hang Emacs).")

(defvar +kitty--target nil
  "The window `+kitty/send' sends to: (SOCKET . ID), or nil to ask.")

(defun +kitty-sockets ()
  "Sockets of the kitty instances running now."
  (seq-filter
   (lambda (s)
     (and (string-match "kitty-\\([0-9]+\\)\\'" s)
          (file-exists-p (format "/proc/%s" (match-string 1 s)))))
   (file-expand-wildcards (format "/run/user/%d/kitty-*" (user-uid)))))

(defun +kitty--call (socket input &rest args)
  "Run `kitten @ --to SOCKET ARGS', INPUT (a string or nil) on its stdin.
Returns its output; signals an error with kitty's message if it fails."
  (with-temp-buffer
    (let* ((default-directory temporary-file-directory)
           (status (apply #'call-process-region (or input "") nil "timeout" nil t nil
                          (number-to-string +kitty-timeout)
                          +kitty-program "@" "--to" (concat "unix:" socket) args)))
      (unless (eql status 0)
        (error "kitty: %s" (string-trim (if (= (buffer-size) 0) (format "exit %s" status)
                                          (buffer-string)))))
      (buffer-string))))

(defun +kitty--active-pid ()
  "The pid of the window the compositor has focused (Hyprland), or nil."
  (when (executable-find "hyprctl")
    (with-temp-buffer
      (when (eql 0 (call-process "hyprctl" nil t nil "activewindow" "-j"))
        (ignore-errors (plist-get (json-parse-string (buffer-string) :object-type 'plist) :pid))))))

(defun +kitty-windows ()
  "Every kitty window of every instance: plists, focused instance first.
Keys: :socket :kitty-pid :os-window :tab :tab-title :id :title :cwd
:at-prompt :cmd (the last command line) :status (its exit) :running
\(foreground processes) :focused."
  (let (out)
    (dolist (socket (+kitty-sockets))
      (when-let* ((json (ignore-errors (json-parse-string (+kitty--call socket nil "ls")
                                                          :object-type 'plist :array-type 'list))))
        (dolist (osw json)
          (dolist (tab (plist-get osw :tabs))
            (dolist (w (plist-get tab :windows))
              (push (list :socket socket
                          :kitty-pid (and (string-match "kitty-\\([0-9]+\\)\\'" socket)
                                          (string-to-number (match-string 1 socket)))
                          :os-window (plist-get osw :id)
                          :tab (plist-get tab :id) :tab-title (plist-get tab :title)
                          :id (plist-get w :id) :title (plist-get w :title)
                          :cwd (plist-get w :cwd)
                          :at-prompt (eq (plist-get w :at_prompt) t)
                          :cmd (let ((c (plist-get w :last_reported_cmdline))) (and (stringp c) c))
                          :status (plist-get w :last_cmd_exit_status)
                          :running (mapcar (lambda (p) (string-join (plist-get p :cmdline) " "))
                                           (plist-get w :foreground_processes))
                          :focused (and (eq (plist-get osw :is_focused) t)
                                        (eq (plist-get tab :is_focused) t)
                                        (eq (plist-get w :is_focused) t)))
                    out))))))
    ;; Each instance has a focused window; the compositor knows which has focus.
    (when-let* ((active (+kitty--active-pid)))
      (dolist (w out)
        (unless (eql (plist-get w :kitty-pid) active) (plist-put w :focused nil))))
    (sort (nreverse out) (lambda (a b) (and (plist-get a :focused) (not (plist-get b :focused)))))))

(defun +kitty--running (w)
  "What runs in window W, shortly: the foreground program, or nil at the prompt."
  (unless (plist-get w :at-prompt)
    (when-let* ((cmd (car (plist-get w :running))))
      (let ((prog (file-name-nondirectory (car (split-string cmd)))))
        (concat prog (let ((args (cdr (split-string cmd)))) (if args (concat " " (string-join args " ")) "")))))))

(defun +kitty--label (w)
  (format "%s › %s" (plist-get w :tab-title) (plist-get w :title)))

(defun +kitty--annotation (w)
  (let ((running (+kitty--running w))
        (status (plist-get w :status)))
    (concat (propertize " " 'display '(space :align-to 56))
            (propertize (abbreviate-file-name (or (plist-get w :cwd) "")) 'face 'completions-annotations)
            "  "
            (cond (running (propertize (concat "▶ " (truncate-string-to-width running 50 nil nil "…"))
                                       'face 'success))
                  (t (propertize "at the prompt" 'face 'shadow)))
            (if (and (integerp status) (/= status 0) (plist-get w :at-prompt))
                (propertize (format "  ✘ last exit %d" status) 'face 'error)
              "")
            (if (plist-get w :focused) (propertize "  (focused)" 'face 'shadow) ""))))

(defun +kitty-read-window (prompt &optional pred)
  "Pick a kitty window with PROMPT (those PRED accepts): its plist."
  (let* ((windows (or (seq-filter (or pred #'identity) (+kitty-windows))
                      (user-error "No kitty window%s" (if pred " for this" ""))))
         (cands (mapcar (lambda (w) (cons (+kitty--label w) w)) windows))
         ;; Two windows may share a label: make each unique.
         (cands (let ((seen (make-hash-table :test #'equal)))
                  (mapcar (lambda (c)
                            (let ((n (cl-incf (gethash (car c) seen 0))))
                              (if (> n 1) (cons (format "%s <%d>" (car c) n) (cdr c)) c)))
                          cands)))
         (completion-extra-properties
          (list :annotation-function (lambda (c) (+kitty--annotation (cdr (assoc c cands)))))))
    (cdr (assoc (completing-read prompt
                                 (lambda (s p a)
                                   (if (eq a 'metadata)
                                       '(metadata (category . kitty-window) (display-sort-function . identity))
                                     (complete-with-action a cands s p)))
                                 nil t)
                cands))))

(defun +kitty--match (w) (format "id:%d" (plist-get w :id)))

(defun +kitty--find (target)
  "The window plist of TARGET (SOCKET . ID), if it still exists."
  (seq-find (lambda (w) (and (equal (plist-get w :socket) (car target))
                             (eql (plist-get w :id) (cdr target))))
            (+kitty-windows)))

(defun +kitty--target (pick)
  "The window to send to: the remembered one, or (PICK, or none) ask."
  (or (and (not pick) +kitty--target (+kitty--find +kitty--target))
      (let ((w (+kitty-read-window "Send to kitty window: ")))
        (setq +kitty--target (cons (plist-get w :socket) (plist-get w :id)))
        w)))

;;;; Commands

(defun +kitty/focus (w)
  "Go to kitty window W (picked)."
  (interactive (list (+kitty-read-window "Kitty window: ")))
  (+kitty--call (plist-get w :socket) nil "focus-window" "--match" (+kitty--match w))
  ;; kitty focuses the window inside; the compositor raises its OS window.
  (when (executable-find "hyprctl")
    (call-process "hyprctl" nil 0 nil "dispatch" "focuswindow" (format "pid:%d" (plist-get w :kitty-pid)))))

(defun +kitty-send-text (w text)
  "Type TEXT into kitty window W."
  (+kitty--call (plist-get w :socket) text "send-text" "--match" (+kitty--match w) "--stdin"))

(defun +kitty/send (&optional pick)
  "Send the region, or this line, to a kitty window, then Enter.
The window is remembered; with prefix arg PICK, pick another."
  (interactive "P")
  (let* ((w (+kitty--target pick))
         (text (string-trim-right
                (if (use-region-p)
                    (buffer-substring-no-properties (region-beginning) (region-end))
                  (buffer-substring-no-properties (line-beginning-position) (line-end-position)))
                "\n")))
    (+kitty-send-text w (concat text "\r"))
    (message "Sent to kitty: %s" (+kitty--label w))))

(defun +kitty--local-dir ()
  "This buffer's directory if it's on this machine, else home."
  (if (file-remote-p default-directory) (expand-file-name "~")
    (expand-file-name default-directory)))

(defun +kitty--socket-for-new ()
  "The instance a new tab goes to: the focused one, else any."
  (or (plist-get (car (+kitty-windows)) :socket)
      (user-error "No kitty running")))

(defun +kitty-launch (type &optional command)
  "A new kitty TYPE (\"tab\" or \"os-window\") in this buffer's directory.
COMMAND, if given, is typed into its shell (so it is in the shell's
history, and the tab stays when it ends).  Returns (SOCKET . ID)."
  (let* ((socket (+kitty--socket-for-new))
         (id (string-to-number
              (string-trim (+kitty--call socket nil "launch" (concat "--type=" type)
                                         (concat "--cwd=" (+kitty--local-dir)))))))
    (when command
      ;; The shell needs a moment to show its prompt; text typed before is kept.
      (+kitty--call socket (concat command "\r") "send-text" "--match" (format "id:%d" id) "--stdin"))
    (when (executable-find "hyprctl")
      (call-process "hyprctl" nil 0 nil "dispatch" "focuswindow"
                    (format "pid:%s" (and (string-match "kitty-\\([0-9]+\\)\\'" socket)
                                          (match-string 1 socket)))))
    (cons socket id)))

(defun +kitty/run (command)
  "Run COMMAND in a new kitty tab, in this buffer's directory."
  (interactive (list (read-shell-command (format "Run in kitty (%s): "
                                                 (abbreviate-file-name (+kitty--local-dir))))))
  (setq +kitty--target (+kitty-launch "tab" command)))

(defun +kitty/new-tab ()
  "A new kitty tab in this buffer's directory."
  (interactive)
  (setq +kitty--target (+kitty-launch "tab")))

(defun +kitty/new-window ()
  "A new kitty window (OS window) in this buffer's directory."
  (interactive)
  (setq +kitty--target (+kitty-launch "os-window")))

(defconst +kitty-keys
  '("ctrl+c" "ctrl+d" "ctrl+z" "ctrl+l" "ctrl+r" "enter" "escape" "tab" "up" "down" "q" "y" "n")
  "Keys offered by `+kitty/send-key' (any kitty key name works).")

(defun +kitty/send-key (keys &optional pick)
  "Send KEYS (kitty names, space-separated: ctrl+c, up, enter) to the
window `+kitty/send' uses; with prefix arg PICK, pick another."
  (interactive (list (completing-read "Keys (e.g. ctrl+c): " +kitty-keys) current-prefix-arg))
  (let ((w (+kitty--target pick)))
    (apply #'+kitty--call (plist-get w :socket) nil "send-key" "--match" (+kitty--match w)
           (split-string keys))
    (message "Sent %s to kitty: %s" keys (+kitty--label w))))

(defun +kitty/cd (&optional pick)
  "Change the remembered window's directory to this buffer's (PICK: another)."
  (interactive "P")
  (let ((w (+kitty--target pick)))
    (unless (plist-get w :at-prompt)
      (user-error "%s isn't at its prompt (%s runs)" (+kitty--label w) (+kitty--running w)))
    (+kitty-send-text w (concat "cd -- " (shell-quote-argument (+kitty--local-dir)) "\r"))))

(defun +kitty-text (w &optional all)
  "What window W shows: its last command's output, or with ALL everything."
  (+kitty--call (plist-get w :socket) nil "get-text" "--match" (+kitty--match w)
                (concat "--extent=" (if all "all" "last_non_empty_output"))))

(defvar-local +kitty--source nil "The kitty window this buffer's text came from.")

(define-derived-mode +kitty-output-mode special-mode "kitty"
  "A kitty window's text (`+kitty/output').")

(defun +kitty/output (w &optional all)
  "Window W's last command output in a buffer; with prefix arg ALL, all of it."
  (interactive (list (+kitty-read-window (if current-prefix-arg "All the text of: " "Last output of: "))
                     current-prefix-arg))
  (let ((text (+kitty-text w all))
        (buf (get-buffer-create (format "*kitty: %s*" (plist-get w :title)))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (ansi-color-apply-on-region (point-min) (point-max)))
      (goto-char (if all (point-max) (point-min)))
      (+kitty-output-mode)
      (setq +kitty--source w)
      (setq header-line-format
            (format " %s  ·  %s  ·  %s" (+kitty--label w)
                    (or (plist-get w :cmd) "") (abbreviate-file-name (or (plist-get w :cwd) "")))))
    (pop-to-buffer buf)))

(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin model))

(defun +kitty/ask-about-output ()
  "Ask the assistant about this kitty output (from `+kitty/output')."
  (interactive)
  (unless +kitty--source (user-error "Not a kitty output buffer"))
  (familiar-ask (format "About this output of `%s` in my terminal (%s): what does it say, and if it failed, why and what to do?"
                        (or (plist-get +kitty--source :cmd) "a command")
                        (abbreviate-file-name (or (plist-get +kitty--source :cwd) "")))))

;;;; M-ß: @kitty

(declare-function gptel-make-tool "gptel" (&rest slots))

(defun +kitty--describe (w)
  (format "- window %s:%d  tab \"%s\"  title \"%s\"  cwd %s  %s%s"
          (file-name-nondirectory (plist-get w :socket)) (plist-get w :id)
          (plist-get w :tab-title) (plist-get w :title) (plist-get w :cwd)
          (if-let* ((r (+kitty--running w))) (concat "running: " r) "at the prompt")
          (if (plist-get w :cmd) (format "  last command: %s (exit %s)" (plist-get w :cmd) (plist-get w :status)) "")))

(defun +kitty--window-by-name (name)
  "The window NAME (\"kitty-PID:ID\") stands for."
  (or (and (string-match "\\`\\(kitty-[0-9]+\\):\\([0-9]+\\)\\'" name)
           (seq-find (lambda (w) (and (equal (file-name-nondirectory (plist-get w :socket)) (match-string 1 name))
                                      (= (plist-get w :id) (string-to-number (match-string 2 name)))))
                     (+kitty-windows)))
      (error "No kitty window %s" name)))

(defun +kitty-ask-tools (keywords _origin)
  "gptel tools for an M-ß turn with @kitty in KEYWORDS."
  (when (memq 'kitty keywords)
    (list (gptel-make-tool
           :name "kitty_windows" :category "kitty"
           :description "The user's kitty terminal windows: tab, title, directory, what runs there or that it is at the prompt, the last command and its exit status."
           :args nil
           :function (lambda () (mapconcat #'+kitty--describe (+kitty-windows) "\n"))
           :include t)
          (gptel-make-tool
           :name "kitty_text" :category "kitty"
           :description "What a kitty window shows: its last command's output, or everything (scrollback) with all=true.  WINDOW as kitty_windows names it (kitty-PID:ID)."
           :args '((:name "window" :type string :description "kitty-PID:ID")
                   (:name "all" :type boolean :description "All of the scrollback" :optional t))
           :function (lambda (window &optional all)
                       (let ((text (+kitty-text (+kitty--window-by-name window) (eq all t))))
                         (if (length> text 20000) (substring text -20000) text)))
           :include t))))

(defun +kitty-ask-keywords ()
  (and (+kitty-sockets) '(("kitty" . "your kitty terminals: their windows and what they show"))))

(with-eval-after-load 'familiar-ask
  (add-hook 'familiar-ask-keyword-functions #'+kitty-ask-keywords)
  (add-hook 'familiar-ask-turn-tools-functions #'+kitty-ask-tools))

;;;; Keys

(with-eval-after-load 'transient
  (transient-define-prefix +kitty-menu ()
    "Your kitty terminals."
    [["Go"
      ("w" "Go to a window" +kitty/focus)
      ("o" "Last output to a buffer (C-u: all)" +kitty/output)]
     ["Send (to the window remembered; C-u: pick)"
      ("s" "Region or line, then Enter" +kitty/send)
      ("k" "Keys (ctrl+c …)" +kitty/send-key)
      ("c" "cd to this directory" +kitty/cd)]
     ["New, in this directory"
      ("r" "Run a command in a tab" +kitty/run)
      ("n" "Tab" +kitty/new-tab)
      ("N" "Window" +kitty/new-window)]]))

(map! :leader :desc "kitty" "o K" #'+kitty-menu)
(map! :map +kitty-output-mode-map :localleader "a" #'+kitty/ask-about-output)

(provide '+kitty)
;;; +kitty.el ends here
