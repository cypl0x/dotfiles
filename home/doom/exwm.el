;;; exwm.el --- EXWM window manager configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; EXWM configuration for Doom Emacs on NixOS.
;;
;; Design principles:
;; - Firefox starts in line-mode so Tridactyl normal/insert modes work correctly
;;   Use s-p to temporarily switch to char-mode if needed (e.g. unusual inputs)
;; - Terminals start in char-mode (direct key passthrough)
;; - 1Password desktop tiles and starts in char-mode
;; - Dialog-like apps (Pavucontrol etc.) float
;; - exwm-input-line-mode-passthrough is OFF
;; - exwm-firefox-evil is NOT used
;; - s-w is the window management prefix (m/v/s/w/d/h/j/k/l/1-9)
;; - s-<return> locks the screen via xsecurelock
;; - All hooks use named functions so SPC h r r replaces them cleanly

;;; Code:

(require 'seq)

;; ---------------------------------------------------------------------------
;; Alt-Tab window ring cycler
;; ---------------------------------------------------------------------------

(defvar +exwm--ring-index 0)
(defvar +exwm--ring-list nil)

(defun +exwm--ring-buffers ()
  "All meaningful buffers in MRU order."
  (seq-filter
   (lambda (b)
     (let ((n (buffer-name b)))
       (and n
            (not (string-prefix-p " " n))
            (not (string-prefix-p "*Minibuf" n)))))
   (buffer-list)))

(defun +exwm--ring-switch (buf)
  "Switch to BUF, using workspace-aware switching for EXWM buffers."
  (if (with-current-buffer buf (eq major-mode 'exwm-mode))
      (exwm-workspace-switch-to-buffer buf)
    (switch-to-buffer buf)))

(defun +exwm/alt-tab ()
  "Cycle forward through buffers in MRU order."
  (interactive)
  (unless (eq last-command #'+exwm/alt-tab)
    (setq +exwm--ring-list (+exwm--ring-buffers)
          +exwm--ring-index 0))
  (when +exwm--ring-list
    (setq +exwm--ring-index (mod (1+ +exwm--ring-index) (length +exwm--ring-list)))
    (when-let ((buf (nth +exwm--ring-index +exwm--ring-list)))
      (+exwm--ring-switch buf))))

(defun +exwm/alt-shift-tab ()
  "Cycle backward through buffers in MRU order."
  (interactive)
  (unless (memq last-command '(+exwm/alt-tab +exwm/alt-shift-tab))
    (setq +exwm--ring-list (+exwm--ring-buffers)
          +exwm--ring-index 0))
  (when +exwm--ring-list
    (setq +exwm--ring-index (mod (1- +exwm--ring-index) (length +exwm--ring-list)))
    (when-let ((buf (nth +exwm--ring-index +exwm--ring-list)))
      (+exwm--ring-switch buf))))

;; ---------------------------------------------------------------------------
;; Main EXWM configuration
;; ---------------------------------------------------------------------------

(use-package! exwm
  :config

  (setenv "_JAVA_AWT_WM_NONREPARENTING" "1")
  (setq exwm-input-line-mode-passthrough nil)
  (setq exwm-workspace-number 9
        exwm-workspace-show-all-buffers t
        exwm-layout-show-all-buffers t)
  (setq mouse-autoselect-window t
        focus-follows-mouse t)

  ;; ---------------------------------------------------------------------------
  ;; Input mode helpers
  ;; ---------------------------------------------------------------------------

  (defun +exwm/in-exwm-buffer-p ()
    "Return non-nil when current buffer is an EXWM X window."
    (eq major-mode 'exwm-mode))

  (defun +exwm/in-char-mode-p ()
    "Return non-nil when the current EXWM buffer is in char-mode."
    (and (+exwm/in-exwm-buffer-p)
         (eq exwm--input-mode 'char-mode)))

  (defun +exwm/force-app-input ()
    "Switch current EXWM buffer to char-mode (app receives all keys)."
    (interactive)
    (if (+exwm/in-exwm-buffer-p)
        (progn (exwm-input-release-keyboard)
               (message "EXWM: char-mode (app input)"))
      (message "EXWM: not an EXWM window")))

  (defun +exwm/force-emacs-input ()
    "Switch current EXWM buffer to line-mode (Emacs receives keys)."
    (interactive)
    (if (+exwm/in-exwm-buffer-p)
        (progn (exwm-reset)
               (message "EXWM: line-mode (Emacs input)"))
      (message "EXWM: not an EXWM window")))

  (defun +exwm/toggle-input-mode ()
    "Toggle between char-mode and line-mode for the current EXWM buffer."
    (interactive)
    (if (+exwm/in-exwm-buffer-p)
        (if (+exwm/in-char-mode-p)
            (+exwm/force-emacs-input)
          (+exwm/force-app-input))
      (message "EXWM: not an EXWM window")))

  ;; ---------------------------------------------------------------------------
  ;; Window classification
  ;; ---------------------------------------------------------------------------

  (defvar +exwm-floating-classes
    '("Pavucontrol"
      "Nm-connection-editor"
      "Arandr"
      "Blueman-manager"
      "Pinentry"
      "Pinentry-gtk-2"
      "pinentry-gtk-2")
    "X11 WM_CLASS values that should open as floating windows.")

  (defvar +exwm-char-mode-classes
    '("kitty"
      "Alacritty"
      "XTerm"
      "URxvt"
      "Xterm"
      "1Password"
      "1password")
    "X11 WM_CLASS values that should start in char-mode.")

  (defun +exwm/class-in-list-p (classes)
    "Return non-nil if `exwm-class-name' is a member of CLASSES."
    (and (boundp 'exwm-class-name)
         exwm-class-name
         (member exwm-class-name classes)))

  (defun +exwm/dialog-role-p ()
    "Return non-nil when the window looks like a transient dialog."
    (or (and (boundp 'exwm-window-role)
             (stringp exwm-window-role)
             (string-match-p "dialog\\|pop-up\\|popup\\|GtkFileChooserDialog"
                             exwm-window-role))
        (and (boundp 'exwm-instance-name)
             (stringp exwm-instance-name)
             (string-match-p "dialog\\|pinentry" exwm-instance-name))))

  ;; ---------------------------------------------------------------------------
  ;; Buffer naming — named functions for clean reloading
  ;; ---------------------------------------------------------------------------

  (defun +exwm/rename-buffer-by-class ()
    "Rename EXWM buffer to its WM_CLASS."
    (exwm-workspace-rename-buffer exwm-class-name))

  (defun +exwm/rename-buffer-by-title ()
    "Rename EXWM buffer to its title for browsers and select apps."
    (when (or (not exwm-instance-name)
              (string-prefix-p "sun-awt-X11-" exwm-instance-name)
              (string= "gimp" exwm-instance-name)
              (member exwm-class-name '("firefox" "Firefox" "Navigator")))
      (exwm-workspace-rename-buffer exwm-title)))

  (add-hook 'exwm-update-class-hook #'+exwm/rename-buffer-by-class)
  (add-hook 'exwm-update-title-hook #'+exwm/rename-buffer-by-title)

  ;; ---------------------------------------------------------------------------
  ;; Window prefix map (s-w → m/v/s/w/d/h/j/k/l/1-9)
  ;; ---------------------------------------------------------------------------

  (defvar +exwm-window-map (make-sparse-keymap)
    "Keymap activated after s-w prefix.")

  (define-key +exwm-window-map (kbd "m") #'doom/window-maximize-buffer)
  (define-key +exwm-window-map (kbd "v") #'evil-window-vsplit)
  (define-key +exwm-window-map (kbd "s") #'evil-window-split)
  (define-key +exwm-window-map (kbd "w") #'evil-window-next)
  (define-key +exwm-window-map (kbd "d") #'evil-window-delete)
  (define-key +exwm-window-map (kbd "h") #'windmove-left)
  (define-key +exwm-window-map (kbd "j") #'windmove-down)
  (define-key +exwm-window-map (kbd "k") #'windmove-up)
  (define-key +exwm-window-map (kbd "l") #'windmove-right)

  (dolist (i (number-sequence 1 9))
    (define-key +exwm-window-map
      (kbd (number-to-string i))
      `(lambda () (interactive)
         (exwm-workspace-move-window ,(1- i))
         (exwm-workspace-switch ,(1- i)))))

  (defun +exwm/window-prefix ()
    "Activate window command map after s-w."
    (interactive)
    (set-transient-map +exwm-window-map))

  ;; ---------------------------------------------------------------------------
  ;; Global keybindings
  ;; ---------------------------------------------------------------------------

  (setq exwm-input-global-keys
        `((,(kbd "s-i")   . +exwm/toggle-input-mode)
          (,(kbd "s-p")   . +exwm/force-app-input)
          (,(kbd "s-e")   . +exwm/force-emacs-input)
          (,(kbd "s-<return>") . (lambda () (interactive)
                                   (start-process-shell-command "lock" nil "xsecurelock")))
          (,(kbd "s-SPC") . app-launcher)
          (,(kbd "s-&")   . (lambda (cmd)
                              (interactive (list (read-shell-command "$ ")))
                              (start-process-shell-command cmd nil cmd)))
          (,(kbd "s-b")             . consult-buffer)
          (,(kbd "M-<tab>")         . +exwm/alt-tab)
          (,(kbd "M-<iso-lefttab>") . +exwm/alt-shift-tab)
          (,(kbd "s-w")   . +exwm/window-prefix)
          (,(kbd "s-S-l") . +exwm/move-window-to-next-workspace)
          (,(kbd "s-S-h") . +exwm/move-window-to-prev-workspace)
          (,(kbd "s-f")   . +exwm/focus-firefox)
          (,(kbd "s-t")   . +exwm/firefox-switch-tab)
          ([print]        . (lambda () (interactive)
                              (start-process-shell-command "flameshot" nil "flameshot gui")))
          ,@(mapcar (lambda (i)
                      `(,(kbd (format "s-%d" i)) .
                        (lambda () (interactive)
                          (exwm-workspace-switch-create ,(1- i)))))
                    (number-sequence 1 9))
          ,@(mapcar (lambda (i)
                      `(,(kbd (format "s-S-%d" i)) .
                        (lambda () (interactive)
                          (exwm-workspace-move-window ,(1- i)))))
                    (number-sequence 1 9))))

  (setq exwm-input-prefix-keys
        '(?\C-x ?\C-u ?\C-h ?\M-x ?\M-` ?\M-& ?\M-:
          ?\s-b ?\s-w ?\s-d ?\s-a ?\s-f ?\s-t ?\s-i ?\s-p ?\s-e))

  (setq exwm-input-simulation-keys
        '(([?\C-b] . [left])
          ([?\M-b] . [C-left])
          ([?\C-f] . [right])
          ([?\M-f] . [C-right])
          ([?\C-p] . [up])
          ([?\C-n] . [down])
          ([?\C-e] . [end])
          ([?\M-v] . [prior])
          ([?\C-v] . [next])
          ([?\C-d] . [delete])
          ([?\C-k] . [S-end delete])
          ([?\M-w] . [?\C-c])
          ([?\C-s] . [?\C-f])
          ([?\C-l] . [?\C-l])
          ([?\C-r] . [?\C-r])
          ([?\C-w] . [?\C-w])))

  ;; ---------------------------------------------------------------------------
  ;; Manage hooks — named functions for clean reloading via SPC h r r
  ;; ---------------------------------------------------------------------------

  (defun +exwm/manage-float-dialogs ()
    "Rule 1: Float dialog-like windows on creation."
    (when (and (or (+exwm/class-in-list-p +exwm-floating-classes)
                   (+exwm/dialog-role-p))
               (not exwm--floating-frame))
      (exwm-floating-toggle-floating)))

  (defun +exwm/manage-char-mode ()
    "Rule 2: Start terminals and 1Password in char-mode."
    (when (+exwm/class-in-list-p +exwm-char-mode-classes)
      (exwm-input-release-keyboard)))

  (defun +exwm/manage-workspace-rules ()
    "Rule 3: Move windows to their designated workspaces on creation."
    (when (boundp 'exwm-class-name)
      (let ((class exwm-class-name)
            (id exwm--id))
        (run-with-idle-timer
         0.1 nil
         (lambda ()
           (pcase class
             ("kitty"     (exwm-workspace-move-window 1 id))
             ("firefox"   (exwm-workspace-move-window 2 id))
             ("Firefox"   (exwm-workspace-move-window 2 id))
             ("Navigator" (exwm-workspace-move-window 2 id))
             ("Beeper"    (exwm-workspace-move-window 3 id))
             ("1Password" (exwm-workspace-move-window 4 id))
             ("1password" (exwm-workspace-move-window 4 id))))))))

  (add-hook 'exwm-manage-finish-hook #'+exwm/manage-float-dialogs)
  (add-hook 'exwm-manage-finish-hook #'+exwm/manage-char-mode)
  (add-hook 'exwm-manage-finish-hook #'+exwm/manage-workspace-rules)

  ;; ---------------------------------------------------------------------------
  ;; System tray and RandR
  ;; ---------------------------------------------------------------------------

  (require 'exwm-systemtray)
  (setq exwm-systemtray-height 20)
  (exwm-systemtray-mode 1)

  (require 'exwm-randr)
  (exwm-randr-mode 1)

  ;; ---------------------------------------------------------------------------
  ;; Autostart
  ;; ---------------------------------------------------------------------------

  (defun +exwm/autostart ()
    "Launch background services and default applications on EXWM init."
    (setenv "XDG_RUNTIME_DIR" (format "/run/user/%d" (user-uid)))
    ;; System tray services
    (dolist (spec '(("picom"      . "picom -b")
                    ("dunst"      . "dunst")
                    ("nm-applet"  . "nm-applet --indicator")
                    ("pasystray"  . "pasystray")
                    ("cbatticon"  . "cbatticon")
                    ("blueman"    . "blueman-applet")
                    ("udiskie"    . "udiskie -t")
                    ("redshift"   . "redshift-gtk")
                    ("flameshot"  . "flameshot")
                    ("xss-lock"   . "xss-lock --transfer-sleep-lock -- xsecurelock")))
      (start-process-shell-command (car spec) nil (cdr spec)))
    ;; Wallpaper
    (let ((wp (expand-file-name "~/wallpaper.jpg")))
      (when (file-exists-p wp)
        (start-process-shell-command "feh" nil (concat "feh --bg-fill " wp))))
    ;; Default applications — workspace rules will move them automatically.
    (dolist (cmd '("kitty" "firefox" "beeper" "1password"))
      (start-process-shell-command cmd nil cmd)))

  (add-hook 'exwm-init-hook #'+exwm/autostart)

  ;; ---------------------------------------------------------------------------
  ;; Helper commands
  ;; ---------------------------------------------------------------------------

  (defun +exwm/focus-window-by-class (class-regexp)
    "Switch to the first EXWM buffer whose class matches CLASS-REGEXP."
    (if-let ((buf (seq-find
                   (lambda (b)
                     (with-current-buffer b
                       (and (eq major-mode 'exwm-mode)
                            (string-match-p class-regexp
                                            (or exwm-class-name "")))))
                   (buffer-list))))
        (exwm-workspace-switch-to-buffer buf)
      (message "No window matching '%s' found" class-regexp)))

  (defun +exwm/focus-firefox ()
    "Focus Firefox window."
    (interactive)
    (+exwm/focus-window-by-class "firefox\\|Firefox\\|Navigator"))

  (defun +exwm/describe-current-x-window ()
    "Print EXWM metadata for the current X window to the echo area."
    (interactive)
    (if (+exwm/in-exwm-buffer-p)
        (message "class=%S instance=%S title=%S role=%S floating=%S input=%S"
                 (and (boundp 'exwm-class-name) exwm-class-name)
                 (and (boundp 'exwm-instance-name) exwm-instance-name)
                 (and (boundp 'exwm-title) exwm-title)
                 (and (boundp 'exwm-window-role) exwm-window-role)
                 (and (boundp 'exwm--floating-frame) exwm--floating-frame)
                 (and (boundp 'exwm--input-mode) exwm--input-mode))
      (message "Not an EXWM window")))

  (defun +exwm/move-window-to-next-workspace ()
    "Move the current EXWM window to the next workspace (wraps)."
    (interactive)
    (let* ((current (exwm-workspace--position (selected-frame)))
           (next (mod (1+ current) exwm-workspace-number)))
      (exwm-workspace-move-window next)))

  (defun +exwm/move-window-to-prev-workspace ()
    "Move the current EXWM window to the previous workspace (wraps)."
    (interactive)
    (let* ((current (exwm-workspace--position (selected-frame)))
           (prev (mod (1- current) exwm-workspace-number)))
      (exwm-workspace-move-window prev)))

  (exwm-wm-mode 1))

;; ---------------------------------------------------------------------------
;; spookfox — Firefox tab switching from Emacs
;; ---------------------------------------------------------------------------

(use-package! spookfox
  :config
  (require 'spookfox-tabs)
  (condition-case err
      (spookfox-start-server)
    (error (message "spookfox: server already running or port in use: %s"
                    (error-message-string err))))

  (defun +exwm/firefox-switch-tab ()
    "Switch Firefox tab via spookfox, then focus the Firefox window."
    (interactive)
    (spookfox-switch-tab)
    (+exwm/focus-firefox))

  (map! :leader
        (:prefix ("F" . "Firefox / EXWM")
         :desc "Switch tab"        "t" #'+exwm/firefox-switch-tab
         :desc "Focus Firefox"     "f" #'+exwm/focus-firefox
         :desc "Describe X window" "x" #'+exwm/describe-current-x-window
         :desc "Toggle input mode" "i" #'+exwm/toggle-input-mode)))

(after! exwm-mff
  (exwm-mff-mode 1))

(provide 'exwm)
;;; exwm.el ends here
