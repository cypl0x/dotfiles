;;; lisp/+system.el --- More of the machine in Emacs: containers, ports, hardware -*- lexical-binding: t; -*-
;;
;; Beside SPC o y's network, Bluetooth, audio, disks, generations and power
;; (+desktop.el), the other tools a Linux desk reaches for, as lists:
;;
;;   SPC o y c   containers (podman): RET logs, s start/stop, x shell inside,
;;               D remove; i images
;;   SPC o y o   listening ports (ss): who listens where, RET the process
;;   SPC o y u   USB devices (sysfs), P PCI devices (lspci)
;;   SPC o y T   temperatures and fans (sysfs hwmon, no lm_sensors needed)
;;   SPC o y m   kernel modules (lsmod): RET modinfo
;;   SPC o y U   users and groups
;;   SPC o y i   this machine: host, time, locale, kernel, boot
;;
;; g refreshes every list.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(eval-and-compile                     ; its list macro
  (unless (featurep '+desktop)
    (load (expand-file-name "+desktop" (file-name-directory (macroexp-file-name))) nil t)))
(defvar vterm-shell)
(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))
(declare-function vterm "ext:vterm" (&optional arg))

(declare-function +desktop--lines "+desktop" (program &rest args))
(declare-function +desktop--run "+desktop" (program &rest args))

(defun +system--read (file)
  (and (file-readable-p file)
       (string-trim (with-temp-buffer (insert-file-contents file) (buffer-string)))))

(defun +system--show (title program &rest args)
  "PROGRAM ARGS's output in a read-only buffer TITLE."
  (with-current-buffer (get-buffer-create (format "*%s*" title))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (apply #'call-process program nil t nil args)
      (ansi-color-apply-on-region (point-min) (point-max)))
    (special-mode)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

;;;; Containers (podman)

(defun +system--podman-json (&rest args)
  (with-temp-buffer
    (when (zerop (apply #'call-process "podman" nil '(t nil) nil args))
      (goto-char (point-min))
      (ignore-errors (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil)))))

(defun +system--container-rows ()
  (mapcar (lambda (c)
            (let ((id (plist-get c :Id)))
              (list id (vector (or (car (plist-get c :Names)) (substring id 0 12))
                               (or (plist-get c :Image) "")
                               (propertize (or (plist-get c :State) "")
                                           'face (if (equal (plist-get c :State) "running") 'success 'shadow))
                               (or (plist-get c :Status) "")
                               (mapconcat (lambda (p) (format "%s→%s" (plist-get p :host_port) (plist-get p :container_port)))
                                          (plist-get c :Ports) " ")))))
          (+system--podman-json "ps" "-a" "--format" "json")))

(defun +system--container () (or (tabulated-list-get-id) (user-error "No container here")))
(defun +system-container-logs () "Its logs." (interactive)
       (+system--show "podman logs" "podman" "logs" "--tail" "500" (+system--container)))
(defun +system-container-toggle () "Start or stop it." (interactive)
       (let ((running (equal (substring-no-properties (aref (tabulated-list-get-entry) 2)) "running")))
         (+desktop--run "podman" (if running "stop" "start") (+system--container))))
(defun +system-container-shell () "A shell inside it." (interactive)
       (let ((id (+system--container)))
         (if (fboundp 'vterm) (let ((vterm-shell (format "podman exec -it %s sh" id))) (vterm (format "*podman %s*" (substring id 0 12))))
           (make-term (format "podman %s" (substring id 0 12)) "podman" nil "exec" "-it" id "sh")
           (pop-to-buffer (format "*podman %s*" (substring id 0 12))))))
(defun +system-container-remove () "Remove it." (interactive)
       (let ((id (+system--container)))
         (when (yes-or-no-p (format "Remove container %s? " (aref (tabulated-list-get-entry) 0)))
           (+desktop--run "podman" "rm" "-f" id))))

(+desktop-define-list containers "Containers"
  [("Name" 24 t) ("Image" 34 t) ("State" 9 t) ("Status" 22 t) ("Ports" 0 nil)]
  (+system--container-rows)
  ("RET" #'+system-container-logs) ("s" #'+system-container-toggle) ("x" #'+system-container-shell)
  ("D" #'+system-container-remove) ("i" #'+desktop/images) ("g" #'+desktop/containers))

(defun +system--image-rows ()
  (mapcar (lambda (i) (list (plist-get i :Id)
                            (vector (or (car (plist-get i :Names)) "<none>")
                                    (file-size-human-readable (or (plist-get i :Size) 0))
                                    (format-time-string "%F" (seconds-to-time (or (plist-get i :Created) 0))))))
          (+system--podman-json "images" "--format" "json")))

(+desktop-define-list images "Container images"
  [("Image" 60 t) ("Size" 9 t) ("Created" 0 t)]
  (+system--image-rows)
  ("g" #'+desktop/images))

;;;; Listening ports (ss)

(defun +system--port-rows ()
  (cl-loop for line in (+desktop--lines "ss" "-Htulpn")
           for f = (split-string line)
           for i from 0
           when (>= (length f) 5)
           collect (let* ((proc (and (nth 6 f) (string-match "((\"\\([^\"]+\\)\",pid=\\([0-9]+\\)" (nth 6 f))
                                     (cons (match-string 1 (nth 6 f)) (match-string 2 (nth 6 f))))))
                     (list (list i (cdr proc))
                           (vector (nth 0 f) (nth 4 f) (if proc (car proc) "(another user)")
                                   (or (cdr proc) ""))))))

(defun +system-port-process () "The process listening there." (interactive)
       (let ((pid (cadr (tabulated-list-get-id))))
         (if (not pid) (user-error "Not your process (ss shows only yours without root)")
           (+system--show (format "process %s" pid) "ps" "-o" "pid,user,etime,args" "-p" pid))))

(+desktop-define-list ports "Listening ports"
  [("Proto" 6 t) ("Address" 32 t) ("Process" 22 t) ("PID" 0 t)]
  (+system--port-rows)
  ("RET" #'+system-port-process) ("g" #'+desktop/ports))

;;;; Hardware: USB, PCI, temperatures

(defun +system--usb-rows ()
  (cl-loop for dir in (directory-files "/sys/bus/usb/devices" t "\\`[0-9]+-[0-9.]+\\'")
           for vendor = (+system--read (expand-file-name "idVendor" dir))
           when vendor
           collect (list (file-name-nondirectory dir)
                         (vector (or (+system--read (expand-file-name "product" dir)) "?")
                                 (or (+system--read (expand-file-name "manufacturer" dir)) "")
                                 (format "%s:%s" vendor (or (+system--read (expand-file-name "idProduct" dir)) ""))
                                 (concat (or (+system--read (expand-file-name "speed" dir)) "") " Mb/s")
                                 (file-name-nondirectory dir)))))

(+desktop-define-list usb "USB devices"
  [("Device" 34 t) ("Maker" 24 t) ("ID" 10 t) ("Speed" 12 t) ("Port" 0 t)]
  (+system--usb-rows)
  ("g" #'+desktop/usb))

(defun +system--pci-rows ()
  (cl-loop for line in (+desktop--lines "lspci")
           when (string-match "\\`\\(\\S-+\\) \\([^:]+\\): \\(.*\\)\\'" line)
           collect (list (match-string 1 line)
                         (vector (match-string 1 line) (match-string 2 line) (match-string 3 line)))))

(+desktop-define-list pci "PCI devices"
  [("Slot" 9 t) ("Class" 30 t) ("Device" 0 t)]
  (+system--pci-rows)
  ("g" #'+desktop/pci))

(defun +system--sensor-rows ()
  (cl-loop for hw in (directory-files "/sys/class/hwmon" t "\\`hwmon")
           for chip = (+system--read (expand-file-name "name" hw))
           append (cl-loop for input in (directory-files hw t "\\`\\(temp\\|fan\\)[0-9]+_input\\'")
                           for base = (string-remove-suffix "_input" (file-name-nondirectory input))
                           for raw = (string-to-number (or (+system--read input) "0"))
                           for temp = (string-prefix-p "temp" base)
                           for crit = (and temp (string-to-number (or (+system--read (expand-file-name (concat base "_crit") hw)) "0")))
                           collect (list (concat chip "/" base)
                                         (vector chip
                                                 (or (+system--read (expand-file-name (concat base "_label") hw)) base)
                                                 (if temp
                                                     (propertize (format "%5.1f °C" (/ raw 1000.0))
                                                                 'face (cond ((and crit (> crit 0) (> raw (* 0.9 crit))) 'error)
                                                                             ((> raw 75000) 'warning) (t 'success)))
                                                   (format "%5d rpm" raw))
                                                 (if (and crit (> crit 0)) (format "crit %.0f °C" (/ crit 1000.0)) ""))))))

(+desktop-define-list sensors "Temperatures and fans"
  [("Chip" 14 t) ("Sensor" 20 t) ("Now" 12 t) ("" 0 nil)]
  (+system--sensor-rows)
  ("g" #'+desktop/sensors))

;;;; Kernel modules

(defun +system--module-rows ()
  (cl-loop for line in (cdr (+desktop--lines "lsmod"))
           for f = (split-string line)
           collect (list (car f) (vector (car f) (file-size-human-readable (string-to-number (nth 1 f)))
                                         (nth 2 f) (or (nth 3 f) "")))))

(defun +system-module-info () "modinfo of the module." (interactive)
       (+system--show "modinfo" "modinfo" (or (tabulated-list-get-id) (user-error "No module here"))))

(+desktop-define-list modules "Kernel modules"
  [("Module" 26 t) ("Size" 8 t) ("Used" 5 t) ("By" 0 nil)]
  (+system--module-rows)
  ("RET" #'+system-module-info) ("g" #'+desktop/modules))

;;;; Users and groups

(defun +system--user-rows ()
  (let ((groups (mapcar (lambda (l) (split-string l ":")) (+desktop--lines "getent" "group"))))
    (cl-loop for line in (+desktop--lines "getent" "passwd")
             for f = (split-string line ":")
             for uid = (string-to-number (nth 2 f))
             ;; People and root; not nobody (65534) or Nix's build users (30000+).
             when (or (= uid 0) (and (>= uid 1000) (< uid 30000)))
             collect (list (car f)
                           (vector (car f) (nth 2 f) (nth 4 f) (nth 6 f)
                                   (mapconcat #'car (seq-filter (lambda (g) (member (car f) (split-string (or (nth 3 g) "") ","))) groups) " "))))))

(+desktop-define-list users "Users"
  [("User" 12 t) ("UID" 6 t) ("Name" 18 t) ("Shell" 34 t) ("Groups" 0 nil)]
  (+system--user-rows)
  ("g" #'+desktop/users))

;;;; This machine

(defun +desktop/machine ()
  "Host, time, locale, kernel and boot, as the system reports them."
  (interactive)
  (with-current-buffer (get-buffer-create "*This machine*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (part '(("Host" "hostnamectl") ("Time" "timedatectl") ("Locale" "localectl")))
        (insert (propertize (car part) 'face 'bold) "\n")
        (call-process (cadr part) nil t nil)
        (insert "\n"))
      (insert (propertize "Kernel and boot" 'face 'bold) "\n")
      (call-process "uname" nil t nil "-srvm")
      (insert "Up since " (string-trim (with-output-to-string (call-process "uptime" nil standard-output nil "-s"))) "\n"))
    (special-mode)
    (local-set-key "g" #'+desktop/machine)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

;;;; In the menu

(with-eval-after-load '+desktop
  (transient-append-suffix '+desktop-menu '(0 -1)
    ["More"
     ("c" "containers" +desktop/containers) ("o" "listening ports" +desktop/ports)
     ("u" "USB" +desktop/usb) ("P" "PCI" +desktop/pci) ("T" "temperatures, fans" +desktop/sensors)
     ("m" "kernel modules" +desktop/modules) ("U" "users, groups" +desktop/users)
     ("i" "this machine" +desktop/machine)]))

(provide '+system)
;;; +system.el ends here
