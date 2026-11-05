;;; lisp/+discover.el --- C-ß: one place to start looking -*- lexical-binding: t; -*-
;;
;; Emacs answers "how do I…" in a dozen places: M-x, apropos, describe-*,
;; Info, embark, which-key, consult-info, Doom's docs.  C-ß, from any buffer,
;; evil state or prompt, is where to start:
;;
;;   C-ß          the menu: what is here (keys, commands, this mode's manual,
;;                the thing at point), a key or a command, words, learning
;;   C-ß C-ß      search everything by words (`+discover/anything'):
;;                  your words for Emacs's   copy → evil-yank, kill-ring-save
;;                  commands, by their docs too, renamed ones by the old name
;;                  Emacs's words            region ≈ selection (the glossary)
;;                  manuals, options
;;                nothing matches: RET asks the assistant, as in M-x
;;   SPC ?        the menu, too
;;   SPC h D      search the text of every manual (`consult-info')
;;   SPC h SPC    the commands of the modes on here (`consult-mode-command')
;;
;; Your words find Emacs's in M-x too: "copy" matches kill-ring-save, "image"
;; org-link-preview (`+discover-synonyms').
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar orderless-matching-styles)
(defvar embark-transformer-alist)
(defvar +usage--mx-commands)
(defvar +usage-runners)
(declare-function embark-bindings "ext:embark" (global))
(declare-function embark-bindings-in-keymap "ext:embark" (keymap))
(declare-function info--manual-names "info" (visited-only))
(declare-function Info-find-node "info" (filename nodename &optional no-going-back strict-case))
(declare-function Info-find-emacs-command-nodes "info" (command))
(declare-function Info-goto-emacs-command-node "info" (command))
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function +usage--merged "+usage" ())
(declare-function +usage-say-later "+usage" (text))
(declare-function familiar-ask "familiar-ask" (prompt &optional fresh origin))
(declare-function consult-info "ext:consult-info" (&rest manuals))
(declare-function helpful-symbol "ext:helpful" (symbol))
(declare-function helpful-variable "ext:helpful" (symbol))
(declare-function helpful-callable "ext:helpful" (symbol))
(declare-function helpful-key "ext:helpful" (key-sequence))

;;;; Your words → Emacs's words (in M-x and C-ß C-ß)

(defvar +discover-synonyms
  '(("copy" "yank" "kill-ring-save" "duplicate")
    ("cut" "kill")
    ("paste" "yank" "insert-register")
    ("clipboard" "kill-ring" "yank" "clipboard")
    ("delete" "kill" "remove" "erase" "clear")
    ("remove" "delete" "kill" "erase")
    ("close" "kill" "quit" "bury" "delete-window")
    ("open" "find" "visit")
    ("search" "find" "grep" "ripgrep" "occur" "isearch" "lookup" "consult-line")
    ("find" "search" "grep" "lookup" "locate")
    ("replace" "substitute" "query-replace")
    ("show" "display" "view" "preview" "describe" "toggle")
    ("hide" "fold" "collapse" "toggle" "invisible")
    ("toggle" "show" "hide" "preview" "mode")
    ("preview" "show" "display" "view" "toggle")
    ("image" "picture" "inline" "link-preview" "img")
    ("picture" "image" "link-preview")
    ("explorer" "dired" "dirvish" "treemacs" "sidebar")
    ("sidebar" "side" "dirvish" "treemacs")
    ("terminal" "term" "shell" "eshell" "vterm" "ghostel")
    ("console" "repl" "shell" "eshell" "term")
    ("pane" "window" "split")
    ("tab" "workspace" "tab-bar" "buffer")
    ("settings" "custom" "customize" "config" "option")
    ("setting" "custom" "customize" "option")
    ("preferences" "custom" "customize" "option")
    ("error" "flycheck" "flymake" "diagnostic" "problem")
    ("problem" "error" "diagnostic" "flycheck")
    ("selection" "region" "mark" "visual")
    ("select" "mark" "region" "visual")
    ("cursor" "point" "caret")
    ("jump" "goto" "go-to" "avy" "navigate" "imenu")
    ("goto" "jump" "go-to")
    ("fold" "hide" "outline" "collapse" "narrow")
    ("collapse" "fold" "hide" "outline")
    ("expand" "unfold" "show" "outline")
    ("spell" "jinx" "ispell" "flyspell")
    ("format" "indent" "tidy" "prettify" "apheleia")
    ("git" "magit" "vc-" "diff-hl" "hunk")
    ("history" "ring" "recent" "lossage")
    ("link" "url" "browse" "hyperlink")
    ("url" "link" "browse")
    ("color" "colour" "theme" "face")
    ("theme" "color" "colour")
    ("font" "face" "text-scale" "zoom")
    ("zoom" "text-scale" "font-size" "scale")
    ("shortcut" "key" "binding" "keymap")
    ("keybinding" "key" "binding" "keymap")
    ("snippet" "yasnippet" "yas" "template")
    ("autocomplete" "completion" "complete" "corfu" "capf")
    ("task" "todo" "agenda")
    ("todo" "task" "agenda")
    ("emoji" "unicode" "char")
    ("wrap" "visual-line" "truncate" "fill")
    ("reload" "revert" "refresh")
    ("refresh" "revert" "reload")
    ("documentation" "doc" "info" "describe" "manual")
    ("manual" "info")
    ("uppercase" "upcase" "capitalize")
    ("lowercase" "downcase")
    ("definition" "lookup" "xref"))
  "WORD → the words Emacs (or a package) uses for it.  Directed: \"copy\"
finds kill-ring-save, not the other way round.")

(defun +discover-orderless-synonyms (component)
  "Orderless matching style: COMPONENT, if one of your words, also matches
Emacs's words for it (`+discover-synonyms').  Nil otherwise: the other
styles still match the word itself."
  (when-let* ((alts (cdr (assoc (downcase component) +discover-synonyms))))
    (rx-to-string `(or ,@alts) t)))

(defvar +discover-synonym-commands
  '(execute-extended-command execute-extended-command-for-buffer
    +discover/anything consult-mode-command)
  "Prompts whose words match synonyms.")

(defun +discover--use-synonyms ()
  "In this minibuffer, your words match synonyms too."
  (when (require 'orderless nil t)
    (setq-local orderless-matching-styles
                (cons #'+discover-orderless-synonyms
                      (remq #'+discover-orderless-synonyms
                            (default-value 'orderless-matching-styles))))))

(defun +discover--synonyms-h ()
  (when (memq current-minibuffer-command +discover-synonym-commands)
    (+discover--use-synonyms)))

(add-hook 'minibuffer-setup-hook #'+discover--synonyms-h)

;;;; Your words, mapped to the commands that do it here

(defvar +discover-yours
  '(("copy" (evil-yank kill-ring-save) "Emacs: kill-ring-save; Evil: y")
    ("cut" (evil-delete kill-region) "Emacs: kill; Evil deletes into a register")
    ("paste" (evil-paste-after yank) "Emacs: yank (the opposite of Evil's y)")
    ("clipboard history, paste an older copy" (+default/yank-pop consult-yank-pop) "the kill ring")
    ("redo" (evil-redo undo-redo))
    ("undo history, undo tree" (undo-tree-visualize vundo))
    ("command palette" (execute-extended-command) "M-x")
    ("quick open, go to a file in the project" (projectile-find-file project-find-file))
    ("open a file" (find-file))
    ("recent files" (consult-recent-file recentf-open))
    ("go to symbol, outline of this file" (consult-imenu imenu))
    ("go to line" (consult-goto-line goto-line))
    ("go to definition" (+lookup/definition xref-find-definitions))
    ("find references, usages" (+lookup/references xref-find-references))
    ("find in files, search the project" (+default/search-project consult-ripgrep))
    ("search in this file" (+default/search-buffer consult-line))
    ("replace in files" (projectile-replace project-query-replace-regexp))
    ("find and replace" (query-replace) "Evil: :%s/old/new/g")
    ("rename symbol, refactor" (eglot-rename lsp-rename))
    ("format document, prettify" (+format/dwim +format/buffer))
    ("code actions, quick fix" (eglot-code-actions lsp-execute-code-action))
    ("toggle comment" (evilnc-comment-operator comment-dwim))
    ("problems, errors list, diagnostics" (+default/diagnostics flycheck-list-errors))
    ("terminal" (+ghostel/toggle +vterm/toggle +eshell/toggle))
    ("file explorer, sidebar, file tree" (dirvish-side +treemacs/toggle dired-jump))
    ("split editor right" (evil-window-vsplit split-window-right))
    ("split editor down" (evil-window-split split-window-below))
    ("close editor, close tab" (kill-current-buffer))
    ("new file, untitled" (evil-buffer-new))
    ("save as" (write-file))
    ("save all" (evil-write-all save-some-buffers))
    ("rename file, move file" (doom/move-this-file rename-visited-file))
    ("delete file" (doom/delete-this-file))
    ("copy file path" (+default/yank-buffer-path))
    ("word wrap" (+word-wrap-mode visual-line-mode))
    ("line numbers" (doom/toggle-line-numbers display-line-numbers-mode))
    ("fold, collapse, expand" (+fold/toggle))
    ("zoom, font size" (doom/increase-font-size text-scale-adjust))
    ("presentation, big font" (doom-big-font-mode))
    ("full screen" (toggle-frame-fullscreen))
    ("color theme" (consult-theme load-theme))
    ("dark mode, light mode" (+themes/toggle-dark))
    ("source control, git" (magit-status))
    ("git blame, who changed this line" (magit-blame-addition magit-blame))
    ("this change: stage, revert, diff" (+hunks-menu))
    ("run task, build" (projectile-compile-project compile))
    ("debug" (+debugger/start))
    ("repl, console" (+eval/open-repl-other-window))
    ("workspaces, tabs" (+workspace/new))
    ("restore session, reopen last session" (doom/quickload-session))
    ("next buffer, previous buffer" (+buffer/previous previous-buffer))
    ("switch buffer, open editors" (consult-buffer switch-to-buffer))
    ("emoji" (emoji-search))
    ("snippets" (consult-yasnippet yas-insert-snippet))
    ("jump to visible text, easymotion" (evil-avy-goto-char-timer avy-goto-char-timer))
    ("open link" (link-hint-open-link))
    ("duplicate line" (duplicate-dwim))
    ("move line up/down, swap lines" (transpose-lines) "Evil: ddp")
    ("spell check, correct spelling" (jinx-correct))
    ("word count" (+prose/text-stats count-words))
    ("scratch, notepad" (doom/toggle-scratch-buffer))
    ("keyboard shortcuts, key bindings here" (embark-bindings describe-bindings))
    ("settings of this mode" (customize-mode))
    ("my config" (doom/open-private-config))
    ("select all" (mark-whole-buffer) "Evil: ggVG")
    ("block selection, column, rectangle" (evil-visual-block rectangle-mark-mode))
    ("record keys, macro" (kmacro-start-macro) "Evil: q REGISTER … q, then @REGISTER")
    ("inline images, image preview" (org-link-preview))
    ("save as root, sudo" (doom/sudo-save-buffer))
    ("ask AI, chat, assistant" (familiar-ask))
    ("insert screenshot" (+screenshot/insert-latest))
    ("process list, task manager" (proced))
    ("calculator" (quick-calc calc))
    ("diff, compare files" (ediff-files))
    ("what did I just press, key history" (view-lossage))
    ("messages, log" (view-echo-area-messages))
    ("what is this (at point)" (+discover/at-point))
    ("search the manuals" (consult-info)))
  "(WORDS COMMANDS [NOTE]): words you'd use, the commands that do it (the
first one defined is offered), what Emacs or Evil calls it.")

;;;; Emacs's words: the manual's glossary

(defvar +discover-plain
  '(("Region" . "the selection") ("Point" . "the cursor position")
    ("Mark" . "where a selection starts") ("Buffer" . "an open file, or any text")
    ("Window" . "a split pane") ("Frame" . "an OS window")
    ("Killing" . "cutting") ("Yanking" . "pasting") ("Kill Ring" . "the clipboard history")
    ("Minibuffer" . "the prompt line") ("Face" . "a text style")
    ("Font Lock" . "syntax highlighting") ("Major Mode" . "the language mode")
    ("Minor Mode" . "a feature you toggle") ("Echo Area" . "where messages show")
    ("Mode Line" . "the status bar") ("Fringe" . "the gutter")
    ("Keymap" . "a table of key bindings") ("Prefix Key" . "a key that waits for more, like SPC")
    ("Prefix Argument" . "a count or C-u (Doom: SPC u)") ("Hook" . "an event's callbacks")
    ("Dired" . "the file manager") ("Customization" . "the settings UI")
    ("Narrowing" . "showing only part of a buffer") ("Visiting" . "opening a file")
    ("Truncation" . "long lines cut off, not wrapped") ("Filling" . "hard-wrapping a paragraph"))
  "Glossary terms → what other editors call them.")

(defvar +discover--glossary nil "((TERM . FIRST-SENTENCE) …) of (emacs) Glossary.")

(defun +discover-glossary ()
  "The Emacs manual's glossary, as ((TERM . FIRST-SENTENCE) …)."
  (or +discover--glossary
      (setq +discover--glossary
            (with-temp-buffer
              (require 'info)
              (Info-mode)
              (ignore-errors (Info-find-node "emacs" "Glossary"))
              (goto-char (point-min))
              (let (out)
                (while (re-search-forward "^\\([^ \n*].*\\)\n\\(\\(?:     .*\n\\)+\\)" nil t)
                  (let ((term (match-string-no-properties 1))
                        (def (string-join (split-string (match-string-no-properties 2)) " ")))
                    (push (cons term (if (string-match "\\`.*?[.!?]\\(?: \\|\\'\\)" def)
                                         (string-trim (match-string 0 def))
                                       def))
                          out)))
                (nreverse out))))))

(defun +discover--glossary-goto (term)
  "TERM in the Emacs manual's glossary."
  (info "(emacs) Glossary")
  (with-current-buffer "*info*"
    (goto-char (point-min))
    (when (re-search-forward (concat "^" (regexp-quote term) "$") nil t)
      (beginning-of-line)
      (set-window-point (get-buffer-window (current-buffer)) (point))
      (set-window-start (get-buffer-window (current-buffer)) (point)))))

;;;; Manuals

(defvar +discover--manuals nil "((NAME . DESCRIPTION) …) from the Info directory.")

(defun +discover-manuals ()
  "Installed Info manuals, with the directory's line about each."
  (or +discover--manuals
      (setq +discover--manuals
            (let ((names (progn (require 'info) (info--manual-names nil)))
                  (about (make-hash-table :test #'equal)))
              (with-temp-buffer
                (Info-mode)
                (when (ignore-errors (Info-find-node "dir" "top") t)
                  (goto-char (point-min))
                  (while (re-search-forward "^\\* \\([^:\n]+\\): (\\([^)]+\\))[^.\n]*\\.[ \t]*\\(.*\\)" nil t)
                    (let ((file (match-string-no-properties 2)))
                      (unless (gethash file about)
                        (puthash file (format "%s: %s" (match-string-no-properties 1)
                                              (match-string-no-properties 3))
                                 about))))))
              (mapcar (lambda (n) (cons n (gethash n about ""))) (sort names #'string<))))))

;;;; C-ß C-ß: search everything

(defvar +discover--origin nil "The buffer the search was started from.")
(defvar +discover--table nil "Candidate → (KIND . DATA) of the running search.")
(defvar +discover--used nil "Command → times used, for the running search.")

(defconst +discover--groups
  '((yours . "Your words → Emacs") (command . "Commands") (term . "Emacs's words")
    (manual . "Manuals") (option . "Options")))

(defun +discover--doc (sym &optional variable)
  (let ((doc (ignore-errors
               (if variable (documentation-property sym 'variable-documentation t)
                 (documentation sym t)))))
    (if doc (car (split-string doc "\n")) "")))

(defun +discover--line (name doc)
  (concat name " " (propertize " " 'display '(space :align-to 44))
          (propertize doc 'face 'completions-annotations)))

(defvar +discover--command-lines (make-hash-table :test #'eq) "Command → its line, made once.")
(defvar +discover--option-lines (make-hash-table :test #'eq) "Option → its line, made once.")

(defun +discover--first-command (cmds)
  (cl-find-if #'commandp cmds))

(defun +discover--usage ()
  "COMMAND → times used (`+usage'), or an empty table."
  (let ((h (make-hash-table :test #'eq)))
    (when (fboundp '+usage--merged)
      (pcase-dolist (`(,cmd . ,hows) (ignore-errors (+usage--merged)))
        (puthash cmd (apply #'+ (mapcar #'cdr hows)) h)))
    h))

(defun +discover--candidates ()
  "All candidates, in display order; fills `+discover--table'."
  (let ((table +discover--table) (used +discover--used) yours cmds terms mans opts)
    (cl-flet ((add (str entry list) (puthash str entry table) (cons str list)))
      (pcase-dolist (`(,words ,commands ,note) +discover-yours)
        (when-let* ((cmd (+discover--first-command commands)))
          (setq yours (add (+discover--line words (format "→ %s%s" cmd (if note (concat "   " note) "")))
                           (cons 'yours cmd) yours))))
      (mapatoms
       (lambda (s)
         (cond ((and (commandp s) (not (string-search "--" (symbol-name s))))
                (let* ((obs (get s 'byte-obsolete-info))
                       (new (and (symbolp (car obs)) (car obs))))
                  (push (cons (car (add (or (gethash s +discover--command-lines)
                                            (puthash s (+discover--line
                                                        (symbol-name s)
                                                        (if new (format "renamed: now %s%s" new
                                                                        (if (nth 2 obs) (format " (in %s)" (nth 2 obs)) ""))
                                                          (+discover--doc s)))
                                                     +discover--command-lines))
                                   (cons 'command (or new s)) nil))
                              (gethash (or new s) used 0))
                        cmds)))
               ((and (custom-variable-p s) (not (string-search "--" (symbol-name s))))
                (setq opts (add (or (gethash s +discover--option-lines)
                                    (puthash s (+discover--line (symbol-name s) (+discover--doc s t))
                                             +discover--option-lines))
                                (cons 'option s) opts))))))
      (pcase-dolist (`(,term . ,def) (+discover-glossary))
        (let ((plain (cdr (assoc term +discover-plain))))
          (setq terms (add (+discover--line term (if plain (format "≈ %s.  %s" plain def) def))
                           (cons 'term term) terms))))
      (pcase-dolist (`(,name . ,about) (+discover-manuals))
        (setq mans (add (+discover--line name about) (cons 'manual name) mans))))
    ;; Commands you use first, most used first; then by name.
    (setq cmds (mapcar #'car (sort cmds (lambda (a b)
                                          (if (= (cdr a) (cdr b))
                                              (string< (car a) (car b))
                                            (> (cdr a) (cdr b)))))))
    (nconc (nreverse yours) cmds
           (sort terms #'string<) (nreverse mans) (sort opts #'string<))))

(defun +discover--group (cand transform)
  (if transform cand
    (alist-get (car (gethash cand +discover--table)) +discover--groups)))

(defun +discover--affix (cands)
  "Keys (as they are where you came from) before each candidate."
  (let ((used +discover--used))
    (with-current-buffer (if (buffer-live-p +discover--origin) +discover--origin (current-buffer))
      (mapcar
       (lambda (cand)
         (let* ((entry (gethash cand +discover--table))
                (sym (and (memq (car entry) '(command yours)) (cdr entry)))
                (key (and sym (where-is-internal sym nil t)))
                (n (and sym used (gethash sym used))))
           (list cand
                 (propertize (truncate-string-to-width (if key (key-description key) "") 13 nil ?\s)
                             'face 'help-key-binding)
                 (if n (propertize (format "  %d×" n) 'face 'shadow) ""))))
       cands))))

(defun +discover--collection (cands)
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (category . +discover)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   (group-function . +discover--group)
                   (affixation-function . +discover--affix))
      (complete-with-action action cands string pred))))

(defun +discover--run (cmd)
  "Run CMD as M-x would, then name its key if it has one."
  (let ((key (where-is-internal cmd nil t)))
    (setq this-command cmd)
    (add-to-history 'extended-command-history (symbol-name cmd))
    (command-execute cmd 'record)
    (when (and key (fboundp '+usage-say-later))
      (+usage-say-later (format "Next time: %s" (propertize (key-description key) 'face 'help-key-binding))))))

(defun +discover--act (entry)
  (pcase entry
    (`(,(or 'command 'yours) . ,cmd) (+discover--run cmd))
    (`(term . ,term) (+discover--glossary-goto term))
    (`(manual . ,name) (info name))
    (`(option . ,var) (if (fboundp 'helpful-variable) (helpful-variable var) (describe-variable var)))))

;;;###autoload
(defun +discover/anything (&optional initial)
  "Search by words: your words for things, commands (and their docs),
Emacs's own words, manuals, options.  RET runs a command, opens a
glossary entry or manual, describes an option.  C-; (embark) on a
candidate: describe it, find its source, bind it…  Nothing matches: RET
asks the assistant which command does it."
  (interactive)
  (let* ((+discover--origin (current-buffer))
         (+discover--table (make-hash-table :test #'equal :size 20000))
         (+discover--used (+discover--usage))
         (cands (+discover--candidates))
         (pick (minibuffer-with-setup-hook #'+discover--use-synonyms
                 (completing-read "Find anything (words): " (+discover--collection cands)
                                  nil t initial))))
    (+discover--act (gethash pick +discover--table))))

(defun +discover--embark-target (_type cand)
  "What embark acts on: the command, option, term or manual behind CAND."
  (pcase (and +discover--table (gethash cand +discover--table))
    (`(,(or 'command 'yours) . ,cmd) (cons 'command (symbol-name cmd)))
    (`(option . ,var) (cons 'variable (symbol-name var)))
    (`(,_ . ,name) (cons 'general name))
    (_ (cons 'general cand))))

(with-eval-after-load 'embark
  (add-to-list 'embark-transformer-alist '(+discover . +discover--embark-target)))

;; Nothing matching: RET asks the assistant, C-g is remembered, as for M-x
;; (+usage.el, "M-x that gave up").
(with-eval-after-load '+usage
  (add-to-list '+usage--mx-commands '+discover/anything)
  ;; What you run from here counts as that command, run by "C-ß".
  (add-to-list '+usage-runners '(+discover/anything . "C-ß")))

;;;; Here: this mode's manual, the thing at point, keys under a prefix

(defun +discover--manual-of (sym)
  "The installed Info manual of the package defining SYM, or nil.
A package's manual has its name (magit, org-roam); a file of Emacs's own
also its first word (elisp-mode → elisp, info → info)."
  (when-let* ((file (ignore-errors (symbol-file sym 'defun))))
    (let* ((names (progn (require 'info) (info--manual-names nil)))
           (base (file-name-base file))
           (pkg (file-name-nondirectory (directory-file-name (file-name-directory file))))
           (own (and (boundp 'lisp-directory)
                     (string-prefix-p (file-truename lisp-directory) (file-truename file)))))
      (cl-find-if (lambda (n) (member n names))
                  (if own (list base (car (split-string base "-")))
                    (list pkg base))))))

(defun +discover--manuals-here ()
  "((LABEL . ACTION) …): the manuals of the major mode (and those it derives
from), the Emacs manual's entry for it, those of the buffer's minor modes."
  (let* ((mode major-mode)
         (modes (append (if (fboundp 'derived-mode-all-parents)
                            (derived-mode-all-parents mode)
                          (list mode))
                        local-minor-modes))
         (in-emacs (save-current-buffer
                     (ignore-errors (Info-find-emacs-command-nodes mode))))
         seen out first)
    (dolist (m modes)
      (when-let* ((man (+discover--manual-of m)))
        (unless (member man seen)
          (push man seen)
          (push (cons (format "%-12s for %s" man m) (lambda () (info man))) out))
        (when (eq m mode) (setq first (length out)))))
    (setq out (nreverse out))
    ;; The Emacs manual's entry: after the mode's own manual, else first.
    (when in-emacs
      (let ((entry (cons (format "%-12s its entry for %s" "emacs" mode)
                         (lambda () (Info-goto-emacs-command-node mode)))))
        (setq out (if first
                      (append (seq-take out first) (list entry) (seq-drop out first))
                    (cons entry out)))))
    out))

(defun +discover/manual-here ()
  "The manual of this mode (or one of the minor modes on here)."
  (interactive)
  (require 'info)
  (let ((all (+discover--manuals-here)))
    (cond ((null all) (consult-info))
          ((null (cdr all)) (funcall (cdar all)))
          (t (funcall (cdr (assoc (completing-read "Manual: " all nil t) all)))))))

(defvar +discover-org-nodes
  '((headline . "Headlines") (table . "Tables") (table-row . "Tables") (table-cell . "Tables")
    (src-block . "Working with Source Code") (inline-src-block . "Structure of Code Blocks")
    (babel-call . "Evaluating Code Blocks") (example-block . "Literal Examples")
    (fixed-width . "Literal Examples") (link . "Hyperlinks") (timestamp . "Timestamps")
    (property-drawer . "Property Syntax") (node-property . "Property Syntax")
    (plain-list . "Plain Lists") (item . "Plain Lists") (clock . "Clocking Work Time")
    (keyword . "In-buffer Settings") (planning . "Deadlines and Scheduling")
    (drawer . "Drawers") (footnote-reference . "Creating Footnotes")
    (footnote-definition . "Creating Footnotes") (latex-fragment . "LaTeX fragments")
    (latex-environment . "LaTeX fragments") (horizontal-rule . "Horizontal Rules")
    (comment . "Comment Lines") (comment-block . "Comment Lines")
    (dynamic-block . "Dynamic Blocks") (target . "Internal Links")
    (radio-target . "Radio Targets") (macro . "Macro Replacement")
    (entity . "Special Symbols") (statistics-cookie . "Breaking Down Tasks")
    (bold . "Emphasis and Monospace") (italic . "Emphasis and Monospace")
    (code . "Emphasis and Monospace") (verbatim . "Emphasis and Monospace")
    (underline . "Emphasis and Monospace") (strike-through . "Emphasis and Monospace"))
  "Org element type → its node in the Org manual.")

(defun +discover/at-point (&optional chars)
  "What is this?  The Org manual's page on the Org thing at point, the doc
of the Lisp symbol at point, or (else, or with CHARS / C-u) the character:
its faces, text properties, overlays, buttons."
  (interactive "P")
  (let* ((sym (symbol-at-point))
         (node (and (not chars) (derived-mode-p 'org-mode)
                    (alist-get (org-element-type (org-element-context)) +discover-org-nodes))))
    (cond (node (info (format "(org) %s" node)))
          ((and (not chars) sym (not (derived-mode-p 'text-mode))
                (or (fboundp sym) (boundp sym) (facep sym)))
           (if (fboundp 'helpful-symbol) (helpful-symbol sym) (describe-symbol sym)))
          (t (describe-char (point))))))

(defun +discover/prefix ()
  "Press a prefix (SPC, SPC g, g, z, C-c, C-x…) and RET: search its keys.
A complete key instead: what it does."
  (interactive)
  (let ((keys []) binding)
    (while (let ((ev (read-key (format "Prefix: %s  (then RET to list its keys)"
                                       (if (zerop (length keys)) "…" (key-description keys))))))
             (if (and (memq ev '(?\r return)) (> (length keys) 0))
                 nil
               (setq keys (vconcat keys (vector ev))
                     binding (key-binding keys t))
               (cond ((keymapp binding) t)
                     (binding nil)
                     (t (user-error "%s does nothing here" (key-description keys)))))))
    (if (keymapp binding)
        (embark-bindings-in-keymap binding)
      (if (fboundp 'helpful-key) (helpful-key keys) (describe-key keys)))))

(defun +discover/ask-which ()
  "Describe what you want to do; the assistant names the command and key."
  (interactive)
  (familiar-ask (format "@echo Which Emacs command (name, and its key here if bound) does this: %s"
                        (read-string "Which command does… "))
                t))

(defun +discover/keys-of-mode ()
  "The keys of this buffer's modes only (no global ones), searchable."
  (interactive)
  (embark-bindings nil))

(defun +discover/all-keys ()
  "Every key active here, global ones too, searchable."
  (interactive)
  (embark-bindings t))

(defun +discover/prompt-command ()
  "The command this prompt belongs to."
  (interactive)
  (let ((cmd (with-current-buffer (window-buffer (minibuffer-window))
               current-minibuffer-command)))
    (if (and cmd (symbolp cmd))
        (if (fboundp 'helpful-callable) (helpful-callable cmd) (describe-function cmd))
      (user-error "No prompt is open"))))

;;;; C-ß: the menu

(defvar +discover--from nil "The buffer the menu was opened from.")

(defun +discover--here ()
  "The menu's first line: where you are."
  (let ((buf (if (buffer-live-p +discover--from) +discover--from (current-buffer))))
    (with-current-buffer buf
      (let ((sym (symbol-at-point)))
        (concat (propertize "Here: " 'face 'transient-heading)
                (propertize (format "%s" major-mode) 'face 'font-lock-type-face)
                (propertize (format "  %s" (buffer-name)) 'face 'shadow)
                (if (minibufferp)
                    (format "  prompt of %s" (or current-minibuffer-command "?"))
                  "")
                (if (and sym (or (fboundp sym) (boundp sym)))
                    (format "  at point: %s" (propertize (symbol-name sym) 'face 'font-lock-constant-face))
                  ""))))))

(defun +discover--org-p ()
  (with-current-buffer (if (buffer-live-p +discover--from) +discover--from (current-buffer))
    (derived-mode-p 'org-mode)))

(defun +discover--minibuffer-p ()
  (and (buffer-live-p +discover--from) (minibufferp +discover--from)))

(transient-define-prefix +discover-menu ()
  "Where to start looking."
  [:description +discover--here
   ["Search by words"
    ("C-ß" "Everything…"              +discover/anything)
    ("i" "Inside every manual"        consult-info)
    ("d" "In docstrings"              apropos-documentation)
    ("a" "By name"                    apropos)
    ("?" "Ask: which command does…"   +discover/ask-which)
    ("A" "Ask anything (M-ß)"         familiar-ask)
    ("w" "On the web"                 +lookup/online)]
   ["What is here"
    ("c" "Commands of these modes"    consult-mode-command)
    ("k" "Keys of these modes"        +discover/keys-of-mode)
    ("K" "All keys here"              +discover/all-keys)
    ("p" "Keys under a prefix…"       +discover/prefix)
    ("m" "The modes, explained"       describe-mode)
    ("h" "This mode's manual"         +discover/manual-here)
    ("." "What is this? (at point)"   +discover/at-point)
    ("s" "Settings of this mode"      customize-mode)
    ("o" "Org by example"             +org/cheatsheet :if +discover--org-p)]
   ["A key or a command"
    ("x" "What does a key do?"        helpful-key)
    ("W" "Which key runs…"            where-is)
    ("f" "Function, command"          helpful-callable)
    ("v" "Variable, option"           helpful-variable)
    ("F" "Face"                       describe-face)
    ("n" "Its page in the manual"     Info-goto-emacs-command-node)
    ("j" "A package"                  doom/describe-package)
    ("J" "A library's source"         find-library)
    ("T" "Every top-level key"        which-key-show-top-level)
    ("l" "What did I just press?"     view-lossage)
    ("e" "Messages so far"            view-echo-area-messages)]]
  [["This prompt"
    :if +discover--minibuffer-p
    ("P" "The command asking"         +discover/prompt-command)
    ("C-;" "Act on the candidate"     embark-act)
    ("E" "Candidates to a buffer"     embark-export)]
   ["Learn"
    ("t" "Emacs tutorial"             help-with-tutorial)
    ("q" "Cheat sheet"                help-quick-toggle)
    ("r" "Emacs manual"               info-emacs-manual)
    ("R" "A manual…"                  info-display-manual)
    ("I" "Continue reading"           +info/continue)
    ("D" "Doom's docs"                doom/docs)
    ("M" "A Doom module's docs"       doom/docs-module)]
   ["This config, your usage"
    ("/" "My own commands"            +docs/commands)
    ("L" "My learning path"           +docs/learn)
    ("u" "What to learn next"         +usage/suggest)
    ("g" "M-x searches given up"      +usage/mx-gave-up)
    ("U" "What I use (report)"        +usage/report)]])

;;;###autoload
(defun +discover ()
  "C-ß: where to start looking (see `+discover-menu')."
  (interactive)
  (setq +discover--from (current-buffer))
  (transient-setup '+discover-menu))

(map! "C-ß" #'+discover)
(map! :leader
      :desc "Find anything (C-ß)" "?" #'+discover
      (:prefix "h"
       :desc "Search every manual"        "D"   #'consult-info
       :desc "Commands of these modes"    "SPC" #'consult-mode-command))

(provide '+discover)
;;; +discover.el ends here
