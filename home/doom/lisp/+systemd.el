;;; lisp/+systemd.el --- systemd and the journal, the way proced shows processes -*- lexical-binding: t; -*-
;;
;; SPC o s   units: system and user ones in one list, state colored, failed
;;           first; act on the one at point
;;   RET status (systemctl status)        l   its journal, following
;;   s start   S stop   r restart   R reload   e enable   d disable
;;   u   system / user / both            a   all units, not only loaded ones
;;   f   failed only                     /   filter by name (regexp)
;;   t   timers: next run, last run, what they start
;;   g   refresh                         ?   the menu
;;
;; SPC o j   the journal, following: colored by priority, unit and time;
;;   RET an entry's fields   p priority   u unit   b this boot / all
;;   /  grep   s since   c clear filters   g reload   ?  the menu
;;
;; System units are changed with `sudo -n systemctl' (no password prompt:
;; it fails rather than asks), user units with `systemctl --user'.  Stop,
;; disable and restart of system units ask first.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)
(require 'ansi-color)

;;;; Running systemctl

(defun +systemd--json (scope &rest args)
  "systemctl ARGS --output=json for SCOPE (system or user), parsed."
  (with-temp-buffer
    (apply #'call-process "systemctl" nil t nil
           (append (and (eq scope 'user) '("--user")) args '("--output=json" "--no-pager")))
    (goto-char (point-min))
    (or (ignore-errors (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil))
        nil)))

(defun +systemd--run (scope verb unit)
  "systemctl VERB UNIT in SCOPE; say what it said."
  (let* ((cmd (if (eq scope 'user)
                  (list "systemctl" "--user" verb unit)
                (list "sudo" "-n" "systemctl" verb unit))))
    (with-temp-buffer
      (let ((status (apply #'call-process (car cmd) nil t nil (cdr cmd))))
        (message "%s %s: %s" verb unit
                 (if (zerop status) "done"
                   (let ((out (string-trim (buffer-string))))
                     (if (string-match-p "password is required" out)
                         "needs a password (sudo -n asks for none): run it in a terminal"
                       out))))))))

;;;; Units

(defvar +systemd-scope 'both "Which units the list shows: system, user or both.")
(defvar +systemd-all nil "Non-nil: all units, not only loaded/active ones.")
(defvar +systemd-failed-only nil)
(defvar +systemd-filter nil "Regexp the unit names must match, or nil.")

(defun +systemd--state-face (active)
  (pcase active
    ("active" 'success) ("failed" 'error) ((or "activating" "deactivating" "reloading") 'warning)
    (_ 'shadow)))

(defun +systemd--units ()
  (cl-loop for scope in (pcase +systemd-scope ('both '(system user)) (s (list s)))
           append (mapcar (lambda (u) (cons scope u))
                          (apply #'+systemd--json scope "list-units"
                                 (append (and +systemd-all '("--all"))
                                         (and +systemd-failed-only '("--state=failed")))))))

(defun +systemd--rows ()
  (let ((units (cl-remove-if-not
                (lambda (u) (or (null +systemd-filter)
                                (string-match-p +systemd-filter (plist-get (cdr u) :unit))))
                (+systemd--units))))
    (mapcar (lambda (u)
              (pcase-let* ((`(,scope . ,p) u)
                           (active (plist-get p :active)))
                (list (cons scope (plist-get p :unit))
                      (vector (propertize (plist-get p :unit) 'face (if (equal active "failed") 'error 'default))
                              (symbol-name scope)
                              (propertize active 'face (+systemd--state-face active))
                              (or (plist-get p :sub) "")
                              (or (plist-get p :description) "")))))
            ;; Failed first, then by name.
            (sort units (lambda (a b)
                          (let ((fa (equal (plist-get (cdr a) :active) "failed"))
                                (fb (equal (plist-get (cdr b) :active) "failed")))
                            (if (eq fa fb)
                                (string< (plist-get (cdr a) :unit) (plist-get (cdr b) :unit))
                              fa)))))))

(defun +systemd--at ()
  (or (tabulated-list-get-id) (user-error "No unit here")))

(defun +systemd--header ()
  (let* ((rows tabulated-list-entries)
         (rows (if (functionp rows) (funcall rows) rows))
         (failed (cl-count-if (lambda (r) (equal (substring-no-properties (aref (cadr r) 2)) "failed")) rows)))
    (setq header-line-format
          (format " %d units (%s%s%s)%s   RET status · l journal · s/S/r start/stop/restart · ? menu"
                  (length rows) +systemd-scope (if +systemd-all ", all" "")
                  (if +systemd-filter (format ", matching %s" +systemd-filter) "")
                  (if (> failed 0) (propertize (format "  %d failed" failed) 'face 'error) "")))))

(defun +systemd-refresh ()
  "Read the units again."
  (interactive)
  (revert-buffer)
  (+systemd--header))

(defun +systemd--act (verb &optional ask)
  (pcase-let ((`(,scope . ,unit) (+systemd--at)))
    (when (or (not ask) (eq scope 'user) (y-or-n-p (format "%s the system unit %s? " (capitalize verb) unit)))
      (+systemd--run scope verb unit)
      (+systemd-refresh))))

(defun +systemd-start () "Start the unit." (interactive) (+systemd--act "start"))
(defun +systemd-stop () "Stop the unit." (interactive) (+systemd--act "stop" t))
(defun +systemd-restart () "Restart the unit." (interactive) (+systemd--act "restart" t))
(defun +systemd-reload () "Reload the unit." (interactive) (+systemd--act "reload"))
(defun +systemd-enable () "Enable the unit." (interactive) (+systemd--act "enable"))
(defun +systemd-disable () "Disable the unit." (interactive) (+systemd--act "disable" t))

(defun +systemd-status ()
  "systemctl status of the unit, in a buffer."
  (interactive)
  (pcase-let ((`(,scope . ,unit) (+systemd--at)))
    (with-current-buffer (get-buffer-create (format "*systemd status: %s*" unit))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (apply #'call-process "systemctl" nil t nil
               (append (and (eq scope 'user) '("--user")) (list "status" "--no-pager" "-n" "30" unit)))
        (ansi-color-apply-on-region (point-min) (point-max))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

(defun +systemd-journal ()
  "The unit's journal, following."
  (interactive)
  (pcase-let ((`(,scope . ,unit) (+systemd--at)))
    (+journal (list :unit unit :user (eq scope 'user) :boot t))))

(defun +systemd-toggle-scope ()
  "Show system units, user units, or both."
  (interactive)
  (setq +systemd-scope (pcase +systemd-scope ('both 'system) ('system 'user) (_ 'both)))
  (+systemd-refresh))

(defun +systemd-toggle-all ()
  "All units, or only loaded ones."
  (interactive)
  (setq +systemd-all (not +systemd-all))
  (+systemd-refresh))

(defun +systemd-toggle-failed ()
  "Only failed units, or all."
  (interactive)
  (setq +systemd-failed-only (not +systemd-failed-only))
  (+systemd-refresh))

(defun +systemd-filter (regexp)
  "Show units whose names match REGEXP (empty: all)."
  (interactive (list (read-string "Units matching (regexp, empty for all): " +systemd-filter)))
  (setq +systemd-filter (and (not (string-empty-p regexp)) regexp))
  (+systemd-refresh))

(defvar-keymap +systemd-mode-map
  "RET" #'+systemd-status  "l" #'+systemd-journal
  "s" #'+systemd-start  "S" #'+systemd-stop  "r" #'+systemd-restart  "R" #'+systemd-reload
  "e" #'+systemd-enable  "d" #'+systemd-disable
  "u" #'+systemd-toggle-scope  "a" #'+systemd-toggle-all  "f" #'+systemd-toggle-failed
  "/" #'+systemd-filter  "t" #'+systemd/timers  "g" #'+systemd-refresh  "?" #'+systemd-menu)

(define-derived-mode +systemd-mode tabulated-list-mode "systemd"
  "systemd units (see `+systemd/units')."
  (setq tabulated-list-format [("Unit" 44 t) ("Scope" 7 t) ("Active" 9 t) ("Sub" 10 t) ("Description" 0 nil)]
        tabulated-list-entries #'+systemd--rows
        tabulated-list-padding 1)
  (tabulated-list-init-header))

;;;###autoload
(defun +systemd/units ()
  "systemd's units: system and user, failed first (see the file)."
  (interactive)
  (with-current-buffer (get-buffer-create "*systemd*")
    (+systemd-mode)
    (tabulated-list-print)
    (+systemd--header)
    (pop-to-buffer (current-buffer))))

;;;; Timers

(defun +systemd--relative (usec)
  (if (or (null usec) (zerop usec)) "—"
    (let* ((s (- (/ usec 1e6) (float-time))) (a (abs s))
           (txt (cond ((< a 90) (format "%ds" a)) ((< a 5400) (format "%dmin" (/ a 60)))
                      ((< a 172800) (format "%dh" (/ a 3600))) (t (format "%dd" (/ a 86400))))))
      (if (> s 0) (concat "in " txt) (concat txt " ago")))))

(defun +systemd--timer-rows ()
  (cl-loop for scope in '(system user)
           append (mapcar (lambda (p)
                            (list (cons scope (plist-get p :unit))
                                  (vector (plist-get p :unit) (symbol-name scope)
                                          (+systemd--relative (plist-get p :next))
                                          (+systemd--relative (plist-get p :last))
                                          (or (plist-get p :activates) ""))))
                          (+systemd--json scope "list-timers" "--all"))))

(define-derived-mode +systemd-timers-mode tabulated-list-mode "timers"
  "systemd timers."
  (setq tabulated-list-format [("Timer" 40 t) ("Scope" 7 t) ("Next" 12 nil) ("Last" 12 nil) ("Starts" 0 nil)]
        tabulated-list-entries #'+systemd--timer-rows)
  (tabulated-list-init-header))

(define-key +systemd-timers-mode-map (kbd "RET") #'+systemd-status)
(define-key +systemd-timers-mode-map "l" #'+systemd-journal)

;;;###autoload
(defun +systemd/timers ()
  "systemd timers: when they run next and last, what they start."
  (interactive)
  (with-current-buffer (get-buffer-create "*systemd timers*")
    (+systemd-timers-mode)
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

;;;; The journal

(defvar-local +journal--filters nil
  "Plist: :unit :user :priority (0-7) :boot :grep :since.")

(defconst +journal--priorities
  '((0 "emerg" error) (1 "alert" error) (2 "crit" error) (3 "err" error)
    (4 "warning" warning) (5 "notice" success) (6 "info" default) (7 "debug" shadow)))

(defun +journal--args (filters)
  (append (list "-o" "json" "-f" "-n" "500" "--no-pager")
          (when-let* ((u (plist-get filters :unit)))
            (list (if (plist-get filters :user) "--user-unit" "--unit") u))
          (when (and (plist-get filters :user) (not (plist-get filters :unit))) (list "--user"))
          (when-let* ((p (plist-get filters :priority))) (list "-p" (number-to-string p)))
          (when (plist-get filters :boot) (list "-b"))
          (when-let* ((g (plist-get filters :grep))) (list "-g" g))
          (when-let* ((s (plist-get filters :since))) (list "--since" s))))

(defun +journal--render (entry)
  "One journal ENTRY (a plist) as a line."
  (let* ((usec (string-to-number (or (plist-get entry :__REALTIME_TIMESTAMP) "0")))
         (prio (string-to-number (or (plist-get entry :PRIORITY) "6")))
         (face (nth 2 (assq prio +journal--priorities)))
         (who (or (plist-get entry :_SYSTEMD_USER_UNIT) (plist-get entry :_SYSTEMD_UNIT)
                  (plist-get entry :SYSLOG_IDENTIFIER) (plist-get entry :_COMM) "?"))
         (msg (let ((m (plist-get entry :MESSAGE)))
                (cond ((stringp m) m)
                      ((listp m) (decode-coding-string (apply #'unibyte-string m) 'utf-8))
                      (t "")))))
    (propertize
     (concat (propertize (format-time-string "%m-%d %H:%M:%S" (/ usec 1e6)) 'face 'shadow) " "
             (propertize (truncate-string-to-width who 28 nil ?\s "…") 'face 'font-lock-type-face) " "
             (propertize (string-trim-right (replace-regexp-in-string "\n" " ⏎ " msg)) 'face face)
             "\n")
     '+journal-entry entry)))

(defun +journal--filter (proc output)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((pending (concat (or (process-get proc 'pending) "") output))
            (inhibit-read-only t))
        (let ((lines (split-string pending "\n")))
          (process-put proc 'pending (car (last lines)))
          (let ((at-end (= (point) (point-max))))
            (save-excursion
              (goto-char (point-max))
              (dolist (line (butlast lines))
                (when-let* ((entry (ignore-errors (json-parse-string line :object-type 'plist :null-object nil))))
                  (insert (+journal--render entry)))))
            (when at-end (goto-char (point-max)))))))))

(defun +journal--start ()
  (let ((inhibit-read-only t))
    (when-let* ((p (get-buffer-process (current-buffer)))) (delete-process p))
    (erase-buffer)
    (setq header-line-format
          (format " journal%s   RET entry · p priority · u unit · b boot · / grep · s since · c clear · ? menu"
                  (let ((f +journal--filters) parts)
                    (when (plist-get f :unit) (push (format "unit %s" (plist-get f :unit)) parts))
                    (when (plist-get f :priority)
                      (push (format "≤ %s" (nth 1 (assq (plist-get f :priority) +journal--priorities))) parts))
                    (when (plist-get f :boot) (push "this boot" parts))
                    (when (plist-get f :grep) (push (format "grep %s" (plist-get f :grep)) parts))
                    (when (plist-get f :since) (push (format "since %s" (plist-get f :since)) parts))
                    (if parts (concat ": " (string-join (nreverse parts) ", ")) ""))))
    (make-process :name "journal" :buffer (current-buffer) :noquery t
                  :command (cons "journalctl" (+journal--args +journal--filters))
                  :filter #'+journal--filter)))

(defun +journal--set (key value)
  (setq +journal--filters (plist-put +journal--filters key value))
  (+journal--start))

(defun +journal-priority (p)
  "Show entries of priority P (0 emerg … 7 debug) and more severe."
  (interactive (list (let ((choice (completing-read "Up to priority: " (mapcar #'cadr +journal--priorities) nil t)))
                       (car (cl-find choice +journal--priorities :key #'cadr :test #'equal)))))
  (+journal--set :priority p))

(defun +journal-unit (unit)
  "Only UNIT's entries (empty: all)."
  (interactive (list (read-string "Unit (empty for all): " (plist-get +journal--filters :unit))))
  (+journal--set :unit (and (not (string-empty-p unit)) unit)))

(defun +journal-boot () "This boot only, or all." (interactive) (+journal--set :boot (not (plist-get +journal--filters :boot))))

(defun +journal-grep (regexp)
  "Entries whose message matches REGEXP (empty: all)."
  (interactive (list (read-string "Message matches (empty for all): " (plist-get +journal--filters :grep))))
  (+journal--set :grep (and (not (string-empty-p regexp)) regexp)))

(defun +journal-since (since)
  "Entries since SINCE (\"1h ago\", \"today\", \"2026-11-05 03:00\"; empty: no limit)."
  (interactive (list (read-string "Since (e.g. 1h ago, today; empty for any): " (plist-get +journal--filters :since))))
  (+journal--set :since (and (not (string-empty-p since)) since)))

(defun +journal-clear () "No filters." (interactive) (setq +journal--filters nil) (+journal--start))
(defun +journal-reload () "Read the journal again." (interactive) (+journal--start))

(defun +journal-entry ()
  "All fields of the entry at point."
  (interactive)
  (let ((entry (or (get-text-property (point) '+journal-entry) (user-error "No entry here"))))
    (with-current-buffer (get-buffer-create "*journal entry*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (cl-loop for (k v) on entry by #'cddr
                 do (insert (propertize (format "%-28s" (substring (symbol-name k) 1)) 'face 'font-lock-keyword-face)
                            (format "%s\n" (if (stringp v) v (format "%S" v)))))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

(defvar-keymap +journal-mode-map
  "RET" #'+journal-entry  "p" #'+journal-priority  "u" #'+journal-unit  "b" #'+journal-boot
  "/" #'+journal-grep  "s" #'+journal-since  "c" #'+journal-clear  "g" #'+journal-reload  "?" #'+journal-menu)

(define-derived-mode +journal-mode special-mode "journal"
  "The systemd journal, following (see `+journal')."
  (setq-local truncate-lines t))

;;;###autoload
(defun +journal (&optional filters)
  "The journal, following, with FILTERS (see `+journal--filters')."
  (interactive)
  (with-current-buffer (get-buffer-create
                        (if (plist-get filters :unit) (format "*journal: %s*" (plist-get filters :unit)) "*journal*"))
    (unless (derived-mode-p '+journal-mode) (+journal-mode))
    (setq +journal--filters filters)
    (+journal--start)
    (goto-char (point-max))
    (pop-to-buffer (current-buffer))))

;;;; Menus

(transient-define-prefix +systemd-menu ()
  "systemd units: act on the one at point, change what's shown."
  [["The unit here"
    ("RET" "status" +systemd-status) ("l" "journal" +systemd-journal)
    ("s" "start" +systemd-start) ("S" "stop" +systemd-stop) ("r" "restart" +systemd-restart)
    ("R" "reload" +systemd-reload) ("e" "enable" +systemd-enable) ("d" "disable" +systemd-disable)]
   ["Show"
    ("u" (lambda () (format "scope: %s" +systemd-scope)) +systemd-toggle-scope :transient t)
    ("a" (lambda () (format "all units: %s" (if +systemd-all "yes" "no"))) +systemd-toggle-all :transient t)
    ("f" (lambda () (format "failed only: %s" (if +systemd-failed-only "yes" "no"))) +systemd-toggle-failed :transient t)
    ("/" "filter by name" +systemd-filter)
    ("t" "timers" +systemd/timers)
    ("j" "the journal" +journal)]])

(transient-define-prefix +journal-menu ()
  "The journal: filters."
  [["Filter"
    ("p" "priority" +journal-priority) ("u" "unit" +journal-unit) ("b" "this boot / all" +journal-boot)
    ("/" "grep" +journal-grep) ("s" "since" +journal-since) ("c" "clear" +journal-clear)]
   ["Here"
    ("RET" "the entry's fields" +journal-entry) ("g" "reload" +journal-reload)]])

;; In evil's normal state these keys (s, r, d, /, …) are evil's own; the
;; lists' maps come first (j and k still move).
(with-eval-after-load 'evil
  (dolist (map (list +systemd-mode-map +journal-mode-map +systemd-timers-mode-map))
    (evil-make-overriding-map map 'normal)))
(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))

(map! :leader
      :desc "systemd units" "o s" #'+systemd/units
      :desc "Journal"       "o j" #'+journal)

(provide '+systemd)
;;; +systemd.el ends here
