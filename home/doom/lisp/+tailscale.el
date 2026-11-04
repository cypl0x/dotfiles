;;; lisp/+tailscale.el --- Your tailnet, in Emacs -*- lexical-binding: t; -*-
;;
;; From the task list: view and inspect peers, configure the daemon from a
;; transient, read its logs.  No package did this; it's `tailscale' itself
;; (you are its operator here, so no sudo) and journald.
;;
;;   SPC o n   the peers: name, address, OS, online or last seen, how it's
;;             reached (direct address or DERP relay), exit node
;;     RET   its home directory over TRAMP      p   tailscale ping it
;;     s     a shell there (ssh, in ghostel)    w   copy its address
;;     e     route through it (exit node)       E   stop routing through one
;;     l     tailscaled's log, following        g   refresh
;;     m     the settings menu (also ? )
;;
;; The menu shows the daemon's settings as they are and toggles them with
;; `tailscale set': accept routes, shields up, Tailscale SSH, exit node,
;; LAN access while on one, advertise this machine as one; and up / down.
;;
;;; Code:

(require 'cl-lib)
(require 'tabulated-list)
(require 'transient)

(defvar +tailscale-program (executable-find "tailscale"))

(defun +tailscale--json (&rest args)
  "`tailscale ARGS --json', parsed (plists, lists)."
  (with-temp-buffer
    (unless (zerop (apply #'call-process +tailscale-program nil t nil args))
      (user-error "tailscale %s: %s" (string-join args " ") (string-trim (buffer-string))))
    (goto-char (point-min))
    (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil)))

(defun +tailscale--run (&rest args)
  "Run `tailscale ARGS', say what it said, refresh the peer list."
  (with-temp-buffer
    (let ((status (apply #'call-process +tailscale-program nil t nil args)))
      (message "tailscale %s%s" (string-join args " ")
               (let ((out (string-trim (buffer-string))))
                 (cond ((not (zerop status)) (concat ": " out))
                       ((string-empty-p out) ": done")
                       (t (concat ": " out)))))))
  (when-let* ((buf (get-buffer "*tailscale*")))
    (with-current-buffer buf (revert-buffer))))

;;;; Peers

(defun +tailscale--seen (peer)
  (let ((seen (plist-get peer :LastSeen)))
    (cond ((plist-get peer :Online) "online")
          ((or (null seen) (string-prefix-p "0001" seen)) "never")
          (t (let ((days (/ (float-time (time-subtract nil (date-to-time seen))) 86400)))
               (cond ((< days 1) "today")
                     ((< days 2) "yesterday")
                     (t (format "%d days ago" days))))))))

(defun +tailscale--how (peer)
  (cond ((not (plist-get peer :Online)) "")
        ((let ((addr (plist-get peer :CurAddr))) (and addr (not (string-empty-p addr))))
         (concat "direct " (plist-get peer :CurAddr)))
        ((plist-get peer :Relay) (concat "relay " (plist-get peer :Relay)))
        (t "")))

(defun +tailscale--rows ()
  (let ((status (+tailscale--json "status" "--json")))
    (mapcar (lambda (peer)
              (list peer
                    (vector (propertize (plist-get peer :HostName)
                                        'face (if (plist-get peer :Online) 'success 'shadow))
                            (or (car (plist-get peer :TailscaleIPs)) "")
                            (or (plist-get peer :OS) "")
                            (+tailscale--seen peer)
                            (+tailscale--how peer)
                            (cond ((plist-get peer :ExitNode) "← in use")
                                  ((plist-get peer :ExitNodeOption) "offered")
                                  (t "")))))
            (sort (let (peers)
                    (cl-loop for (_k v) on (plist-get status :Peer) by #'cddr do (push v peers))
                    peers)
                  (lambda (a b)
                    (if (eq (and (plist-get a :Online) t) (and (plist-get b :Online) t))
                        (string< (plist-get a :HostName) (plist-get b :HostName))
                      (plist-get a :Online)))))))

(defun +tailscale--peer ()
  (or (tabulated-list-get-id) (user-error "No peer here")))

(defun +tailscale--address (peer)
  (car (plist-get peer :TailscaleIPs)))

(defun +tailscale-dired ()
  "The peer's home directory over TRAMP (ssh)."
  (interactive)
  (dired (format "/ssh:%s:~/" (+tailscale--address (+tailscale--peer)))))

(defun +tailscale-shell ()
  "An ssh session to the peer, in a terminal buffer."
  (interactive)
  (let ((host (+tailscale--address (+tailscale--peer))))
    (if (fboundp 'ghostel)
        (let ((default-directory (format "/ssh:%s:~/" host)))
          (call-interactively #'ghostel))
      (async-shell-command (format "ssh %s" host)))))

(defun +tailscale-ping ()
  "`tailscale ping' the peer, in a buffer: direct or relayed, and how fast."
  (interactive)
  (let* ((peer (+tailscale--peer))
         (buf (get-buffer-create (format "*tailscale ping %s*" (plist-get peer :HostName)))))
    (with-current-buffer buf (let ((inhibit-read-only t)) (erase-buffer)))
    (make-process :name "tailscale-ping" :buffer buf :noquery t
                  :command (list +tailscale-program "ping" "--c" "5"
                                 (+tailscale--address peer)))
    (display-buffer buf)))

(defun +tailscale-copy ()
  "Copy the peer's Tailscale address."
  (interactive)
  (let ((addr (+tailscale--address (+tailscale--peer))))
    (kill-new addr)
    (message "Copied %s" addr)))

(defun +tailscale-use-exit-node ()
  "Route this machine's traffic through the peer."
  (interactive)
  (let ((peer (+tailscale--peer)))
    (unless (plist-get peer :ExitNodeOption)
      (user-error "%s doesn't offer itself as an exit node" (plist-get peer :HostName)))
    (+tailscale--run "set" (concat "--exit-node=" (+tailscale--address peer)))))

(defun +tailscale-no-exit-node ()
  "Stop routing through an exit node."
  (interactive)
  (+tailscale--run "set" "--exit-node="))

(defun +tailscale/log ()
  "tailscaled's log, following."
  (interactive)
  (let ((buf (get-buffer-create "*tailscaled log*")))
    (unless (get-buffer-process buf)
      (with-current-buffer buf (let ((inhibit-read-only t)) (erase-buffer)))
      (make-process :name "tailscaled-log" :buffer buf :noquery t
                    :command '("journalctl" "-u" "tailscaled" "-n" "300" "-f" "--no-pager")))
    (pop-to-buffer buf)
    (goto-char (point-max))))

(defvar +tailscale-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'+tailscale-dired)
    (define-key map "s" #'+tailscale-shell)
    (define-key map "p" #'+tailscale-ping)
    (define-key map "w" #'+tailscale-copy)
    (define-key map "e" #'+tailscale-use-exit-node)
    (define-key map "E" #'+tailscale-no-exit-node)
    (define-key map "l" #'+tailscale/log)
    (define-key map "m" #'+tailscale-menu)
    (define-key map "?" #'+tailscale-menu)
    map))

(define-derived-mode +tailscale-mode tabulated-list-mode "Tailscale"
  "Your tailnet's peers."
  (setq tabulated-list-format [("Peer" 16 t) ("Address" 16 t) ("OS" 8 t)
                               ("Seen" 12 t) ("Reached" 28 nil) ("Exit node" 0 nil)]
        tabulated-list-entries #'+tailscale--rows)
  (tabulated-list-init-header))

;;;###autoload
(defun +tailscale/peers ()
  "Your tailnet: peers, how they're reached, and what to do with them."
  (interactive)
  (unless +tailscale-program (user-error "tailscale isn't installed"))
  (with-current-buffer (get-buffer-create "*tailscale*")
    (+tailscale-mode)
    (tabulated-list-print)
    (let ((status (+tailscale--json "status" "--json")))
      (setq header-line-format
            (format " %s on %s (%s)   RET files · s shell · p ping · e exit node · l log · m settings"
                    (plist-get (plist-get status :Self) :HostName)
                    (plist-get (plist-get status :CurrentTailnet) :Name)
                    (plist-get status :BackendState))))
    (pop-to-buffer (current-buffer))))

;;;; Settings

(defvar +tailscale--prefs nil "The daemon's settings when the menu opened.")

(defun +tailscale--pref (key)
  (plist-get +tailscale--prefs key))

(defun +tailscale--toggle (flag key)
  "A suffix that flips boolean setting KEY with `tailscale set --FLAG'."
  (lambda ()
    (interactive)
    (+tailscale--run "set" (format "--%s=%s" flag (if (+tailscale--pref key) "false" "true")))))

(defun +tailscale--state (key)
  (if (+tailscale--pref key) (propertize "on" 'face 'success) (propertize "off" 'face 'shadow)))

(transient-define-prefix +tailscale-menu ()
  "Tailscale's settings on this machine, as they are; each key changes one."
  [:description
   (lambda ()
     (setq +tailscale--prefs (+tailscale--json "debug" "prefs"))
     (format "Tailscale on %s (operator: %s)" (system-name)
             (or (+tailscale--pref :OperatorUser) "root")))
   ["Routing"
    ("r" (lambda () (format "accept subnet routes   %s" (+tailscale--state :RouteAll)))
     (lambda () (interactive) (funcall (+tailscale--toggle "accept-routes" :RouteAll))))
    ("x" (lambda () (format "exit node   %s"
                            (let ((id (+tailscale--pref :ExitNodeID)))
                              (if (and id (not (string-empty-p id))) (propertize id 'face 'success)
                                (propertize "none" 'face 'shadow)))))
     +tailscale-set-exit-node)
    ("L" (lambda () (format "LAN access on an exit node   %s" (+tailscale--state :ExitNodeAllowLANAccess)))
     (lambda () (interactive) (funcall (+tailscale--toggle "exit-node-allow-lan-access" :ExitNodeAllowLANAccess))))
    ("a" (lambda () (format "offer this machine as exit node   %s"
                            (if (member "0.0.0.0/0" (+tailscale--pref :AdvertiseRoutes))
                                (propertize "on" 'face 'success) (propertize "off" 'face 'shadow))))
     (lambda () (interactive)
       (+tailscale--run "set" (format "--advertise-exit-node=%s"
                                      (if (member "0.0.0.0/0" (+tailscale--pref :AdvertiseRoutes))
                                          "false" "true")))))]
   ["Security"
    ("S" (lambda () (format "shields up (no incoming)   %s" (+tailscale--state :ShieldsUp)))
     (lambda () (interactive) (funcall (+tailscale--toggle "shields-up" :ShieldsUp))))
    ("h" (lambda () (format "Tailscale SSH server   %s" (+tailscale--state :RunSSH)))
     (lambda () (interactive) (funcall (+tailscale--toggle "ssh" :RunSSH))))]
   ["Connection"
    ("u" "up" (lambda () (interactive) (+tailscale--run "up")))
    ("d" "down" (lambda () (interactive) (+tailscale--run "down")))
    ("l" "daemon log" +tailscale/log)
    ("p" "peers" +tailscale/peers)]])

(defun +tailscale-set-exit-node ()
  "Pick an exit node from the peers that offer one (or none)."
  (interactive)
  (let* ((status (+tailscale--json "status" "--json"))
         (offers (cl-loop for (_k p) on (plist-get status :Peer) by #'cddr
                          when (plist-get p :ExitNodeOption)
                          collect (cons (format "%s  %s%s" (plist-get p :HostName)
                                                (car (plist-get p :TailscaleIPs))
                                                (if (plist-get p :Online) "" "  (offline)"))
                                        (car (plist-get p :TailscaleIPs)))))
         (pick (completing-read "Exit node: " (cons "none" (mapcar #'car offers)) nil t)))
    (+tailscale--run "set" (concat "--exit-node=" (or (cdr (assoc pick offers)) "")))))

(map! :leader :desc "Tailscale peers" "o n" #'+tailscale/peers)

(provide '+tailscale)
;;; +tailscale.el ends here
