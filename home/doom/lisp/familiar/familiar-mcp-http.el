;;; familiar-mcp-http.el --- familiar's MCP server over HTTP, inside Emacs -*- lexical-binding: t; -*-
;;
;; The MCP Streamable HTTP transport (spec 2025-06-18), served by Emacs
;; itself: an agent attaches with a URL instead of the stdio script, which
;; starts an emacsclient for every message.  The tools are the ones
;; mcp-server-lib serves for familiar (`familiar-mcp-start').
;;
;;   M-x familiar-mcp-http-start   serve on 127.0.0.1:`familiar-mcp-http-port'
;;   M-x familiar-mcp-http-stop
;;   claude mcp add --transport http emacs http://127.0.0.1:PORT/mcp \
;;     --header "Authorization: Bearer $(cat ~/.local/state/emacs/familiar-mcp-http-token)"
;;
;; What the spec asks of a minimal server, and this does:
;; - one endpoint, /mcp; POST carries one JSON-RPC message
;; - a request is answered with one application/json object; a notification
;;   or response with 202 and no body
;; - GET and DELETE: 405 (no server-initiated stream, no sessions to end)
;; - an unknown MCP-Protocol-Version header: 400
;; - the Origin header is checked (DNS rebinding): only localhost passes
;; - bound to 127.0.0.1; every request needs the bearer token, kept in a
;;   0600 file so a restart doesn't change it
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function mcp-server-lib-process-jsonrpc "ext:mcp-server-lib" (json-string server-id))
(declare-function familiar-mcp-start "familiar-mcp" ())

(defgroup familiar-mcp-http nil
  "familiar's MCP server over HTTP."
  :group 'familiar)

(defcustom familiar-mcp-http-port 39391
  "Port on 127.0.0.1.  Fixed, so an agent's configuration keeps working."
  :type 'natnum)

(defcustom familiar-mcp-http-token-file
  (expand-file-name "emacs/familiar-mcp-http-token"
                    (or (getenv "XDG_STATE_HOME") "~/.local/state"))
  "Where the bearer token is kept (mode 0600)."
  :type 'file)

(defcustom familiar-mcp-http-server-id "familiar"
  "mcp-server-lib server whose tools are served."
  :type 'string)

(defvar familiar-mcp-http-protocol-versions '("2024-11-05" "2025-03-26" "2025-06-18" "2025-11-25")
  "MCP-Protocol-Version values accepted; others get 400.")

(defvar familiar-mcp-http-process-function #'mcp-server-lib-process-jsonrpc
  "Called with a JSON-RPC string and the server id; returns the response
string, or nil/\"\" for notifications.")

(defvar familiar-mcp-http--server nil "The listening process.")

(defvar familiar-mcp-http-routes nil
  "Alist PATH-PREFIX → HANDLER for endpoints besides /mcp (same token).
HANDLER is called with METHOD PATH HEADERS BODY and returns
(STATUS EXTRA-HEADERS BODY), (:async FN) where FN is called with a
function taking those three, or (:sse FN) where FN is called with SEND
(one event's data) and CLOSE.  nil passes the request on.")

;;;; Token

(defun familiar-mcp-http-token ()
  "The bearer token, created on first use."
  (if (file-readable-p familiar-mcp-http-token-file)
      (string-trim (with-temp-buffer
                     (insert-file-contents familiar-mcp-http-token-file)
                     (buffer-string)))
    (let ((token (secure-hash 'sha256 (format "%s%s%s" (random t) (float-time) (emacs-pid)))))
      (make-directory (file-name-directory familiar-mcp-http-token-file) t)
      (with-file-modes #o600
        (with-temp-file familiar-mcp-http-token-file (insert token "\n")))
      token)))

(defun familiar-mcp-http--token-ok-p (header)
  "Whether the Authorization HEADER carries the token."
  (and header
       (string-match "\\`Bearer[ \t]+\\(\\S-+\\)" header)
       ;; Compare digests: the time taken doesn't depend on the token.
       (equal (secure-hash 'sha256 (match-string 1 header))
              (secure-hash 'sha256 (familiar-mcp-http-token)))))

;;;; Requests

(defun familiar-mcp-http--parse (raw)
  "RAW bytes of an HTTP request: (METHOD PATH HEADERS BODY), or nil if
incomplete.  HEADERS is an alist with downcased names; BODY is decoded
UTF-8.  `:bad' when it can never become a request."
  (when-let* ((end (string-search "\r\n\r\n" raw)))
    (let* ((lines (split-string (substring raw 0 end) "\r\n"))
           (start (split-string (car lines) " "))
           (headers (delq nil (mapcar (lambda (l)
                                        (when (string-match "\\`\\([^:]+\\):[ \t]*\\(.*\\)\\'" l)
                                          (cons (downcase (match-string 1 l)) (match-string 2 l))))
                                      (cdr lines))))
           (length (string-to-number (or (alist-get "content-length" headers nil nil #'equal) "0")))
           (body-start (+ end 4)))
      (cond ((/= (length start) 3) :bad)
            ((< (- (length raw) body-start) length) nil)   ; body still arriving
            (t (list (nth 0 start) (nth 1 start) headers
                     (decode-coding-string (substring raw body-start (+ body-start length)) 'utf-8)))))))

(defun familiar-mcp-http--origin-ok-p (origin)
  "Whether ORIGIN (or its absence: not a browser) may talk to us."
  (or (null origin)
      (string-match-p "\\`https?://\\(?:localhost\\|127\\.0\\.0\\.1\\|\\[::1\\]\\)\\(?::[0-9]+\\)?\\'" origin)))

(defun familiar-mcp-http-respond (method path headers body)
  "The response to an HTTP request: (STATUS EXTRA-HEADERS BODY-STRING)."
  (let ((header (lambda (name) (alist-get name headers nil nil #'equal))))
    (cond
     ((not (familiar-mcp-http--origin-ok-p (funcall header "origin")))
      (list 403 nil "Forbidden origin"))
     ((not (familiar-mcp-http--token-ok-p (funcall header "authorization")))
      (list 401 '(("WWW-Authenticate" . "Bearer")) "Unauthorized"))
     ((when-let* ((route (seq-find (lambda (r) (string-prefix-p (car r) path))
                                   familiar-mcp-http-routes)))
        (funcall (cdr route) method path headers body)))
     ((not (equal (car (split-string path "?")) "/mcp"))
      (list 404 nil "Not found"))
     ((member method '("GET" "DELETE"))
      (list 405 '(("Allow" . "POST")) ""))
     ((not (equal method "POST"))
      (list 405 '(("Allow" . "POST")) ""))
     ((let ((v (funcall header "mcp-protocol-version")))
        (and v (not (member v familiar-mcp-http-protocol-versions))))
      (list 400 nil "Unsupported MCP-Protocol-Version"))
     (t
      (let ((message (ignore-errors (json-parse-string body :object-type 'alist))))
        (cond
         ((not (consp message))
          (list 400 '(("Content-Type" . "application/json"))
                "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}"))
         ;; A notification or a response: accepted, nothing to say.
         ((not (and (assq 'method message) (assq 'id message)))
          (funcall familiar-mcp-http-process-function body familiar-mcp-http-server-id)
          (list 202 nil ""))
         (t
          (list 200 '(("Content-Type" . "application/json"))
                (or (funcall familiar-mcp-http-process-function body familiar-mcp-http-server-id)
                    "")))))))))

(defun familiar-mcp-http--reason (status)
  (pcase status (200 "OK") (202 "Accepted") (400 "Bad Request") (401 "Unauthorized")
         (403 "Forbidden") (404 "Not Found") (405 "Method Not Allowed") (_ "Error")))

(defun familiar-mcp-http--bytes (s)
  "S as UTF-8 bytes (`json-serialize' already returns those)."
  (if (multibyte-string-p s) (encode-coding-string s 'utf-8) s))

(defun familiar-mcp-http--send (proc status extra body)
  (let ((bytes (familiar-mcp-http--bytes (or body ""))))
    (process-send-string
     proc
     (concat (format "HTTP/1.1 %d %s\r\n" status (familiar-mcp-http--reason status))
             (mapconcat (lambda (h) (format "%s: %s\r\n" (car h) (cdr h))) extra "")
             (unless (assoc "Content-Type" extra) "Content-Type: text/plain; charset=utf-8\r\n")
             (format "Content-Length: %d\r\nConnection: close\r\n\r\n" (length bytes))
             bytes))
    (process-send-eof proc)))

(defun familiar-mcp-http--filter (proc chunk)
  (let ((raw (concat (or (process-get proc :raw) "") chunk)))
    (process-put proc :raw raw)
    (pcase (familiar-mcp-http--parse raw)
      ('nil nil)
      (:bad (familiar-mcp-http--send proc 400 nil "Bad request"))
      (`(,method ,path ,headers ,body)
       (process-put proc :raw nil)
       (pcase (condition-case err (familiar-mcp-http-respond method path headers body)
                (error (list 500 nil (error-message-string err))))
         (`(:async ,fn)
          (funcall fn (lambda (status extra out)
                        (when (process-live-p proc)
                          (familiar-mcp-http--send proc status extra out)))))
         (`(:sse ,fn)
          (process-send-string proc "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
          (funcall fn
                   (lambda (data)
                     (when (process-live-p proc)
                       (process-send-string proc (concat "data: " (familiar-mcp-http--bytes data) "\n\n"))))
                   (lambda () (when (process-live-p proc) (process-send-eof proc)))))
         (`(,status ,extra ,out) (familiar-mcp-http--send proc status extra out)))))))

;;;; Commands

;;;###autoload
(defun familiar-mcp-http-start (&optional port)
  "Serve familiar's MCP tools at http://127.0.0.1:PORT/mcp."
  (interactive)
  (familiar-mcp-http-stop)
  (when (eq familiar-mcp-http-process-function #'mcp-server-lib-process-jsonrpc)
    (require 'familiar-mcp)
    (familiar-mcp-start))
  (familiar-mcp-http-token)
  (setq familiar-mcp-http--server
        (make-network-process :name "familiar-mcp-http" :server t
                              :host "127.0.0.1" :service (or port familiar-mcp-http-port)
                              :family 'ipv4 :coding 'binary :noquery t
                              :filter #'familiar-mcp-http--filter))
  (let ((url (familiar-mcp-http-url)))
    (when (called-interactively-p 'interactive)
      (message "familiar MCP at %s (token in %s)" url
               (abbreviate-file-name familiar-mcp-http-token-file)))
    url))

;;;###autoload
(defun familiar-mcp-http-stop ()
  "Stop serving MCP over HTTP."
  (interactive)
  (when (process-live-p familiar-mcp-http--server)
    (delete-process familiar-mcp-http--server))
  (setq familiar-mcp-http--server nil))

(defun familiar-mcp-http-url ()
  "The endpoint, while serving."
  (when (process-live-p familiar-mcp-http--server)
    (format "http://127.0.0.1:%d/mcp" (process-contact familiar-mcp-http--server :service))))

(provide 'familiar-mcp-http)
;;; familiar-mcp-http.el ends here
