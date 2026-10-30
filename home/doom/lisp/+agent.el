;;; lisp/+agent.el --- AI agent integration layer -*- lexical-binding: t; -*-
;;
;; Transient menu, quick-ask, agent status, gptel config, MCP bridge,
;; and unified AI keybindings for agent-shell, gptel, and Claude Code.
;;
;;; Code:

;;;; Permission auto-allow ───────────────────────────────────────────────────

(after! agent-shell
  (setq agent-shell-permission-responder-function
        #'agent-shell-permission-allow-always))

;;;; Quick-ask — minibuffer prompt without context switch ────────────────────

(defun +agent/quick-ask (prompt)
  "Send PROMPT to the current or most recent agent-shell buffer.
With active region, prepend selected text as context."
  (interactive
   (list (let ((initial (when (use-region-p)
                          (buffer-substring-no-properties
                           (region-beginning) (region-end)))))
           (read-string "Ask agent: "
                        (when initial
                          (concat "Context:\n" initial "\n\nQuestion: "))))))
  (let* ((shell-buf (or (seq-find
                          (lambda (b)
                            (with-current-buffer b
                              (derived-mode-p 'agent-shell-mode)))
                          (buffer-list))
                         (error "No agent-shell buffer found")))
         (buf-name (buffer-name shell-buf)))
    (with-current-buffer shell-buf
      (goto-char (point-max))
      (insert prompt)
      (agent-shell-submit))
    (message "Sent to %s" buf-name)))

;;;; Send buffer/region to agent ─────────────────────────────────────────────

(defun +agent/send-buffer ()
  "Send entire buffer content to the current agent-shell session."
  (interactive)
  (let ((content (buffer-substring-no-properties (point-min) (point-max)))
        (fname (or (buffer-file-name) (buffer-name))))
    (+agent/quick-ask
     (format "Here is the content of `%s`:\n\n```\n%s\n```\n\nWhat do you think?"
             fname content))))

(defun +agent/explain-region ()
  "Send region to agent with request to explain."
  (interactive)
  (unless (use-region-p) (user-error "No active region"))
  (let ((text (buffer-substring-no-properties (region-beginning) (region-end)))
        (mode (symbol-name major-mode)))
    (+agent/quick-ask
     (format "Explain this %s code:\n\n```\n%s\n```" mode text))))

(defun +agent/fix-region ()
  "Send region to agent with request to fix/improve."
  (interactive)
  (unless (use-region-p) (user-error "No active region"))
  (let ((text (buffer-substring-no-properties (region-beginning) (region-end)))
        (mode (symbol-name major-mode)))
    (+agent/quick-ask
     (format "Fix or improve this %s code. Show only the corrected version:\n\n```\n%s\n```"
             mode text))))

;;;; Agent status ────────────────────────────────────────────────────────────

(defun +agent/list-sessions ()
  "Show all active agent-shell sessions in a buffer."
  (interactive)
  (let ((buf (get-buffer-create "*Agent Sessions*"))
        (sessions (seq-filter
                   (lambda (b)
                     (with-current-buffer b
                       (derived-mode-p 'agent-shell-mode)))
                   (buffer-list))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Active Agent Sessions\n\n" 'face '(:height 1.3 :weight bold)))
        (if (null sessions)
            (insert "No active sessions.\n")
          (dolist (s sessions)
            (insert (format "  %s  %s\n"
                            (propertize "●" 'face 'success)
                            (buffer-name s))))))
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

;;;; gptel — LLM in any buffer ───────────────────────────────────────────────

(use-package! gptel
  :defer t
  :config
  ;; Claude backend — key from ~/.authinfo (plain text, chmod 600):
  ;;   machine api.anthropic.com login apikey password sk-ant-...
  (auth-source-forget-all-cached)
  (auth-source-forget-all-cached)
  (setq gptel-model 'claude-sonnet-4-6
        gptel-api-key (auth-source-pick-first-password :host "api.anthropic.com")
        gptel-backend
        (gptel-make-anthropic "Claude"
          :stream t
          :key (auth-source-pick-first-password :host "api.anthropic.com")
          :models '(claude-sonnet-4-6
                    claude-opus-4-6
                    claude-haiku-4-5-20251001
                    claude-sonnet-5-5
                    claude-opus-5-5))
        gptel-default-mode 'org-mode))

;;;; Transient menu — unified AI dispatch ────────────────────────────────────

;; Lazy wrappers for autoload safety in transient.
(defun +agent/start-claude ()
  "Start Claude." (interactive) (call-interactively #'agent-shell-anthropic-start-claude-code))
(defun +agent/switch-buf ()
  "Switch agent buffer." (interactive) (call-interactively #'agent-shell-switch-buffer))
(defun +agent/help ()
  "Agent help." (interactive) (call-interactively #'agent-shell-help-menu))
(defun +agent/send-reg ()
  "Send region." (interactive) (call-interactively #'agent-shell-send-region))

(transient-define-prefix +agent/transient ()
    "AI Agent dispatch menu."
    ["Agent Shell"
     ("s" "Start Claude"     +agent/start-claude)
     ("S" "Switch buffer"    +agent/switch-buf)
     ("l" "List sessions"    +agent/list-sessions)
     ("h" "Help menu"        +agent/help)]
    ["Quick Actions"
     ("a" "Ask (minibuffer)" +agent/quick-ask)
     ("e" "Explain region"   +agent/explain-region)
     ("f" "Fix region"       +agent/fix-region)
     ("b" "Send buffer"      +agent/send-buffer)
     ("r" "Send region"      +agent/send-reg)]
    ["gptel (inline LLM)"
     ("g" "gptel send"       gptel-send)
     ("G" "gptel menu"       gptel-menu)
     ("c" "gptel chat"       gptel)
     ("m" "Set model"        gptel-set-model)]
    ["Tools"
     ("t" "ACP traffic"      agent-shell-view-acp-logs)
     ("T" "Transcript"       agent-shell-open-transcript)
     ("u" "Usage"            agent-shell-show-usage)]
    ["History"
     ("R" "Recall transcripts"  agent-recall)
     ("X" "Reindex transcripts" agent-recall-reindex)])

;;;; monet + agent-shell bridge ──────────────────────────────────────────────

(after! (:and agent-shell monet)
  (defadvice! +agent/monet-inject-env (fn &rest args)
    "Inject monet IDE env vars into agent-shell sessions."
    :around #'agent-shell-anthropic-make-claude-client
    (let* ((session (monet-start-server-in-directory
                     (or (when (fboundp 'projectile-project-name)
                           (projectile-project-name))
                         "default")
                     default-directory))
           (port (monet--session-port session))
           (agent-shell-anthropic-claude-environment
            (append agent-shell-anthropic-claude-environment
                    (list "ENABLE_IDE_INTEGRATION=t"
                          (format "CLAUDE_CODE_SSE_PORT=%d" port)))))
      (apply fn args))))

;;;; agent-shell ecosystem ────────────────────────────────────────────────────

(use-package! agent-recall
  :after agent-shell
  :config
  ;; Index all Claude Code + agent-shell transcripts.
  (setq agent-recall-search-paths
        '("~/.claude/transcripts"       ; Claude Code CLI sessions
          "~/.agent-shell/transcripts"   ; agent-shell global
          "~/todo"                       ; per-project agent-shell dirs
          "~/dotfiles"
          "~/dev"))
)

;; Add recall to agent transient instead of SPC A prefix (SPC A = transient command, not prefix)


(use-package! agent-shell-attention
  :after agent-shell
  :config
  (agent-shell-attention-mode 1))

(use-package! agent-shell-math-renderer
  :after agent-shell)

(use-package! ob-agent-shell
  :after (:all org agent-shell))

;;;; powerthesaurus ──────────────────────────────────────────────────────────

(use-package! powerthesaurus
  :defer t
  :config
  (map! :leader
        (:prefix "P"
         :desc "Thesaurus (dwim)" "t" #'powerthesaurus-lookup-dwim)))

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      :desc "AI agent menu"    "A" #'+agent/transient)

(provide '+agent)
;;; +agent.el ends here
