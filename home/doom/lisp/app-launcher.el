;;; app-launcher.el -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'consult)
(require 'json)
(require 'subr-x)

(defgroup app-launcher nil
  "Universal application launcher and switcher."
  :group 'convenience)

(defcustom app-launcher-desktop-dirs
  '("/run/current-system/sw/share/applications"
    "~/.local/share/applications")
  "Directories containing .desktop files for the app launcher source."
  :type '(repeat directory))

(defcustom app-launcher-firefox-wmctrl-title "Firefox"
  "wmctrl window title (or substring) used to focus Firefox."
  :type 'string)

(defcustom app-launcher-tridactyl-tabs-command nil
  "Shell command (string) that outputs a JSON array of tabs.

This command is executed via Tridactyl's native messenger host (cmd=run).
Each tab object should include at least a title and an id/index.
Example tab object keys: title, id, index, url.
"
  :type '(choice (const :tag "Disabled" nil) string))

(defcustom app-launcher-tridactyl-switch-command nil
  "Command used to switch Firefox tabs via Tridactyl.

If a string, it is formatted with a single %s argument (tab id or index).
If a function, it is called with a tab plist and must return a command string.
The command is executed via the native messenger host (cmd=run).
"
  :type '(choice (const :tag "Disabled" nil) string function))

(defcustom app-launcher-shell-buffer-name "*shell-output*"
  "Buffer name used for async shell command output."
  :type 'string)

(defvar app-launcher-history nil
  "Minibuffer history for `app-launcher'.")

(defvar app-launcher-shell-history nil
  "History of shell commands launched via `app-launcher'.")

(defvar app-launcher--warned (make-hash-table :test 'equal))

(defun app-launcher--warn-once (key message)
  "Display MESSAGE once per KEY."
  (unless (gethash key app-launcher--warned)
    (puthash key t app-launcher--warned)
    (display-warning 'app-launcher message :warning)))

(defun app-launcher--candidate (prefix label value &optional kind)
  "Build a display candidate with PREFIX and LABEL storing VALUE and KIND."
  (propertize (concat prefix label)
              'app-launcher-value value
              'app-launcher-kind kind))

(defun app-launcher--value (cand)
  "Extract the stored value from CAND (or return CAND)."
  (or (get-text-property 0 'app-launcher-value cand) cand))

(defun app-launcher--wmctrl-available-p ()
  (executable-find "wmctrl"))

(defun app-launcher--wmctrl-list ()
  (when (app-launcher--wmctrl-available-p)
    (let* ((output (shell-command-to-string "wmctrl -l"))
           (lines (split-string output "\n" t))
           (titles (delq nil
                         (mapcar (lambda (line)
                                   (when (string-match "^\\S-+\\s-+\\S-+\\s-+\\S-+\\s-+\\(.*\\)$" line)
                                     (match-string 1 line)))
                                 lines))))
      titles)))

(defun app-launcher--wmctrl-activate (title)
  (when (and title (app-launcher--wmctrl-available-p))
    (call-process "wmctrl" nil 0 nil "-a" title)))

(defun app-launcher--desktop-files ()
  (let ((dirs (mapcar #'expand-file-name app-launcher-desktop-dirs)))
    (cl-mapcan (lambda (dir)
                 (when (file-directory-p dir)
                   (directory-files dir t "\\.desktop\\'")))
               dirs)))

(defun app-launcher--desktop-parse (path)
  (with-temp-buffer
    (insert-file-contents path)
    (let ((name nil)
          (nodisplay nil)
          (hidden nil))
      (goto-char (point-min))
      (while (re-search-forward "^\\([^#=]+\\)=\\(.*\\)$" nil t)
        (let ((key (match-string 1))
              (val (match-string 2)))
          (pcase key
            ("Name" (setq name val))
            ("NoDisplay" (setq nodisplay (string= val "true")))
            ("Hidden" (setq hidden (string= val "true"))))))
      (when (and name (not nodisplay) (not hidden))
        (list :name name :id (file-name-base path) :path path)))))

(defun app-launcher--desktop-apps ()
  (let ((apps (delq nil (mapcar #'app-launcher--desktop-parse
                                (app-launcher--desktop-files)))))
    (sort apps (lambda (a b)
                 (string-lessp (plist-get a :name)
                               (plist-get b :name))))))

(defun app-launcher--launch-app (app)
  (let ((id (plist-get app :id))
        (path (plist-get app :path)))
    (cond
     ((executable-find "gtk-launch")
      (call-process "gtk-launch" nil 0 nil id))
     ((executable-find "gio")
      (call-process "gio" nil 0 nil "launch" path))
     (t (user-error "Neither gtk-launch nor gio found")))))

(defun app-launcher--display-shell-buffer (buffer)
  (display-buffer-in-side-window
   buffer
   '((side . bottom) (slot . 0) (window-height . 0.33))))

(defun app-launcher--run-shell (command)
  (let* ((buffer (get-buffer-create app-launcher-shell-buffer-name))
         (process (async-shell-command command buffer)))
    (when process
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (when (buffer-live-p buffer)
             (app-launcher--display-shell-buffer buffer))))))
    (push command app-launcher-shell-history)))

(defun app-launcher--native-host-from-manifest ()
  (let ((dir (expand-file-name "~/.mozilla/native-messaging-hosts")))
    (when (file-directory-p dir)
      (let ((json-object-type 'plist)
            (json-array-type 'list))
        (cl-loop for file in (directory-files dir t "tridactyl.*\\.json\\'")
                 for path = (condition-case nil
                                (plist-get (json-read-file file) :path)
                              (error nil))
                 when (and path (file-executable-p path))
                 return path)))))

(defun app-launcher--native-host-path ()
  (or (executable-find "native_main")
      (executable-find "tridactyl-native")
      (let* ((dev-root (expand-file-name "~/dev/native_messenger"))
             (candidates (list (expand-file-name "native_main" dev-root)
                               (expand-file-name "target/release/native_main" dev-root)
                               (expand-file-name "target/debug/native_main" dev-root))))
        (cl-loop for cand in candidates
                 when (file-executable-p cand)
                 return cand))
      (app-launcher--native-host-from-manifest)))

(defun app-launcher--native-call (payload)
  (let ((binary (app-launcher--native-host-path)))
    (if (not binary)
        (progn
          (app-launcher--warn-once
           'tridactyl-native
           "Tridactyl native messenger not found; skipping Firefox tab source.")
          nil)
      (let* ((json-encoding-pretty-print nil)
             (message (json-encode payload))
             (len (string-bytes message))
             (len-bytes (list (logand len #xff)
                              (logand (lsh len -8) #xff)
                              (logand (lsh len -16) #xff)
                              (logand (lsh len -24) #xff))))
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (insert (apply #'unibyte-string len-bytes))
          (insert message)
          (let ((coding-system-for-read 'binary)
                (coding-system-for-write 'binary))
            (call-process-region (point-min) (point-max) binary t t nil))
          (goto-char (point-min))
          (when (>= (buffer-size) 4)
            (let* ((len-bytes-out (buffer-substring-no-properties (point) (+ (point) 4)))
                   (out-len (+ (aref len-bytes-out 0)
                               (lsh (aref len-bytes-out 1) 8)
                               (lsh (aref len-bytes-out 2) 16)
                               (lsh (aref len-bytes-out 3) 24)))
                   (start (+ (point) 4))
                   (end (min (+ start out-len) (point-max))))
              (when (< start end)
                (let ((json-str (buffer-substring-no-properties start end)))
                  (condition-case nil
                      (json-parse-string json-str :object-type 'plist :array-type 'list)
                    (error nil)))))))))))

(defun app-launcher--native-run-command (command)
  (app-launcher--native-call `(:cmd "run" :command ,command)))

(defun app-launcher--native-response-content (response)
  (when (listp response)
    (or (plist-get response :content)
        (plist-get response :stdout)
        (plist-get response :out))))

(defun app-launcher--tab-id (tab)
  (or (plist-get tab :id)
      (plist-get tab :tabId)
      (plist-get tab :index)
      (plist-get tab :tabIndex)))

(defun app-launcher--tridactyl-tabs ()
  (if (not app-launcher-tridactyl-tabs-command)
      (progn
        (app-launcher--warn-once
         'tridactyl-tabs-command
         "Tridactyl tab command is not configured; skipping Firefox tab source.")
        nil)
    (let* ((response (app-launcher--native-run-command
                      app-launcher-tridactyl-tabs-command))
           (content (app-launcher--native-response-content response)))
      (when (stringp content)
        (condition-case nil
            (json-parse-string content :object-type 'plist :array-type 'list)
          (error nil))))))

(defun app-launcher--tridactyl-switch (tab)
  (let* ((cmd (cond
               ((functionp app-launcher-tridactyl-switch-command)
                (funcall app-launcher-tridactyl-switch-command tab))
               ((stringp app-launcher-tridactyl-switch-command)
                (format app-launcher-tridactyl-switch-command
                        (or (app-launcher--tab-id tab)
                            (plist-get tab :title))))))
         (command (and (stringp cmd) (string-trim cmd))))
    (if (not command)
        (progn
          (app-launcher--warn-once
           'tridactyl-switch-command
           "Tridactyl switch command is not configured; cannot switch tabs.")
          nil)
      (app-launcher--native-run-command command))))

(defun app-launcher--buffer-names ()
  (let (names)
    (dolist (buf (buffer-list))
      (let ((name (buffer-name buf)))
        (when (and name
                   (not (string-prefix-p " " name))
                   (not (string-prefix-p "*Minibuf" name)))
          (push name names))))
    (nreverse names)))

(defun app-launcher--source-buffers ()
  `(:name "Buffers"
    :category app-launcher-buffer
    :narrow ?b
    :items ,(lambda ()
              (mapcar (lambda (name)
                        (app-launcher--candidate "[buf] " name name 'buffer))
                      (app-launcher--buffer-names)))
    :action ,(lambda (cand)
               (let* ((name (app-launcher--value cand))
                      (buf (get-buffer name)))
                 (if (and buf (with-current-buffer buf (eq major-mode 'exwm-mode)))
                     (exwm-workspace-switch-to-buffer buf)
                   (switch-to-buffer name))))))

(defun app-launcher--source-windows ()
  `(:name "Windows"
    :category window
    :narrow ?w
    :items ,(lambda ()
              (mapcar (lambda (title)
                        (app-launcher--candidate "[win] " title title 'window))
                      (or (app-launcher--wmctrl-list) '())))
    :action ,(lambda (cand)
               (app-launcher--wmctrl-activate (app-launcher--value cand)))))

(defun app-launcher--source-tabs ()
  `(:name "Firefox Tabs"
    :category tab
    :narrow ?t
    :items ,(lambda ()
              (let ((tabs (app-launcher--tridactyl-tabs)))
                (mapcar (lambda (tab)
                          (let ((title (or (plist-get tab :title) "(untitled)")))
                            (app-launcher--candidate "[tab] " title tab 'tab)))
                        (or tabs '()))))
    :action ,(lambda (cand)
               (let ((tab (app-launcher--value cand)))
                 (when (stringp app-launcher-firefox-wmctrl-title)
                   (app-launcher--wmctrl-activate app-launcher-firefox-wmctrl-title))
                 (app-launcher--tridactyl-switch tab)))))

(defun app-launcher--source-apps ()
  `(:name "Applications"
    :category application
    :narrow ?a
    :items ,(lambda ()
              (mapcar (lambda (app)
                        (app-launcher--candidate "[app] " (plist-get app :name) app 'app))
                      (app-launcher--desktop-apps)))
    :action ,(lambda (cand)
               (app-launcher--launch-app (app-launcher--value cand)))))

(defun app-launcher--source-shell ()
  `(:name "Shell"
    :category shell
    :narrow ?!
    :items ,(lambda ()
              (mapcar (lambda (cmd)
                        (app-launcher--candidate "[!] " cmd cmd 'shell))
                      app-launcher-shell-history))
    :action ,(lambda (cand)
               (app-launcher--run-shell (app-launcher--value cand)))))

;;;###autoload
(defun app-launcher ()
  "Universal application launcher driven by Consult."
  (interactive)
  (let* ((sources (list (app-launcher--source-buffers)
                        (app-launcher--source-windows)
                        (app-launcher--source-tabs)
                        (app-launcher--source-apps)
                        (app-launcher--source-shell)))
         (selection (consult--multi
                     sources
                     :prompt "Launcher: "
                     :history 'app-launcher-history
                     :require-match nil)))
    (when (and (stringp selection)
               (string-prefix-p "!" (string-trim-left selection)))
      (app-launcher--run-shell (string-trim (substring selection 1))))))

(provide 'app-launcher)
;;; app-launcher.el ends here
