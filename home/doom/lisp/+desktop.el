;;; lisp/+desktop.el --- Network, Bluetooth, audio, disks, NixOS generations, power -*- lexical-binding: t; -*-
;;
;; SPC o y   the system menu; each list below in proced's style (g refreshes)
;;   n  network (NetworkManager): connections and Wi-Fi in reach
;;        RET connect (known: up; new: asks the password)  d disconnect
;;   b  Bluetooth devices          RET connect / disconnect   p power on/off
;;   a  audio (PipeWire)           RET make default   + / - volume   m mute
;;   d  disks                      RET mount / unmount (udisks, no sudo)
;;   g  NixOS generations          RET what changed since it (diff-closures)
;;                                  R roll back to it (asks; sudo)
;;   p  power: battery, charge, AC
;; With systemd (SPC o s), the journal (SPC o j), processes (SPC o k),
;; Tailscale (SPC o n) and Hyprland (SPC o h) these are the machine.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)
(require 'ansi-color)

(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))

(defun +desktop--lines (program &rest args)
  (with-temp-buffer
    (apply #'call-process program nil t nil args)
    (split-string (buffer-string) "\n" t)))

(defun +desktop--run (program &rest args)
  "Run PROGRAM ARGS; say what it said; refresh the list."
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t nil args)))
      (message "%s: %s" (file-name-nondirectory program)
               (let ((out (string-trim (buffer-string))))
                 (if (string-empty-p out) (if (zerop status) "done" "failed") out)))))
  (when (derived-mode-p 'tabulated-list-mode) (revert-buffer)))

(defmacro +desktop-define-list (name title format rows &rest keys)
  "A tabulated list NAME (command +desktop/NAME) with FORMAT and ROWS (a
function), and KEYS: (KEY COMMAND) pairs."
  (declare (indent 2))
  (let ((mode (intern (format "+desktop-%s-mode" name)))
        (cmd (intern (format "+desktop/%s" name)))
        (buf (format "*%s*" title)))
    `(progn
       (define-derived-mode ,mode tabulated-list-mode ,title
         ,(format "%s." title)
         (setq tabulated-list-format ,format
               tabulated-list-entries ,rows)
         (tabulated-list-init-header))
       ,@(cl-loop for (k c) in keys collect `(define-key ,(intern (format "%s-map" mode)) (kbd ,k) ,c))
       (with-eval-after-load 'evil (evil-make-overriding-map ,(intern (format "%s-map" mode)) 'normal))
       (defun ,cmd ()
         ,(format "%s." title)
         (interactive)
         (with-current-buffer (get-buffer-create ,buf)
           (,mode)
           (tabulated-list-print)
           (pop-to-buffer (current-buffer)))))))

;;;; Network

(defun +desktop--network-rows ()
  (let ((active (mapcar (lambda (l) (car (split-string l ":")))
                        (+desktop--lines "nmcli" "-t" "-f" "NAME" "connection" "show" "--active")))
        (known (mapcar (lambda (l) (car (split-string l ":")))
                       (+desktop--lines "nmcli" "-t" "-f" "NAME,TYPE" "connection" "show"))))
    (append
     (cl-loop for l in (+desktop--lines "nmcli" "-t" "-f" "IN-USE,SSID,SIGNAL,SECURITY" "device" "wifi" "list")
              for f = (split-string l ":")
              for ssid = (nth 1 f)
              unless (string-empty-p ssid)
              collect (list (list 'wifi ssid)
                            (vector (propertize ssid 'face (if (equal (car f) "*") 'success 'default))
                                    "wifi" (concat (nth 2 f) "%") (or (nth 3 f) "")
                                    (cond ((equal (car f) "*") "connected") ((member ssid known) "known") (t "")))))
     (cl-loop for name in known
              unless (cl-find-if (lambda (l) (string-prefix-p (concat name ":") l))
                                 (+desktop--lines "nmcli" "-t" "-f" "NAME,TYPE" "connection" "show" "--active"))
              collect (list (list 'connection name)
                            (vector name "saved" "" "" "")))
     (cl-loop for name in active
              collect (list (list 'connection name)
                            (vector (propertize name 'face 'success) "active" "" "" "connected"))))))

(defun +desktop-network-connect ()
  "Connect: a known connection comes up; a new Wi-Fi asks its password."
  (interactive)
  (pcase-let ((`(,kind ,name) (or (tabulated-list-get-id) (user-error "Nothing here"))))
    (if (or (eq kind 'connection)
            (member name (mapcar (lambda (l) (car (split-string l ":")))
                                 (+desktop--lines "nmcli" "-t" "-f" "NAME" "connection" "show"))))
        (+desktop--run "nmcli" "connection" "up" name)
      (let ((pw (read-passwd (format "Password for %s (empty if open): " name))))
        (if (string-empty-p pw)
            (+desktop--run "nmcli" "device" "wifi" "connect" name)
          ;; Not on the command line (other processes can read that): a
          ;; connection without the secret, then up with a passwd-file
          ;; only you can read, removed at once.
          (let ((file (make-temp-file "nm-psk")))
            (unwind-protect
                (progn
                  (set-file-modes file #o600)
                  (with-temp-file file (insert "802-11-wireless-security.psk:" pw "\n"))
                  (+desktop--run "nmcli" "connection" "add" "type" "wifi" "ifname" "*" "con-name" name
                                 "ssid" name "wifi-sec.key-mgmt" "wpa-psk")
                  (+desktop--run "nmcli" "connection" "up" name "passwd-file" file))
              (delete-file file))))
        (clear-string pw)))))

(defun +desktop-network-disconnect ()
  "Take the connection down."
  (interactive)
  (pcase-let ((`(,_ ,name) (or (tabulated-list-get-id) (user-error "Nothing here"))))
    (+desktop--run "nmcli" "connection" "down" name)))

(+desktop-define-list network "Network"
  [("Name" 32 t) ("Type" 10 t) ("Signal" 8 t) ("Security" 16 nil) ("State" 0 nil)]
  #'+desktop--network-rows
  ("RET" #'+desktop-network-connect) ("d" #'+desktop-network-disconnect) ("g" #'revert-buffer))

;;;; Bluetooth

(defun +desktop--bt-rows ()
  (cl-loop for l in (+desktop--lines "bluetoothctl" "devices")
           when (string-match "^Device \\([0-9A-F:]+\\) \\(.*\\)$" l)
           collect (let* ((mac (match-string 1 l)) (name (match-string 2 l))
                          (info (string-join (+desktop--lines "bluetoothctl" "info" mac) "\n"))
                          (connected (string-match-p "Connected: yes" info)))
                     (list mac (vector (propertize name 'face (if connected 'success 'default)) mac
                                       (if connected "connected" "")
                                       (if (string-match-p "Paired: yes" info) "paired" "")
                                       (if (string-match "Battery Percentage: [^(]*(\\([0-9]+\\))" info)
                                           (concat (match-string 1 info) "%") ""))))))

(defun +desktop-bt-toggle ()
  "Connect or disconnect the device."
  (interactive)
  (let* ((mac (or (tabulated-list-get-id) (user-error "No device here")))
         (connected (string-match-p "Connected: yes" (string-join (+desktop--lines "bluetoothctl" "info" mac) "\n"))))
    (+desktop--run "bluetoothctl" (if connected "disconnect" "connect") mac)))

(defun +desktop-bt-power ()
  "Turn the Bluetooth controller on or off."
  (interactive)
  (let ((on (cl-some (lambda (l) (string-match-p "Powered: yes" l)) (+desktop--lines "bluetoothctl" "show"))))
    (+desktop--run "bluetoothctl" "power" (if on "off" "on"))))

(+desktop-define-list bluetooth "Bluetooth"
  [("Device" 32 t) ("Address" 20 nil) ("State" 12 t) ("Paired" 8 t) ("Battery" 0 nil)]
  #'+desktop--bt-rows
  ("RET" #'+desktop-bt-toggle) ("p" #'+desktop-bt-power) ("g" #'revert-buffer))

;;;; Audio

(defun +desktop--audio-rows ()
  (let (section out)
    (dolist (l (+desktop--lines "wpctl" "status"))
      (cond ((string-match "\\(Sinks\\|Sources\\):" l) (setq section (match-string 1 l)))
            ((string-match "\\(Filters\\|Streams\\|Devices\\|Clients\\):" l) (setq section nil))
            ((string-match "^Video" l) (setq section nil))
            ((and section (string-match "\\(\\*\\)? *\\([0-9]+\\)\\. \\(.*?\\) *\\[vol: \\([0-9.]+\\)\\( MUTED\\)?\\]" l))
             (push (list (string-to-number (match-string 2 l))
                         (vector (propertize (match-string 3 l) 'face (if (match-string 1 l) 'success 'default))
                                 (if (equal section "Sinks") "output" "input")
                                 (format "%d%%" (round (* 100 (string-to-number (match-string 4 l)))))
                                 (if (match-string 5 l) "muted" "")
                                 (if (match-string 1 l) "default" "")))
                   out))))
    (nreverse out)))

(defun +desktop--audio-id () (number-to-string (or (tabulated-list-get-id) (user-error "No device here"))))
(defun +desktop-audio-default () "Make it the default." (interactive) (+desktop--run "wpctl" "set-default" (+desktop--audio-id)))
(defun +desktop-audio-up () "5% louder." (interactive) (+desktop--run "wpctl" "set-volume" "-l" "1.5" (+desktop--audio-id) "5%+"))
(defun +desktop-audio-down () "5% quieter." (interactive) (+desktop--run "wpctl" "set-volume" (+desktop--audio-id) "5%-"))
(defun +desktop-audio-mute () "Mute or unmute." (interactive) (+desktop--run "wpctl" "set-mute" (+desktop--audio-id) "toggle"))

(+desktop-define-list audio "Audio"
  [("Device" 44 t) ("Kind" 8 t) ("Volume" 8 nil) ("Muted" 7 nil) ("" 0 nil)]
  #'+desktop--audio-rows
  ("RET" #'+desktop-audio-default) ("+" #'+desktop-audio-up) ("-" #'+desktop-audio-down)
  ("=" #'+desktop-audio-up) ("m" #'+desktop-audio-mute) ("g" #'revert-buffer))

;;;; Disks

(defun +desktop--disk-rows ()
  (let ((json (with-temp-buffer
                (call-process "lsblk" nil t nil "-J" "-o" "NAME,PATH,SIZE,TYPE,MOUNTPOINTS,LABEL,FSTYPE,RM")
                (goto-char (point-min))
                (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil)))
        out)
    (cl-labels ((walk (devs depth)
                  (dolist (d devs)
                    (let ((mounts (delq nil (plist-get d :mountpoints))))
                      (push (list (plist-get d :path)
                                  (vector (concat (make-string (* 2 depth) ?\s) (plist-get d :name))
                                          (or (plist-get d :size) "") (or (plist-get d :type) "")
                                          (or (plist-get d :fstype) "") (or (plist-get d :label) "")
                                          (propertize (string-join mounts " ") 'face (if mounts 'success 'shadow))))
                            out))
                    (walk (plist-get d :children) (1+ depth)))))
      (walk (plist-get json :blockdevices) 0))
    (nreverse out)))

(defun +desktop-disk-toggle ()
  "Mount or unmount the filesystem (udisks: your removable ones, no sudo)."
  (interactive)
  (let* ((path (or (tabulated-list-get-id) (user-error "No device here")))
         (mounted (not (string-empty-p (string-trim (aref (tabulated-list-get-entry) 5))))))
    (+desktop--run "udisksctl" (if mounted "unmount" "mount") "-b" path)))

(+desktop-define-list disks "Disks"
  [("Device" 22 t) ("Size" 8 t) ("Type" 6 t) ("Filesystem" 10 t) ("Label" 16 t) ("Mounted at" 0 nil)]
  #'+desktop--disk-rows
  ("RET" #'+desktop-disk-toggle) ("g" #'revert-buffer))

;;;; NixOS generations

(defun +desktop--generation-rows ()
  (let ((gens (with-temp-buffer
                (call-process "nixos-rebuild" nil t nil "list-generations" "--json")
                (goto-char (point-min))
                (ignore-errors (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil)))))
    (mapcar (lambda (g)
              (list (plist-get g :generation)
                    (vector (propertize (number-to-string (plist-get g :generation))
                                        'face (if (plist-get g :current) 'success 'default))
                            (or (plist-get g :date) "") (or (plist-get g :nixosVersion) "")
                            (or (plist-get g :kernelVersion) "") (if (plist-get g :current) "current" ""))))
            gens)))

(defun +desktop--generation-link (n) (format "/nix/var/nix/profiles/system-%d-link" n))

(defun +desktop-generation-diff ()
  "What changed between this generation and the running system."
  (interactive)
  (let* ((n (or (tabulated-list-get-id) (user-error "No generation here")))
         (buf (get-buffer-create (format "*generation %d → current*" n))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "nix store diff-closures generation %d → the running system\n\n" n))
        (call-process "nix" nil t nil "store" "diff-closures" (+desktop--generation-link n) "/run/current-system")
        (ansi-color-apply-on-region (point-min) (point-max))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buf)))

(defun +desktop-generation-rollback ()
  "Switch the system to this generation (asks; sudo -n, so no password prompt)."
  (interactive)
  (let ((n (or (tabulated-list-get-id) (user-error "No generation here"))))
    (when (yes-or-no-p (format "Switch the running system to generation %d? " n))
      (+desktop--run "sudo" "-n" (concat (+desktop--generation-link n) "/bin/switch-to-configuration") "switch"))))

(+desktop-define-list generations "NixOS generations"
  [("Gen" 6 t) ("Built" 20 t) ("NixOS" 26 t) ("Kernel" 10 t) ("" 0 nil)]
  #'+desktop--generation-rows
  ("RET" #'+desktop-generation-diff) ("R" #'+desktop-generation-rollback) ("g" #'revert-buffer))

;;;; Power

(defun +desktop--read (file) (and (file-readable-p file) (string-trim (with-temp-buffer (insert-file-contents file) (buffer-string)))))

;;;###autoload
(defun +desktop/power ()
  "Batteries and AC, from /sys/class/power_supply."
  (interactive)
  (with-current-buffer (get-buffer-create "*Power*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (dir (directory-files "/sys/class/power_supply" t "\\`[^.]"))
        (let ((type (+desktop--read (expand-file-name "type" dir))))
          (insert (propertize (file-name-nondirectory dir) 'face 'bold) (format "  %s\n" type))
          (pcase type
            ("Battery"
             (let ((cap (+desktop--read (expand-file-name "capacity" dir)))
                   (status (+desktop--read (expand-file-name "status" dir)))
                   (full (+desktop--read (expand-file-name "energy_full" dir)))
                   (design (+desktop--read (expand-file-name "energy_full_design" dir)))
                   (now (+desktop--read (expand-file-name "power_now" dir))))
               (insert (format "  %s%%, %s" cap status)
                       (if (and full design) (format ", health %d%%" (round (* 100.0 (/ (string-to-number full) (float (max 1 (string-to-number design))))))) "")
                       (if (and now (> (string-to-number now) 0)) (format ", drawing %.1f W" (/ (string-to-number now) 1e6)) "")
                       "\n\n")))
            ("Mains" (insert (format "  %s\n\n" (if (equal (+desktop--read (expand-file-name "online" dir)) "1") "connected" "unplugged"))))
            (_ (insert "\n")))))
      (special-mode))
    ;; A keymap of its own: the mode's is shared by every buffer in it.
    (use-local-map (make-composed-keymap nil (current-local-map)))
    (local-set-key "g" #'+desktop/power)
    (pop-to-buffer (current-buffer))))

;;;; The menu

(transient-define-prefix +desktop-menu ()
  "The machine: network, Bluetooth, audio, disks, generations, power, and more."
  [["Devices"
    ("n" "network" +desktop/network) ("b" "Bluetooth" +desktop/bluetooth) ("a" "audio" +desktop/audio)
    ("d" "disks" +desktop/disks) ("p" "power" +desktop/power)]
   ["System"
    ("g" "NixOS generations" +desktop/generations) ("s" "systemd units" +systemd/units)
    ("j" "journal" +journal) ("k" "processes" proced)]
   ["Desktop"
    ("h" "Hyprland windows" +hyprland/windows) ("t" "Tailscale" +tailscale/peers)]])

(map! :leader :desc "System" "o y" #'+desktop-menu)

(provide '+desktop)
;;; +desktop.el ends here
