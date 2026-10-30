;;; familiar-mcp.el --- Emacs's code knowledge as MCP tools for agents -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; Package-Requires: ((emacs "29.1") (mcp-server-lib "0.5.0"))
;;
;;; Commentary:
;;
;; Coding agents search with grep.  Emacs knows more: the buffer's xref
;; backend (eglot/LSP when a server runs, else etags or Emacs Lisp) resolves
;; definitions and references semantically, and imenu knows a file's
;; structure.  This exposes that as an MCP server, "familiar", through
;; mcp-server-lib's stdio bridge to the running Emacs.
;;
;; Why not through the IDE connection (monet)?  Claude Code only passes two
;; IDE tools to the model (mcp__ide__executeCode, mcp__ide__getDiagnostics;
;; checked in the 2.1.226 bundle), so extra IDE tools would never be seen.
;;
;; Register once (user scope):
;;   claude mcp add --scope user emacs -- \
;;     <mcp-server-lib>/emacs-mcp-stdio.sh --server-id=familiar \
;;     --init-function=familiar-mcp-start --stop-function=familiar-mcp-stop
;;
;; All tools are read-only.  Positions are FILE + LINE + SYMBOL, which agents
;; already have from grep output.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'xref)
(require 'imenu)

(declare-function mcp-server-lib-register-server "ext:mcp-server-lib" (&rest properties))
(declare-function mcp-server-lib-unregister-server "ext:mcp-server-lib" (server-id))
(defvar mcp-server-lib--running)
(declare-function mcp-server-lib-tool-throw "ext:mcp-server-lib" (error-message))
(declare-function mcp-server-lib-start "ext:mcp-server-lib-commands" ())

(defvar familiar-mcp-max-results 50 "Cap on locations returned per call.")

(defun familiar-mcp--throw (fmt &rest args)
  (mcp-server-lib-tool-throw (apply #'format fmt args)))

(defun familiar-mcp--buffer (file)
  "A live buffer visiting FILE, without displaying it."
  (let ((path (expand-file-name file)))
    (unless (file-readable-p path) (familiar-mcp--throw "Cannot read %s" path))
    (or (find-buffer-visiting path) (find-file-noselect path t))))

(defun familiar-mcp--goto (line symbol)
  "Move to LINE (1-based string or number) and onto SYMBOL there."
  (let ((n (if (stringp line) (string-to-number line) line)))
    (unless (and (integerp n) (> n 0)) (familiar-mcp--throw "Bad line: %S" line))
    (goto-char (point-min))
    (forward-line (1- n))
    (when (and symbol (not (string-empty-p symbol)))
      (unless (search-forward symbol (line-end-position) t)
        (familiar-mcp--throw "%s not found on line %d" symbol n))
      (goto-char (match-beginning 0)))))

(defun familiar-mcp--format (xrefs)
  "XREFS as \"file:line: summary\" lines, relative to the project when possible."
  (if (null xrefs) "No results."
    (let ((root (when-let* ((pr (project-current))) (project-root pr))))
      (mapconcat
       (lambda (x)
         (let* ((loc (xref-item-location x))
                (file (xref-location-group loc))
                (line (or (xref-location-line loc)
                          ;; elisp (and some other) locations have no line
                          ;; until resolved to a marker.
                          (ignore-errors
                            (let ((m (xref-location-marker loc)))
                              (with-current-buffer (marker-buffer m)
                                (line-number-at-pos m)))))))
           (format "%s:%s: %s"
                   (if (and root file (file-in-directory-p file root))
                       (file-relative-name file root)
                     file)
                   (or line "?")
                   (string-trim (substring-no-properties (xref-item-summary x))))))
       (seq-take xrefs familiar-mcp-max-results)
       "\n"))))

(defun familiar-mcp--xref (kind file line symbol)
  "Resolve KIND (definitions or references) at FILE LINE SYMBOL."
  (with-current-buffer (familiar-mcp--buffer file)
    (save-excursion
      (familiar-mcp--goto line symbol)
      (let* ((backend (or (xref-find-backend) (familiar-mcp--throw "No xref backend")))
             (id (or (xref-backend-identifier-at-point backend)
                     (familiar-mcp--throw "No identifier at %s:%s" file line))))
        (concat (format "[%s via %s]\n" kind backend)
                (familiar-mcp--format
                 (if (eq kind 'definitions)
                     (xref-backend-definitions backend id)
                   (xref-backend-references backend id))))))))

(defun familiar-mcp-definitions (file line &optional symbol)
  "Find where the symbol at FILE:LINE is defined, using Emacs's xref backend.

MCP Parameters:
  file - Absolute path of the file containing the use
  line - Line number (1-based) of the use
  symbol - The identifier on that line (recommended; else the line start)"
  (familiar-mcp--xref 'definitions file line symbol))

(defun familiar-mcp-references (file line &optional symbol)
  "Find references to the symbol at FILE:LINE, using Emacs's xref backend.

MCP Parameters:
  file - Absolute path of the file containing the symbol
  line - Line number (1-based) of the symbol
  symbol - The identifier on that line (recommended; else the line start)"
  (familiar-mcp--xref 'references file line symbol))

(defun familiar-mcp--flatten (index &optional prefix)
  "Flatten an imenu INDEX into (NAME . POSITION), nested names joined by PREFIX."
  (cl-loop for (name . rest) in index
           for full = (if prefix (concat prefix "/" name) name)
           if (imenu--subalist-p (cons name rest))
           append (familiar-mcp--flatten rest full)
           else if (not (string-prefix-p "*" name))
           collect (cons full (if (overlayp rest) (overlay-start rest) rest))))

(defun familiar-mcp-outline (file)
  "List the definitions in FILE with their line numbers, from imenu.

MCP Parameters:
  file - Absolute path of the file"
  (with-current-buffer (familiar-mcp--buffer file)
    (let* ((imenu-auto-rescan t)
           (index (save-excursion (ignore-errors (imenu--make-index-alist t))))
           (items (familiar-mcp--flatten index)))
      (if (null items) "No outline (no imenu support for this mode)."
        (mapconcat (lambda (it)
                     (format "%d: %s" (line-number-at-pos (cdr it)) (car it)))
                   (sort items (lambda (a b) (< (cdr a) (cdr b))))
                   "\n")))))

(defconst familiar-mcp--tools
  '((familiar-mcp-definitions
     :id "definitions" :read-only t
     :description "Semantic go-to-definition from the user's Emacs (LSP via eglot when running, else etags/elisp). More precise than grep for overloaded or common names.")
    (familiar-mcp-references
     :id "references" :read-only t
     :description "Semantic find-references from the user's Emacs (LSP via eglot when running, else etags/elisp).")
    (familiar-mcp-outline
     :id "outline" :read-only t
     :description "Structural outline of a file (functions, types, headings) with line numbers, from Emacs's imenu."))
  "Tool specs for `mcp-server-lib-register-server'.")

;;;###autoload
(defun familiar-mcp-start ()
  "Register the familiar MCP server; used as the stdio script's init function."
  (require 'mcp-server-lib)
  (mcp-server-lib-register-server
   :id "familiar" :name "familiar-emacs"
   :instructions "Code navigation from the user's running Emacs. Prefer `definitions'/`references' over grep for symbols; pass the absolute file, the 1-based line and the symbol text."
   :tools familiar-mcp--tools)
  ;; Shared with other servers (elisp-dev-mcp) and other Claude sessions;
  ;; starting twice is an error.
  (unless (bound-and-true-p mcp-server-lib--running)
    (mcp-server-lib-start)))

;;;###autoload
(defun familiar-mcp-stop ()
  "Unregister the familiar MCP server; the stdio script's stop function."
  (mcp-server-lib-unregister-server "familiar"))

(provide 'familiar-mcp)
;;; familiar-mcp.el ends here
