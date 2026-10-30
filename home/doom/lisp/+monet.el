;;; lisp/+monet.el --- Claude Code in any terminal sees this Emacs -*- lexical-binding: t; -*-
;;
;; monet implements Claude Code's IDE protocol: an attached Claude sees your
;; selection and flycheck/flymake diagnostics, opens files here, and shows
;; its edits as diffs in Emacs.  It attaches through a lock file in
;; ~/.claude/ide/ naming the project folder, but monet only writes one when
;; Claude is started from Emacs (claude-code.el).  You run Claude Code in
;; kitty, so it never found Emacs.
;;
;; This starts one monet session per project root as soon as you visit a
;; file there.  Claude Code's `autoConnectIde' (on in ~/.claude.json) then
;; attaches automatically when you start `claude' in that project; `/ide'
;; in Claude Code shows it.  The server listens on localhost only, and the
;; per-session token in the lock file is enforced here (monet itself never
;; checks it).  When a Claude exits, the project is offered again; monet
;; removes the lock files when Emacs exits.
;;
;;   M-x monet-list-sessions   what is running
;;   M-x +monet-auto-start-mode   toggle (on by default)
;;
;;; Code:

(require 'cl-lib)

(defvar monet--sessions)
(defvar +monet-auto-start-mode)
(declare-function monet-start-server-in-directory "ext:monet" (key directory))
(declare-function monet--session-directory "ext:monet" (session))

(defun +monet--root ()
  "This buffer's local project root, or nil."
  (and buffer-file-name
       (not (file-remote-p default-directory))
       (fboundp 'doom-project-root)
       (doom-project-root)))

(defun +monet--skip-p (root)
  "Non-nil for roots that are not worth a session."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (or (string-prefix-p "/nix/store/" root)
        (equal root (file-name-as-directory (expand-file-name "~"))))))

(defun +monet-session-for (root)
  "The monet session serving ROOT, if any."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (cl-loop for s being the hash-values of monet--sessions
             when (equal root (file-name-as-directory
                               (expand-file-name (monet--session-directory s))))
             return s)))

(defun +monet--key (root)
  "A session key for ROOT, unique among running sessions."
  (let* ((base (file-name-nondirectory (directory-file-name root)))
         (key base) (n 1))
    (while (gethash key monet--sessions)
      (setq key (format "%s<%d>" base (cl-incf n))))
    key))

(defun +monet-ensure-session-h ()
  "Start a monet session for this buffer's project unless one runs."
  (when-let* (((bound-and-true-p monet-mode))
              (root (+monet--root))
              ((not (+monet--skip-p root)))
              ((not (+monet-session-for root))))
    (condition-case err
        (monet-start-server-in-directory (+monet--key root) root)
      (error (message "monet: no session for %s: %s" root (error-message-string err))))))

;;;; Enforce the lock file's token

;; monet writes an auth token into each lock file but never checks it (no
;; reference to the header in monet ee2e355); a wrong token still gets
;; "101 Switching Protocols".  Claude Code sends it as
;; "X-Claude-Code-Ide-Authorization: <authToken>" (checked in the 2.1.226
;; bundle), so connections without it are refused here.  websocket.el parses
;; the handshake and then calls monet's on-open synchronously, so the headers
;; stashed by the first advice belong to the connection the second one sees.

(declare-function monet--session-auth-token "ext:monet" (session))
(declare-function websocket-close "ext:websocket" (websocket))

(defvar +monet--handshake nil "Raw headers of the handshake being accepted.")
(defvar +monet--refused (make-hash-table :test #'eq :weakness 'key)
  "Websockets refused for a bad token; their close must not end the session.")

(defun +monet--stash-handshake-a (fn output)
  "Around `websocket-verify-client-headers' (FN): remember OUTPUT."
  (setq +monet--handshake output)
  (funcall fn output))

(defun +monet-token-ok-p (headers token)
  "Non-nil if raw HEADERS carry TOKEN in Claude Code's IDE auth header."
  (and (stringp headers) (stringp token)
       (let ((case-fold-search t))
         (string-match-p (concat "^x-claude-code-ide-authorization:[ \t]*"
                                 (regexp-quote token) "[ \t]*\r?$")
                         headers))))

(defun +monet--check-token-a (fn session ws)
  "Around `monet--on-open-server' (FN): refuse WS unless it sent SESSION's token."
  (if (+monet-token-ok-p +monet--handshake (monet--session-auth-token session))
      (funcall fn session ws)
    (puthash ws t +monet--refused)
    (message "monet: refused an IDE connection without the session token")
    (websocket-close ws)))

(defun +monet--on-close-a (fn session ws)
  "Around `monet--on-close-server' (FN): keep SESSION when WS was refused;
after a real Claude leaves, offer the project again."
  (if (gethash ws +monet--refused)
      (remhash ws +monet--refused)
    (let ((dir (monet--session-directory session)))
      (funcall fn session ws)
      (when +monet-auto-start-mode
        (run-at-time 1 nil #'+monet--rearm dir)))))

(defun +monet--rearm (dir)
  "Start a fresh session for DIR if a buffer still visits a file there."
  (when (and (bound-and-true-p monet-mode) (not (+monet-session-for dir)))
    (when-let* ((buf (seq-find (lambda (b)
                                 (let ((f (buffer-file-name b)))
                                   (and f (file-in-directory-p f dir))))
                               (buffer-list))))
      (with-current-buffer buf (+monet-ensure-session-h)))))

;;;###autoload
(define-minor-mode +monet-auto-start-mode
  "Start a monet session for each project you visit, for Claude Code in a terminal."
  :global t
  :group 'tools
  (if +monet-auto-start-mode
      (progn
        (add-hook 'find-file-hook #'+monet-ensure-session-h)
        ;; Projects already open get theirs now.
        (dolist (buf (buffer-list))
          (with-current-buffer buf (+monet-ensure-session-h))))
    (remove-hook 'find-file-hook #'+monet-ensure-session-h)))

(with-eval-after-load 'websocket
  (advice-add 'websocket-verify-client-headers :around #'+monet--stash-handshake-a))

(with-eval-after-load 'monet
  (advice-add 'monet--on-open-server :around #'+monet--check-token-a)
  (advice-add 'monet--on-close-server :around #'+monet--on-close-a)
  (unless noninteractive (+monet-auto-start-mode 1)))

(provide '+monet)
;;; +monet.el ends here
