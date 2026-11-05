;;; familiar-peers.el --- Message your running Claude Code sessions from Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Wolfhard Prell
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Claude Code sessions on this machine message each other (their
;; ListAgents / SendMessage tools) over local Unix sockets.  Emacs speaks
;; the same protocol, so it can write to any of your sessions directly:
;; no terminal, no tmux, no keystrokes into a window.
;;
;;   M-x familiar-peers         the live sessions: name, status (busy, idle,
;;                              waiting for you), where they work; RET writes
;;                              to one
;;   M-x familiar-peers-send    write to a session (compose buffer, C-c C-c)
;;   M-x familiar-peers-send-region / -heading
;;                              send the region, or the Org item at point
;;                              with a link to it ("I filed this, have a look")
;;
;; How (read from Claude Code 2.1.314): each session registers
;; ~/.claude/sessions/PID.json (name, cwd, status, messagingSocketPath) and
;; PID.<hash>.key (its peerToken, readable only by you).  A sender connects
;; to the socket, writes {"type":"auth","token":…} on one line and the
;; message on the next:
;;   {"msgV":1,"msg_id":UUID,"type":"user","priority":"next",
;;    "message":{"role":"user","content":"<cross-session-message …>…"}}
;; The session gets it as a message from "Emacs", like one from a peer.
;; A busy session reads it at its next turn boundary (after the tool call
;; it is running), not at once: a quiet minute is normal, not a loss.
;; Emacs has no inbox of its own: the message asks for replies through
;; emacsclient.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'tabulated-list)

(defgroup familiar-peers nil
  "Messaging Claude Code sessions from Emacs."
  :group 'familiar)

(defcustom familiar-peers-directory (expand-file-name "~/.claude/sessions/")
  "Where Claude Code sessions register themselves."
  :type 'directory)

(defcustom familiar-peers-sender-name "Emacs"
  "How messages from here are signed (from-name)."
  :type 'string)

(defcustom familiar-peers-reply-hint
  "(Sent from the user's Emacs; Emacs has no inbox: answer by writing into a new Emacs buffer with emacsclient, and say so in the echo area.)"
  "Appended to every message, so the session knows how to answer."
  :type 'string)

(defconst familiar-peers--protocol 1 "The message version (msgV) spoken here.")

;;;; Sessions

(defun familiar-peers--read-json (file)
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (json-parse-buffer :object-type 'plist :null-object nil :false-object nil))))

(defun familiar-peers--alive-p (pid)
  (and (integerp pid) (process-attributes pid) t))

(defun familiar-peers-list ()
  "Live Claude Code sessions: plists with :pid :name :cwd :status :kind :socket."
  (cl-loop for file in (directory-files familiar-peers-directory t "\\`[0-9]+\\.json\\'")
           for s = (familiar-peers--read-json file)
           for pid = (plist-get s :pid)
           for socket = (plist-get s :messagingSocketPath)
           when (and s (familiar-peers--alive-p pid) (stringp socket) (file-exists-p socket)
                     (not (plist-get s :spare)) (not (plist-get s :parkedJobId)))
           collect (list :pid pid :name (or (plist-get s :name) (format "session %d" pid))
                         :cwd (plist-get s :cwd) :status (plist-get s :status)
                         :waiting (plist-get s :waitingFor) :kind (plist-get s :kind)
                         :socket socket :updated (plist-get s :updatedAt))))

(defun familiar-peers--token (pid)
  "The peerToken of session PID (from its key file, readable only by you)."
  (when-let* ((file (car (directory-files familiar-peers-directory t (format "\\`%d\\.[0-9a-f]+\\.key\\'" pid))))
              (key (familiar-peers--read-json file)))
    (plist-get key :peerToken)))

;;;; Sending

(defun familiar-peers--uuid ()
  (let ((b (mapcar (lambda (_) (random 256)) (make-list 16 0))))
    (setf (nth 6 b) (logior #x40 (logand (nth 6 b) #x0f))
          (nth 8 b) (logior #x80 (logand (nth 8 b) #x3f)))
    (apply #'format "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" b)))

(defun familiar-peers--envelope (text)
  "TEXT as a cross-session message from Emacs."
  (format "<cross-session-message from-name=\"%s\">\n%s\n</cross-session-message>"
          (replace-regexp-in-string "[\"<>]" "" familiar-peers-sender-name)
          ;; Its own closing tag would end the envelope early.
          (replace-regexp-in-string "</cross-session-message" "<\\/cross-session-message" text t t)))

(defun familiar-peers--wire (token text)
  "The two lines sent for TEXT with TOKEN."
  (concat (json-serialize (list :type "auth" :token token)) "\n"
          (json-serialize (list :msgV familiar-peers--protocol :msg_id (familiar-peers--uuid)
                                :type "user"
                                :message (list :role "user" :content (familiar-peers--envelope text))
                                :priority "next"))
          "\n"))

(defun familiar-peers-send-text (peer text)
  "Send TEXT to PEER (a plist from `familiar-peers-list').  t when written."
  (let ((token (or (familiar-peers--token (plist-get peer :pid))
                   (user-error "No key for session %s (is it still running?)" (plist-get peer :name))))
        (proc (make-network-process :name "familiar-peer" :family 'local :service (plist-get peer :socket)
                                    :noquery t :coding 'utf-8)))
    (unwind-protect
        (progn (process-send-string proc (familiar-peers--wire token (concat text "\n\n" familiar-peers-reply-hint)))
               (process-send-eof proc)
               t)
      (run-at-time 0.3 nil (lambda () (when (process-live-p proc) (delete-process proc)))))))

(defun familiar-peers--read-peer (&optional prompt)
  (let* ((peers (or (familiar-peers-list) (user-error "No Claude Code session is running")))
         (label (lambda (p) (format "%s  [%s]  %s" (plist-get p :name) (or (plist-get p :status) "?")
                                    (abbreviate-file-name (or (plist-get p :cwd) "")))))
         (choice (completing-read (or prompt "To session: ") (mapcar label peers) nil t)))
    (cl-find choice peers :key label :test #'equal)))

;;;; Commands

(defvar-local familiar-peers--target nil "The session this compose buffer writes to.")

(defvar-keymap familiar-peers-compose-mode-map
  "C-c C-c" #'familiar-peers-compose-send  "C-c C-k" #'familiar-peers-compose-cancel)

(define-minor-mode familiar-peers-compose-mode
  "Writing to a Claude Code session: C-c C-c sends, C-c C-k drops."
  :lighter " ✉Claude")

;;;###autoload
(defun familiar-peers-send (peer &optional initial)
  "Write to Claude Code session PEER (asked) in a buffer; INITIAL text to start."
  (interactive (list (familiar-peers--read-peer)))
  (let ((buf (generate-new-buffer (format "*to %s*" (plist-get peer :name)))))
    (with-current-buffer buf
      (if (fboundp 'markdown-mode) (markdown-mode) (text-mode))
      (familiar-peers-compose-mode 1)
      (setq familiar-peers--target peer)
      (setq-local header-line-format
                  (list " " (propertize (format "To %s" (plist-get peer :name)) 'face 'bold)
                        (propertize (format "  (%s, %s)   C-c C-c send · C-c C-k drop"
                                            (or (plist-get peer :status) "?")
                                            (abbreviate-file-name (or (plist-get peer :cwd) "")))
                                    'face 'shadow)))
      (when initial (insert initial)))
    (pop-to-buffer buf)
    (when (fboundp 'evil-insert-state) (evil-insert-state))))

(defun familiar-peers-compose-send ()
  "Send this buffer to its session."
  (interactive)
  (let ((text (string-trim (buffer-string))) (peer familiar-peers--target))
    (when (string-empty-p text) (user-error "Nothing written"))
    (familiar-peers-send-text peer text)
    (message "Sent to %s (%d characters)" (plist-get peer :name) (length text))
    (set-buffer-modified-p nil)
    (kill-buffer)))

(defun familiar-peers-compose-cancel ()
  "Drop this message."
  (interactive)
  (when (or (string-empty-p (string-trim (buffer-string))) (y-or-n-p "Drop this message? "))
    (set-buffer-modified-p nil) (kill-buffer)))

;;;###autoload
(defun familiar-peers-send-region (beg end)
  "Send the region BEG..END to a session (asked), saying where it is from."
  (interactive "r")
  (let ((peer (familiar-peers--read-peer))
        (where (if buffer-file-name (format "%s:%d" (abbreviate-file-name buffer-file-name) (line-number-at-pos beg))
                 (buffer-name))))
    (familiar-peers-send-text peer (format "From %s:\n\n%s" where (buffer-substring-no-properties beg end)))
    (message "Sent %d characters to %s" (- end beg) (plist-get peer :name))))

(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-end-of-subtree "org" (&optional invisible-ok to-heading element))

;;;###autoload
(defun familiar-peers-send-heading ()
  "Tell a session about the Org item at point: its heading, text and link.
The compose buffer starts with it, so you can add a word before sending."
  (interactive)
  (let* ((file (or buffer-file-name (user-error "Not a file")))
         (item (save-excursion
                 (org-back-to-heading t)
                 (let ((beg (point)) (title (org-get-heading t t t t)))
                   (list title (line-number-at-pos)
                         (buffer-substring-no-properties beg (save-excursion (org-end-of-subtree t t) (point))))))))
    (familiar-peers-send (familiar-peers--read-peer)
                         (format "New in %s (line %d): \"%s\" — please have a look.\n\n%s"
                                 (abbreviate-file-name file) (nth 1 item) (nth 0 item)
                                 (string-trim (nth 2 item))))))

;;;; The list

(defvar-keymap familiar-peers-mode-map
  :parent tabulated-list-mode-map
  "RET" #'familiar-peers-write-at-point  "g" #'familiar-peers)

(define-derived-mode familiar-peers-mode tabulated-list-mode "Claude sessions"
  "Your running Claude Code sessions."
  (setq tabulated-list-format [("Session" 34 t) ("Status" 16 t) ("Kind" 12 t) ("Where" 0 t)])
  (tabulated-list-init-header))

(defun familiar-peers-write-at-point ()
  "Write to the session at point."
  (interactive)
  (familiar-peers-send (or (tabulated-list-get-id) (user-error "No session here"))))

;;;###autoload
(defun familiar-peers ()
  "Your running Claude Code sessions; RET writes to one."
  (interactive)
  (with-current-buffer (get-buffer-create "*Claude sessions*")
    (familiar-peers-mode)
    (setq tabulated-list-entries
          (mapcar (lambda (p)
                    (list p (vector (plist-get p :name)
                                    (let ((s (or (plist-get p :status) "?")))
                                      (propertize (if (plist-get p :waiting) (format "%s: %s" s (plist-get p :waiting)) s)
                                                  'face (pcase s ("busy" 'warning) ("waiting" 'error) ("idle" 'success) (_ 'default))))
                                    (or (plist-get p :kind) "")
                                    (abbreviate-file-name (or (plist-get p :cwd) "")))))
                  (familiar-peers-list)))
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

(provide 'familiar-peers)
;;; familiar-peers.el ends here
