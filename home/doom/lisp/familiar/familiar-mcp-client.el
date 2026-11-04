;;; familiar-mcp-client.el --- MCP servers' tools in familiar-ask, by @name -*- lexical-binding: t; -*-
;;
;; The MCP servers Claude Code knows for a project (~/.claude.json: the
;; user's and the project's own) are @keywords in M-ß: "@github open
;; issues about the CI?" starts the server if it isn't running and offers
;; its tools for that turn.  Configured once, for Claude Code and Emacs.
;;
;; Only when asked for: github alone brings 26 tool schemas, which would
;; be paid for with every prompt.  familiar's own bridge ("emacs") is left
;; out; its tools are M-ß's anyway.
;;
;; Tools that may change things outside Emacs (create, update, merge, push)
;; ask first, whatever `familiar-ask-confirm-tools' says: those were set to
;; run unasked for Emacs, where edits are undoable.  Read-only ones run at
;; once: by the tool's readOnlyHint, else `familiar-mcp-client-read-only-servers',
;; else the name (get_, list_, search_, read_…).
;;
;; Uses mcp.el (lizqwerscott/mcp.el) as the client.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar-ask)

(defvar mcp-server-connections)
(declare-function mcp-connect-server "ext:mcp" (name &rest args))
(declare-function mcp-make-text-tool "ext:mcp" (name tool-name &optional asyncp))
(declare-function mcp--status "ext:mcp" (connection))
(declare-function mcp--tools "ext:mcp" (connection))
(declare-function project-root "project" (project))

(defgroup familiar-mcp-client nil
  "MCP servers' tools in `familiar-ask'."
  :group 'familiar)

(defcustom familiar-mcp-client-config (expand-file-name "~/.claude.json")
  "Claude Code's configuration, read for its MCP servers."
  :type 'file)

(defcustom familiar-mcp-client-exclude '("emacs")
  "Servers not offered: \"emacs\" is familiar's own bridge."
  :type '(repeat string))

(defcustom familiar-mcp-client-confirm-writes t
  "Whether MCP tools that aren't read-only ask before running."
  :type 'boolean)

(defcustom familiar-mcp-client-read-only-servers '("nixos-mcp")
  "Servers whose tools only read (nixos-mcp searches package data)."
  :type '(repeat string))

(defvar familiar-mcp-client-read-only-regexp
  "\\`\\(?:get\\|list\\|search\\|read\\|fetch\\|find\\|describe\\|show\\|query\\|nixos_search\\|nixos_info\\|home_manager\\|darwin\\|nixhub\\)"
  "Tool names that only read: they run without asking.")

(defvar familiar-mcp-client--cache nil "(MTIME . PARSED-JSON) of the config.")

(defun familiar-mcp-client--json ()
  "Claude Code's configuration as nested alists, read again when it changes."
  (when (file-readable-p familiar-mcp-client-config)
    (let ((mtime (file-attribute-modification-time
                  (file-attributes familiar-mcp-client-config))))
      (unless (equal mtime (car familiar-mcp-client--cache))
        (setq familiar-mcp-client--cache
              (cons mtime (with-temp-buffer
                            (insert-file-contents familiar-mcp-client-config)
                            (json-parse-buffer :object-type 'alist :array-type 'list
                                               :null-object nil :false-object nil)))))
      (cdr familiar-mcp-client--cache))))

(defun familiar-mcp-client--project ()
  "This buffer's project root as Claude Code keys it (no trailing slash)."
  (when-let* ((pr (project-current)))
    (directory-file-name (expand-file-name (project-root pr)))))

(defun familiar-mcp-client-servers (&optional project)
  "Alist NAME → plist (:command :args :env) of stdio servers for PROJECT.
PROJECT defaults to this buffer's; its servers come after the user's."
  (let* ((json (familiar-mcp-client--json))
         (project (or project (familiar-mcp-client--project)))
         (scopes (list (alist-get 'mcpServers json)
                       (and project
                            (alist-get 'mcpServers
                                       (alist-get (intern project) (alist-get 'projects json))))))
         out)
    (dolist (servers scopes)
      (pcase-dolist (`(,name . ,spec) servers)
        (let ((name (symbol-name name)))
          (when (and (alist-get 'command spec)
                     (member (or (alist-get 'type spec) "stdio") '("stdio"))
                     (not (member name familiar-mcp-client-exclude)))
            (setf (alist-get name out nil nil #'equal)
                  (list :command (alist-get 'command spec)
                        :args (alist-get 'args spec)
                        :env (cl-loop for (k . v) in (alist-get 'env spec)
                                      append (list (intern (format ":%s" k)) v))))))))
    (nreverse out)))

(defun familiar-mcp-client-keywords ()
  "@NAME keywords for the servers of this buffer's project."
  (mapcar (lambda (s) (cons (car s) (format "tools of the %s MCP server" (car s))))
          (familiar-mcp-client-servers)))

(defun familiar-mcp-client--connection (name spec)
  "A connected client for server NAME (SPEC as in `familiar-mcp-client-servers')."
  (require 'mcp)
  (let ((conn (gethash name mcp-server-connections)))
    (unless (and conn (eq (mcp--status conn) 'connected))
      (message "Starting the %s MCP server…" name)
      (apply #'mcp-connect-server name
             (append spec (list :syncp t)))
      (setq conn (gethash name mcp-server-connections)))
    (unless (and conn (eq (mcp--status conn) 'connected))
      (user-error "The %s MCP server didn't start (see *%s stderr*)" name name))
    conn))

(defun familiar-mcp-client--read-only-p (name spec)
  "Whether server NAME's tool SPEC (as the server lists it) only reads.
Its own readOnlyHint when it gives one, else the server, else the name."
  (let ((hint (plist-member (plist-get spec :annotations) :readOnlyHint)))
    (cond (hint (eq (cadr hint) t))
          ((member name familiar-mcp-client-read-only-servers) t)
          (t (string-match-p familiar-mcp-client-read-only-regexp (plist-get spec :name))))))

(defun familiar-mcp-client--wrap (tool name &optional read-only)
  "TOOL (a gptel tool plist from mcp.el) capped, asking first unless READ-ONLY."
  (let* ((tool-name (plist-get tool :name))
         (fn (plist-get tool :function))
         (asks (and familiar-mcp-client-confirm-writes (not read-only))))
    (plist-put tool :function
               (lambda (callback &rest args)
                 (if (and asks
                          (not (y-or-n-p (format "%s: run %s %s? " name tool-name
                                                 (truncate-string-to-width (format "%S" args) 120 nil nil "…")))))
                     (funcall callback (format "The user declined to run %s." tool-name))
                   (apply fn (lambda (result)
                               (funcall callback (if (stringp result) (familiar-ask--cap result) result)))
                          args))))
    (plist-put tool :category (format "mcp-%s" name))
    (apply #'gptel-make-tool tool)))

(defun familiar-mcp-client-turn-tools (keywords origin)
  "The tools of the servers named in KEYWORDS, for ORIGIN's project."
  (let ((servers (with-current-buffer (or (plist-get origin :buffer) (current-buffer))
                   (familiar-mcp-client-servers))))
    (cl-loop for (name . spec) in servers
             when (memq (intern name) keywords)
             append (let ((conn (familiar-mcp-client--connection name spec)))
                      (mapcar (lambda (tool)
                                (familiar-mcp-client--wrap
                                 (mcp-make-text-tool name (plist-get tool :name) t) name
                                 (familiar-mcp-client--read-only-p name tool)))
                              (mcp--tools conn))))))

(add-hook 'familiar-ask-keyword-functions #'familiar-mcp-client-keywords)
(add-hook 'familiar-ask-turn-tools-functions #'familiar-mcp-client-turn-tools)

(provide 'familiar-mcp-client)
;;; familiar-mcp-client.el ends here
