;;; lisp/+dashboard.el --- Custom dashboard sections -*- lexical-binding: t; -*-
;;
;; Extends the Doom dashboard with system info, agent status, quick
;; launchers, and feature discovery.
;;
;;; Code:

;;;; Master command hub ──────────────────────────────────────────────────────

;; Wrapper commands for lazy autoload — avoids transient errors when
;; referenced packages haven't loaded yet.
(defun +dashboard/start-claude ()
  "Start Claude agent-shell session." (interactive)
  (call-interactively #'agent-shell-anthropic-start-claude-code))
(defun +dashboard/gptel-menu ()
  "Open gptel menu." (interactive) (call-interactively #'gptel-menu))
(defun +dashboard/roam-find ()
  "Find org-roam node." (interactive) (call-interactively #'org-roam-node-find))
(defun +dashboard/roam-daily ()
  "Go to today's daily note." (interactive) (call-interactively #'org-roam-dailies-goto-today))
(defun +dashboard/ql-view ()
  "Open org-ql views." (interactive) (call-interactively #'org-ql-view))

(transient-define-prefix +dashboard/hub ()
    "Configuration & feature hub — the starting point for everything."
    ["AI Agents"
     ("a" "Agent menu (AI)"      +agent/transient)
     ("A" "Start Claude session" +dashboard/start-claude)
     ("g" "gptel (inline LLM)"  +dashboard/gptel-menu)]
    ["Knowledge"
     ("r" "Org-roam find node"  +dashboard/roam-find)
     ("c" "Org capture"          org-capture)
     ("v" "Org-ql views"        +dashboard/ql-view)
     ("n" "Daily note"          +dashboard/roam-daily)]
    ["Proof Assistants"
     ("D" "DTT menu"             +dtt/transient)
     ("u" "Agda Unicode toggle"  +dtt/toggle-agda-input)
     ("s" "Proof status"         +dtt/proof-status)]
    ["System"
     ("N" "NixOS menu"           +nix/transient)
     ("R" "Remote (TRAMP)"       +tramp/connection-info)
     ("F" "Font showcase"        +fonts/ligature-showcase)]
    ["Writing"
     ("w" "Writing mode"         +prose/writing-mode)
     ("P" "Prose stats"          +prose/text-stats)
     ("W" "Word frequency"       +prose/word-frequency)]
    ["Help"
     ("?" "Help & discovery"     +nav/help-transient)
     ("b" "Buffer menu"          +nav/buffer-transient)
     ("q" "Quit"                 transient-quit-one)])

;;;; Dashboard menu item ─────────────────────────────────────────────────────

;; Add a custom section to Doom's dashboard.  The Doom dashboard supports
;; custom "menu" entries via `+doom-dashboard-menu-sections'.

(after! doom-dashboard
  ;; Append a section that opens our hub transient.
  (add-to-list '+doom-dashboard-menu-sections
               '("Open Feature Hub"
                 :icon (nerd-icons-faicon "nf-fa-rocket" :face 'doom-dashboard-menu-title)
                 :action +dashboard/hub)
               t)

  ;; Also add quick launchers.
  (add-to-list '+doom-dashboard-menu-sections
               '("Start AI Agent"
                 :icon (nerd-icons-faicon "nf-fa-bolt" :face 'doom-dashboard-menu-title)
                 :action agent-shell-anthropic-start-claude-code)
               t)

  (add-to-list '+doom-dashboard-menu-sections
               '("Find Knowledge Node"
                 :icon (nerd-icons-faicon "nf-fa-brain" :face 'doom-dashboard-menu-title)
                 :action org-roam-node-find)
               t)

  (add-to-list '+doom-dashboard-menu-sections
               '("NixOS Operations"
                 :icon (nerd-icons-faicon "nf-fa-cog" :face 'doom-dashboard-menu-title)
                 :action +nix/transient)
               t))

;;;; System overview command ─────────────────────────────────────────────────

(defun +dashboard/system-overview ()
  "Show a comprehensive system overview in a buffer."
  (interactive)
  (let ((buf (get-buffer-create "*System Overview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "System Overview\n" 'face '(:height 1.5 :weight bold))
                (format "Generated: %s\n\n" (format-time-string "%Y-%m-%d %H:%M"))

                (propertize "═══ Environment ═══\n" 'face '(:weight bold))
                (format "Emacs:     %s\n" emacs-version)
                (format "Doom:      %s\n" doom-version)
                (format "System:    %s\n" system-type)
                (format "Host:      %s\n" (system-name))
                (format "User:      %s\n\n" user-login-name)

                (propertize "═══ Buffers ═══\n" 'face '(:weight bold))
                (format "Total:     %d\n" (length (buffer-list)))
                (format "Files:     %d\n" (length (seq-filter #'buffer-file-name (buffer-list))))
                (format "Modified:  %d\n" (length (seq-filter #'buffer-modified-p (buffer-list))))
                (format "Processes: %d\n\n" (length (process-list)))

                (propertize "═══ AI Sessions ═══\n" 'face '(:weight bold))
                (format "agent-shell: %d\n"
                        (length (seq-filter
                                 (lambda (b) (with-current-buffer b
                                               (derived-mode-p 'agent-shell-mode)))
                                 (buffer-list))))
                (format "monet servers: %d\n"
                        (if (boundp 'monet--sessions)
                            (hash-table-count monet--sessions) 0))
                "\n"

                (propertize "═══ Proof Assistants ═══\n" 'face '(:weight bold))
                (format "Agda buffers:  %d\n"
                        (length (seq-filter (lambda (b) (with-current-buffer b (derived-mode-p 'agda2-mode))) (buffer-list))))
                (format "Lean buffers:  %d\n"
                        (length (seq-filter (lambda (b) (with-current-buffer b (derived-mode-p 'lean4-mode))) (buffer-list))))
                (format "Coq buffers:   %d\n"
                        (length (seq-filter (lambda (b) (with-current-buffer b (derived-mode-p 'coq-mode))) (buffer-list))))
                "\n"

                (propertize "═══ TRAMP ═══\n" 'face '(:weight bold))
                (format "Method:    %s\n" (bound-and-true-p tramp-default-method))
                (format "Connections: %d\n" (length (tramp-list-connections))))
        (goto-char (point-min))
        (view-mode 1)))
    (pop-to-buffer buf)))

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      :desc "Feature hub"       "H" #'+dashboard/hub
      :desc "System overview"   "I" #'+dashboard/system-overview)

(provide '+dashboard)
;;; +dashboard.el ends here
