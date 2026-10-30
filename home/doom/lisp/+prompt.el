;;; lisp/+prompt.el --- Emacs-centric AI prompt workflow -*- lexical-binding: t; -*-
;;
;; Two entry points for inline AI interaction without leaving current context:
;;   +prompt/ask       — fresh question with optional context
;;   +prompt/followup  — continue previous conversation
;;
;; Context composition via custom syntax in minibuffer:
;;   @buffer          — include current buffer content
;;   @region          — include active region
;;   @file:path       — include file content
;;   @var:name        — include variable value
;;   @eval:(expr)     — evaluate elisp, include result
;;   @mode            — include current major/minor modes
;;   @buffers         — list open buffers with modes
;;
;; Responses stream to echo area or dedicated *AI Response* buffer.
;;
;;; Code:

(require 'gptel)

;;;; gptel tools — give LLM access to Emacs state ───────────────────────────

(after! gptel
  (dolist (tool
           (list
            (gptel-make-tool
             :name "read_buffer"
             :function (lambda (buffer)
                         (if (get-buffer buffer)
                             (with-current-buffer buffer
                               (buffer-substring-no-properties (point-min) (point-max)))
                           (format "Buffer '%s' does not exist" buffer)))
             :description "Read contents of an Emacs buffer"
             :args '((:name "buffer" :type string :description "Buffer name"))
             :category "emacs")
            (gptel-make-tool
             :name "list_buffers"
             :function (lambda ()
                         (mapconcat
                          (lambda (b)
                            (format "%s (%s)%s"
                                    (buffer-name b)
                                    (with-current-buffer b (symbol-name major-mode))
                                    (if (buffer-modified-p b) " [modified]" "")))
                          (seq-filter (lambda (b) (not (string-prefix-p " " (buffer-name b))))
                                      (buffer-list))
                          "\n"))
             :description "List all open buffers with their major modes"
             :args nil
             :category "emacs")
            (gptel-make-tool
             :name "eval_elisp"
             :function (lambda (code)
                         (condition-case err
                             (format "%S" (eval (read code)))
                           (error (format "Error: %S" err))))
             :description "Evaluate Emacs Lisp code and return the result"
             :args '((:name "code" :type string :description "Elisp expression to evaluate"))
             :category "emacs")
            (gptel-make-tool
             :name "describe_variable"
             :function (lambda (name)
                         (let ((sym (intern-soft name)))
                           (if (and sym (boundp sym))
                               (format "%s = %S\nDoc: %s" name (symbol-value sym)
                                       (or (documentation-property sym 'variable-documentation) "none"))
                             (format "Variable '%s' not bound" name))))
             :description "Get value and documentation of an Emacs variable"
             :args '((:name "name" :type string :description "Variable name"))
             :category "emacs")
            (gptel-make-tool
             :name "describe_function"
             :function (lambda (name)
                         (let ((sym (intern-soft name)))
                           (if (and sym (fboundp sym))
                               (format "%s\nDoc: %s" name (or (documentation sym) "none"))
                             (format "Function '%s' not defined" name))))
             :description "Get documentation of an Emacs function"
             :args '((:name "name" :type string :description "Function name"))
             :category "emacs")
            (gptel-make-tool
             :name "insert_text"
             :function (lambda (text buffer)
                         (if (get-buffer buffer)
                             (with-current-buffer buffer
                               (goto-char (point))
                               (insert text)
                               (format "Inserted %d chars in %s" (length text) buffer))
                           (format "Buffer '%s' not found" buffer)))
             :description "Insert text at cursor position in a buffer"
             :args '((:name "text" :type string :description "Text to insert")
                     (:name "buffer" :type string :description "Target buffer name"))
             :category "emacs")

            (gptel-make-tool
             :name "get_modes"
             :function (lambda (buffer)
                         (if (get-buffer buffer)
                             (with-current-buffer buffer
                               (format "Major: %s\nMinor: %s"
                                       major-mode
                                       (string-join
                                        (seq-take
                                         (mapcar #'symbol-name
                                                 (seq-filter
                                                  (lambda (m) (and (boundp m) (symbol-value m)))
                                                  minor-mode-list))
                                         30)
                                        ", ")))
                           "Buffer not found"))
             :description "Get major and minor modes active in a buffer"
             :args '((:name "buffer" :type string :description "Buffer name"))
             :category "emacs")))
    (push tool gptel-tools))

  ;; Brave web search tool (separate — conditional on brave-search)
  (when (fboundp 'brave-search-web)
    (push (gptel-make-tool
           :name "web_search"
           :function (lambda (query)
                       (let* ((data (brave-search-web query :count 5))
                              (results (alist-get 'results (alist-get 'web data))))
                         (mapconcat
                          (lambda (r)
                            (format "## %s\n%s\n%s\n"
                                    (alist-get 'title r)
                                    (alist-get 'url r)
                                    (or (alist-get 'description r) "")))
                          results "\n")))
           :description "Search the web via Brave Search API"
           :args '((:name "query" :type string :description "Search query"))
           :category "web")
          gptel-tools)))  ; close after! gptel

;;;; Context expansion ───────────────────────────────────────────────────────

(defvar +prompt/--last-response nil
  "Last AI response for followup context.")

(defvar +prompt/--conversation nil
  "Conversation history for followup prompts.")

(defun +prompt/--expand-context (text)
  "Expand context references in TEXT.
Replaces @buffer, @region, @file:path, @var:name, @eval:(expr), @mode, @buffers
with actual content."
  (let ((result text))
    ;; @buffer — current buffer content
    (setq result
          (replace-regexp-in-string
           "@buffer\\b"
           (lambda (_)
             (format "\n```%s\n%s\n```\n"
                     (or (file-name-extension (or buffer-file-name "")) "")
                     (buffer-substring-no-properties (point-min) (point-max))))
           result t t))
    ;; @region — active region
    (setq result
          (replace-regexp-in-string
           "@region\\b"
           (lambda (_)
             (if (use-region-p)
                 (format "\n```\n%s\n```\n"
                         (buffer-substring-no-properties
                          (region-beginning) (region-end)))
               "[no active region]"))
           result t t))
    ;; @file:path — file content
    (setq result
          (replace-regexp-in-string
           "@file:\\([^ \t\n]+\\)"
           (lambda (match)
             (let ((path (match-string 1 match)))
               (if (file-exists-p path)
                   (format "\n```\n%s\n```\n"
                           (with-temp-buffer
                             (insert-file-contents path)
                             (buffer-string)))
                 (format "[file not found: %s]" path))))
           result t t))
    ;; @var:name — variable value
    (setq result
          (replace-regexp-in-string
           "@var:\\([^ \t\n]+\\)"
           (lambda (match)
             (let* ((name (match-string 1 match))
                    (sym (intern-soft name)))
               (if (and sym (boundp sym))
                   (format "%s = %S" name (symbol-value sym))
                 (format "[variable not bound: %s]" name))))
           result t t))
    ;; @eval:(expr) — evaluate elisp
    (setq result
          (replace-regexp-in-string
           "@eval:(\\([^)]+\\))"
           (lambda (match)
             (let ((expr (match-string 1 match)))
               (condition-case err
                   (format "%s → %S" expr (eval (read expr)))
                 (error (format "[eval error: %S]" err)))))
           result t t))
    ;; @mode — current modes
    (setq result
          (replace-regexp-in-string
           "@mode\\b"
           (lambda (_)
             (format "Major: %s\nMinor: %s"
                     major-mode
                     (string-join
                      (mapcar #'symbol-name
                              (seq-filter
                               (lambda (m)
                                 (and (boundp m) (symbol-value m)))
                               minor-mode-list))
                      ", ")))
           result t t))
    ;; @buffers — open buffers
    (setq result
          (replace-regexp-in-string
           "@buffers\\b"
           (lambda (_)
             (mapconcat
              (lambda (b)
                (format "  %s (%s)"
                        (buffer-name b)
                        (with-current-buffer b (symbol-name major-mode))))
              (seq-filter #'buffer-file-name (buffer-list))
              "\n"))
           result t t))
    result))

;;;; System prompt ───────────────────────────────────────────────────────────

(defvar +prompt/system-prompt
  "You are an expert Emacs assistant embedded in a Doom Emacs session.
You have tools to interact with the running Emacs instance.

Environment:
- GNU Emacs 32.0.50 (pgtk build) on NixOS
- Doom Emacs v2.2.4 with evil-mode
- Maple Mono NF font with ligatures
- User: Wolfhard, German keyboard (QWERTZ), speaks English and German
- Languages: Agda, Lean 4, Coq, Haskell, Rust, Nix, TypeScript

Available tools:
- read_buffer: Read buffer contents by name
- list_buffers: List open buffers with modes
- eval_elisp: Evaluate arbitrary Emacs Lisp and return result
- describe_variable: Get variable value and docs
- describe_function: Get function documentation
- insert_text: Insert text at cursor in a buffer
- get_modes: Get active major/minor modes in a buffer
- web_search: Search the web via Brave Search API

Use tools proactively to answer questions about the user's Emacs state.
When asked about buffers, modes, or config — use tools to check, don't guess.
When asked to insert or modify — use insert_text or eval_elisp.

When answering:
- Be concise and direct
- Use org-mode formatting
- For Emacs questions, prefer Doom idioms (map!, after!, use-package!, etc.)
- For keybindings, note SPC is leader, localleader is SPC m
- Show elisp code when relevant
- German umlauts are fine in responses"
  "System prompt for +prompt/ AI interactions.")

;;;; Core commands ───────────────────────────────────────────────────────────

(defun +prompt/ask (prompt)
  "Ask AI a question with optional context expansion.
Context syntax: @buffer @region @file:path @var:name @eval:(expr) @mode @buffers"
  (interactive
   (list (read-string "Ask AI: "
                      (when (use-region-p)
                        (concat "@region ")))))
  (let* ((expanded (+prompt/--expand-context prompt))
         (buf (get-buffer-create "*AI Response*")))
    ;; Store for followup
    (setq +prompt/--conversation
          (list (list :role "user" :content expanded)))
    ;; Show loading
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Thinking..." 'face 'shadow))
        (org-mode)))
    (display-buffer buf '(display-buffer-in-side-window
                          (side . bottom) (slot . 0) (window-height . 0.35)))
    ;; Send request with all tools always enabled
    (gptel-request expanded
      :system +prompt/system-prompt
      :tools gptel-tools
      :callback
      (lambda (response _info)
        (setq +prompt/--last-response response)
        (push (list :role "assistant" :content response)
              +prompt/--conversation)
        (with-current-buffer (get-buffer-create "*AI Response*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert response)
            (goto-char (point-min))
            (org-mode)
            (view-mode 1)))))))

(defun +prompt/followup (prompt)
  "Continue previous AI conversation with PROMPT."
  (interactive
   (list (read-string "Followup: "
                      (when (use-region-p)
                        (concat "@region ")))))
  (unless +prompt/--conversation
    (user-error "No previous conversation. Use +prompt/ask first"))
  (let* ((expanded (+prompt/--expand-context prompt))
         (context (mapconcat
                   (lambda (msg)
                     (format "%s: %s"
                             (upcase (substring (symbol-name (plist-get msg :role)) 1))
                             (plist-get msg :content)))
                   (reverse +prompt/--conversation)
                   "\n\n"))
         (full-prompt (format "%s\n\nUSER: %s" context expanded))
         (buf (get-buffer-create "*AI Response*")))
    (push (list :role "user" :content expanded)
          +prompt/--conversation)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Thinking..." 'face 'shadow))))
    (display-buffer buf '(display-buffer-in-side-window
                          (side . bottom) (slot . 0) (window-height . 0.35)))
    (gptel-request full-prompt
      :system +prompt/system-prompt
      :tools gptel-tools
      :callback
      (lambda (response _info)
        (setq +prompt/--last-response response)
        (push (list :role "assistant" :content response)
              +prompt/--conversation)
        (with-current-buffer (get-buffer-create "*AI Response*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert response)
            (goto-char (point-min))
            (org-mode)
            (view-mode 1)))))))

(defun +prompt/insert-response ()
  "Insert last AI response at point."
  (interactive)
  (unless +prompt/--last-response
    (user-error "No AI response available"))
  (insert +prompt/--last-response))

(defun +prompt/ask-about-buffer ()
  "Quick: ask about current buffer with full content attached."
  (interactive)
  (+prompt/ask (concat "@buffer\n\nQuestion: "
                       (read-string "Ask about this buffer: "))))

(defun +prompt/explain-region ()
  "Quick: explain selected region."
  (interactive)
  (unless (use-region-p) (user-error "No active region"))
  (+prompt/ask "@region\n\nExplain this code in detail."))

(defun +prompt/rewrite-region ()
  "Quick: rewrite selected region."
  (interactive)
  (unless (use-region-p) (user-error "No active region"))
  (+prompt/ask (concat "@region\n\nRewrite this to be: "
                       (read-string "Rewrite to be: "))))

(defun +prompt/org-table ()
  "Quick: generate org table from description."
  (interactive)
  (+prompt/ask (concat "Generate an org-mode table. "
                       (read-string "Table contents: ")
                       "\n\nReturn ONLY the org table, no explanation.")))

;;;; Transient ───────────────────────────────────────────────────────────────

(transient-define-prefix +prompt/transient ()
  "AI prompt dispatch."
  ["Prompt"
   ("a" "Ask AI"              +prompt/ask)
   ("f" "Followup"            +prompt/followup)
   ("b" "Ask about buffer"    +prompt/ask-about-buffer)]
  ["Region"
   ("e" "Explain region"      +prompt/explain-region)
   ("r" "Rewrite region"      +prompt/rewrite-region)]
  ["Insert"
   ("i" "Insert response"     +prompt/insert-response)
   ("t" "Generate org table"  +prompt/org-table)]
  ["gptel"
   ("g" "gptel send"          gptel-send)
   ("G" "gptel menu"          gptel-menu)
   ("m" "Set model"           +agent/set-model)])

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      :desc "AI prompt"        "i" #'+prompt/ask
      :desc "AI followup"      "I" #'+prompt/followup
      :desc "AI prompt menu"   "'" #'+prompt/transient)

(provide '+prompt)
;;; +prompt.el ends here
