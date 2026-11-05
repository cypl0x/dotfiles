;;; lisp/+hyprland.el --- Hyprland's windows, workspaces, binds and monitors -*- lexical-binding: t; -*-
;;
;; SPC o h   windows, grouped by workspace (the focused one marked)
;;   RET focus it (switches workspace)   m move it to a workspace
;;   f float / tile    F fullscreen    p pin    c close (asks)
;;   b binds    w workspaces    M monitors    g refresh    ? menu
;; In the binds list: the keys spelled out (SUPER + SHIFT + Q), what they
;; do, their flags (locked, repeat, mouse, release), the submap; / filters;
;; RET opens the line in hyprland.conf that makes the bind.
;;
;; Editing the config itself (Lua: the API in the language server, eval in
;; the running Hyprland, its config errors) is lisp/+lua.el's.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)

(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))

(defvar +hyprland-config (expand-file-name "~/dotfiles/home/hyprland/hyprland.conf")
  "The hyprlang config binds jump into (in the repo, not the deployed copy).")

(defvar +hyprland-config-lua (expand-file-name "~/dotfiles/home/hyprland/hyprland.lua")
  "The Lua config, when Hyprland runs it.")

(defun +hyprland-lua-p ()
  "Non-nil when the running Hyprland uses the Lua config."
  (not (string-match-p "only supported with the lua config"
                       (with-output-to-string (call-process "hyprctl" nil standard-output nil "repl" "return 1")))))

(defun +hyprland--json (&rest args)
  (with-temp-buffer
    (apply #'call-process "hyprctl" nil t nil (append args '("-j")))
    (goto-char (point-min))
    (ignore-errors (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil))))

(defun +hyprland--dispatch (&rest args)
  "hyprctl dispatch ARGS; say if it failed."
  (with-temp-buffer
    (apply #'call-process "hyprctl" nil t nil "dispatch" args)
    (let ((out (string-trim (buffer-string))))
      (unless (equal out "ok") (message "hyprctl dispatch %s: %s" (string-join args " ") out)))))

;;;; Windows

(defun +hyprland--window-rows ()
  (let ((active (plist-get (+hyprland--json "activewindow") :address)))
    (mapcar (lambda (c)
              (let ((ws (plist-get c :workspace)))
                (list (plist-get c :address)
                      (vector (propertize (or (plist-get ws :name) "") 'face 'font-lock-type-face)
                              (propertize (or (plist-get c :class) "") 'face (if (equal (plist-get c :address) active) 'success 'default))
                              (or (plist-get c :title) "")
                              (string-join (delq nil (list (and (plist-get c :floating) "float")
                                                           (and (> (or (plist-get c :fullscreen) 0) 0) "full")
                                                           (and (plist-get c :pinned) "pin")))
                                           " ")
                              (number-to-string (or (plist-get c :pid) 0))))))
            (sort (+hyprland--json "clients")
                  (lambda (a b) (< (or (plist-get (plist-get a :workspace) :id) 0)
                                   (or (plist-get (plist-get b :workspace) :id) 0)))))))

(defun +hyprland--window () (or (tabulated-list-get-id) (user-error "No window here")))
(defun +hyprland--addr () (concat "address:" (+hyprland--window)))

(defun +hyprland-refresh () "Read Hyprland again." (interactive) (revert-buffer))

(defun +hyprland-focus ()
  "Focus the window (its workspace comes too)."
  (interactive)
  (+hyprland--dispatch "focuswindow" (+hyprland--addr)))

(defun +hyprland-move (workspace)
  "Move the window to WORKSPACE (a number or name), staying here."
  (interactive (list (completing-read "Move to workspace: "
                                      (mapcar (lambda (w) (plist-get w :name)) (+hyprland--json "workspaces")))))
  (+hyprland--dispatch "movetoworkspacesilent" (format "%s,%s" workspace (+hyprland--addr)))
  (+hyprland-refresh))

(defun +hyprland-float () "Float or tile the window." (interactive)
       (+hyprland--dispatch "togglefloating" (+hyprland--addr)) (+hyprland-refresh))
(defun +hyprland-pin () "Pin the window (on every workspace) or unpin it." (interactive)
       (+hyprland--dispatch "pin" (+hyprland--addr)) (+hyprland-refresh))
(defun +hyprland-fullscreen () "Fullscreen the window (focuses it)." (interactive)
       (+hyprland-focus) (+hyprland--dispatch "fullscreen" "0") (+hyprland-refresh))
(defun +hyprland-close ()
  "Close the window (asks)."
  (interactive)
  (let ((row (tabulated-list-get-entry)))
    (when (y-or-n-p (format "Close %s “%s”? " (aref row 1) (truncate-string-to-width (aref row 2) 40 nil nil "…")))
      (+hyprland--dispatch "closewindow" (+hyprland--addr))
      (+hyprland-refresh))))

(defvar-keymap +hyprland-mode-map
  "RET" #'+hyprland-focus  "m" #'+hyprland-move  "f" #'+hyprland-float  "F" #'+hyprland-fullscreen
  "p" #'+hyprland-pin  "c" #'+hyprland-close  "b" #'+hyprland/binds  "w" #'+hyprland/workspaces
  "M" #'+hyprland/monitors  "g" #'+hyprland-refresh  "?" #'+hyprland-menu)

(define-derived-mode +hyprland-mode tabulated-list-mode "Hyprland"
  "Hyprland's windows."
  (setq tabulated-list-format [("Workspace" 16 t) ("Class" 24 t) ("Title" 60 t) ("State" 12 nil) ("PID" 0 nil)]
        tabulated-list-entries #'+hyprland--window-rows
        header-line-format " Windows   RET focus · m move · f float · F full · p pin · c close · b binds · w workspaces · ? menu")
  (tabulated-list-init-header))

;;;###autoload
(defun +hyprland/windows ()
  "Hyprland's windows by workspace."
  (interactive)
  (with-current-buffer (get-buffer-create "*hyprland*")
    (+hyprland-mode)
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

;;;; Binds

(defconst +hyprland--mods '((64 . "SUPER") (4 . "CTRL") (8 . "ALT") (1 . "SHIFT") (2 . "CAPS")
                            (16 . "MOD2") (32 . "MOD3") (128 . "MOD5"))
  "Hyprland's modifier bits, in the order they're spelled.")

(defun +hyprland--keys (bind)
  (let ((mask (or (plist-get bind :modmask) 0)))
    (string-join (append (cl-loop for (bit . name) in +hyprland--mods
                                  unless (zerop (logand mask bit)) collect name)
                         (list (plist-get bind :key)))
                 " + ")))

(defvar +hyprland-binds-filter nil)

(defun +hyprland--bind-rows ()
  (cl-loop for b in (+hyprland--json "binds")
           for keys = (+hyprland--keys b)
           for what = (string-trim (format "%s %s" (plist-get b :dispatcher) (or (plist-get b :arg) "")))
           when (or (null +hyprland-binds-filter)
                    (string-match-p +hyprland-binds-filter (concat keys " " what)))
           collect (list b
                         (vector (propertize keys 'face 'help-key-binding)
                                 what
                                 (string-join (delq nil (list (and (plist-get b :locked) "locked")
                                                              (and (plist-get b :repeat) "repeat")
                                                              (and (plist-get b :mouse) "mouse")
                                                              (and (plist-get b :release) "release")))
                                              " ")
                                 (or (plist-get b :submap) "")))))

(defun +hyprland--lua-bind-line (key arg)
  "In the Lua config buffer: go to the bind of KEY (ARG's first word
 disambiguates); non-nil if found."
  (let (hits)
    (goto-char (point-min))
    (while (re-search-forward (concat "^[ \t]*bind([^,]*,[ \t]*\"" (regexp-quote key) "\"") nil t)
      (push (line-beginning-position) hits))
    (setq hits (nreverse hits))
    (when hits
      (goto-char (or (and (not (string-empty-p arg))
                          (seq-find (lambda (p) (save-excursion (goto-char p)
                                                                (search-forward (car (split-string arg)) (line-end-position) t)))
                                    hits))
                     (car hits)))
      t)))

(defun +hyprland-bind-source ()
  "The line in the running config (.lua or .conf) making the bind at point."
  (interactive)
  (let* ((b (or (tabulated-list-get-id) (user-error "No bind here")))
         (arg (string-trim (or (plist-get b :arg) "")))
         (key (plist-get b :key)))
    (if (+hyprland-lua-p)
        (progn (find-file-other-window +hyprland-config-lua)
               (unless (+hyprland--lua-bind-line key arg)
                 (message "No bind(…, \"%s\") in hyprland.lua" key)))
    (find-file-other-window +hyprland-config)
    (goto-char (point-min))
    (if (re-search-forward (concat "^[ \t]*bind[a-z]*[ \t]*=.*,[ \t]*" (regexp-quote key) "[ \t]*,.*"
                                   (regexp-quote (plist-get b :dispatcher))
                                   (if (string-empty-p arg) "" (concat ".*" (regexp-quote (car (split-string arg))))))
                           nil t)
        (beginning-of-line)
      (message "Not found by key and dispatcher; it may come from a variable or a submap")))))

(defun +hyprland-binds-filter (regexp)
  "Show binds matching REGEXP (keys or what they do; empty: all)."
  (interactive (list (read-string "Binds matching (empty for all): " +hyprland-binds-filter)))
  (setq +hyprland-binds-filter (and (not (string-empty-p regexp)) regexp))
  (revert-buffer))

(define-derived-mode +hyprland-binds-mode tabulated-list-mode "Hyprland binds"
  "Hyprland's binds."
  (setq tabulated-list-format [("Keys" 32 t) ("Does" 70 t) ("Flags" 16 nil) ("Submap" 0 t)]
        tabulated-list-entries #'+hyprland--bind-rows
        header-line-format " Binds   RET where in hyprland.conf · / filter · g refresh")
  (tabulated-list-init-header))
(define-key +hyprland-binds-mode-map (kbd "RET") #'+hyprland-bind-source)
(define-key +hyprland-binds-mode-map "/" #'+hyprland-binds-filter)

;;;###autoload
(defun +hyprland/binds ()
  "Every Hyprland bind, keys spelled out."
  (interactive)
  (with-current-buffer (get-buffer-create "*hyprland binds*")
    (+hyprland-binds-mode)
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

;;;; Workspaces and monitors

(define-derived-mode +hyprland-workspaces-mode tabulated-list-mode "Hyprland workspaces"
  "Hyprland's workspaces."
  (setq tabulated-list-format [("Workspace" 16 t) ("Monitor" 10 t) ("Windows" 8 t) ("Last window" 0 nil)]
        tabulated-list-entries
        (lambda ()
          (mapcar (lambda (w) (list (plist-get w :name)
                                    (vector (plist-get w :name) (or (plist-get w :monitor) "")
                                            (number-to-string (or (plist-get w :windows) 0))
                                            (or (plist-get w :lastwindowtitle) ""))))
                  (sort (+hyprland--json "workspaces") (lambda (a b) (< (plist-get a :id) (plist-get b :id))))))
        header-line-format " Workspaces   RET go there · g refresh")
  (tabulated-list-init-header))
(define-key +hyprland-workspaces-mode-map (kbd "RET")
            (lambda () (interactive)
              (let ((name (or (tabulated-list-get-id) (user-error "No workspace here"))))
                (if (string-prefix-p "special:" name)
                    (+hyprland--dispatch "togglespecialworkspace" (substring name 8))
                  (+hyprland--dispatch "workspace" (format "name:%s" name))))))

;;;###autoload
(defun +hyprland/workspaces ()
  "Hyprland's workspaces."
  (interactive)
  (with-current-buffer (get-buffer-create "*hyprland workspaces*")
    (+hyprland-workspaces-mode)
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

;;;###autoload
(defun +hyprland/monitors ()
  "Hyprland's monitors."
  (interactive)
  (with-current-buffer (get-buffer-create "*hyprland monitors*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (m (+hyprland--json "monitors"))
        (insert (propertize (format "%s" (plist-get m :name)) 'face 'bold)
                (format "  %s%s\n  %dx%d @ %.2f Hz, scale %s, workspace %s\n\n"
                        (plist-get m :description) (if (plist-get m :focused) "  (focused)" "")
                        (plist-get m :width) (plist-get m :height) (plist-get m :refreshRate)
                        (plist-get m :scale) (plist-get (plist-get m :activeWorkspace) :name))))
      (special-mode))
    (pop-to-buffer (current-buffer))))

(transient-define-prefix +hyprland-menu ()
  "Hyprland from Emacs."
  [["The window here"
    ("RET" "focus" +hyprland-focus) ("m" "move to workspace" +hyprland-move)
    ("f" "float / tile" +hyprland-float) ("F" "fullscreen" +hyprland-fullscreen)
    ("p" "pin" +hyprland-pin) ("c" "close" +hyprland-close)]
   ["Lists"
    ("b" "binds" +hyprland/binds) ("w" "workspaces" +hyprland/workspaces) ("M" "monitors" +hyprland/monitors)]])

(with-eval-after-load 'evil
  (dolist (map (list +hyprland-mode-map +hyprland-binds-mode-map +hyprland-workspaces-mode-map))
    (evil-make-overriding-map map 'normal)))

(map! :leader :desc "Hyprland windows" "o h" #'+hyprland/windows)

(provide '+hyprland)
;;; +hyprland.el ends here
