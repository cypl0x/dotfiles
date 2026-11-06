;;; tools/familiar/config.el -*- lexical-binding: t; -*-
;;
;; familiar is an AI layer woven into Emacs, built on gptel: a package of its
;; own (lisp/familiar/, see familiar.el there), installed by this module's
;; packages.el.  This file only wires it into Doom: popups, keys, the spend
;; counter in the mode line, the bridges an Emacs daemon starts.
;;
;;   SPC A x / d / F / C / $   explain · explain diagnostic · fix · commit msg · spend
;;   SPC A E / v               explain the compilation error at point · review diff
;;   M-ß, SPC A ? / N / A      ask anything (familiar-ask) · fresh conversation · earlier ones
;;   SPC b R                   rename buffer; a name from its contents fills in (C-u: save too)
;;   SPC A H                   hand context at point to agent-shell / claude-code / clipboard
;;   M-g, SPC m g              in a commit message buffer: write the message
;;   X                         embark action on regions, defuns and identifiers
;;
;;; Code:

(dolist (cmd '(familiar-explain familiar-explain-diagnostic familiar-fix
               familiar-explain-compilation-error familiar-review familiar-handoff
               familiar-commit-message familiar-spend familiar-mode-line-mode
               familiar-rename-buffer))
  (autoload cmd "familiar" nil t))

;; Ask anything from anywhere (familiar-ask.el).  M-ß (one chord on a German
;; keyboard) is unbound in every loaded keymap and evil state, so one global
;; binding reaches it everywhere, M-x prompts included.  (C-M-? was the first
;; pick, but dired binds it in normal state.)
(autoload 'familiar-ask "familiar-ask" nil t)
(autoload 'familiar-ask-sessions "familiar-ask" nil t)
(autoload 'familiar-ask-new "familiar-ask" nil t)
(autoload 'familiar-ask-continue "familiar-ask" nil t)
(autoload 'familiar-ask-compose "familiar-ask" nil t)
(autoload 'familiar-rate-prompts "familiar-rate" nil t)
(autoload 'familiar-prompts-insert "familiar-prompts" nil t)
(autoload 'familiar-prompts-update "familiar-prompts" nil t)
(autoload 'familiar-complete "familiar-complete" nil t)
(autoload 'familiar-footprint "familiar-footprint" nil t)
(autoload 'familiar-analytics "familiar-analytics" nil t)
(dolist (fn '(familiar-peers familiar-peers-send familiar-peers-send-region familiar-peers-send-heading))
  (autoload fn "familiar-peers" nil t))
(with-eval-after-load '+agent
  ;; Write to your running Claude Code sessions (their own peer messaging).
  (transient-append-suffix '+agent/transient '(1 -1)
    ["Claude Code sessions"
     ("w" "Write to a session" familiar-peers-send)
     ("W" "Sessions" familiar-peers)
     ("o" "This Org item to a session" familiar-peers-send-heading)
     ("y" "Region to a session" familiar-peers-send-region)]))
(map! :leader :desc "AI analytics (familiar)" "o $" #'familiar-analytics)

;;;; SPC z: everything familiar does, and its settings, in one menu

(defvar familiar-budget)
(defvar familiar-models)
(defvar familiar-mcp-sampling)
(defvar familiar-mcp-sampling-mode)
(defvar familiar-mode-line-mode)
(declare-function familiar-spent "familiar" ())

(defun +familiar-menu--status ()
  "The menu's heading: spend against the budget, the models, sampling."
  (require 'familiar)
  (format "familiar · %s of %s spent · %s · MCP sampling: %s"
          (format "$%.2f" (familiar-spent))
          (if familiar-budget (format "$%.2f" familiar-budget) "no budget")
          (mapconcat (lambda (tm) (format "%s %s" (car tm)
                                          (replace-regexp-in-string "\\`claude-\\|-[0-9-]+\\'" "" (symbol-name (cdr tm)))))
                     familiar-models ", ")
          (if (bound-and-true-p familiar-mcp-sampling-mode)
              (bound-and-true-p familiar-mcp-sampling)
            "off")))

(defun +familiar/set-budget (usd)
  "Set familiar's budget to USD dollars (this session; customize keeps it)."
  (interactive (list (read-number "Budget in USD: " familiar-budget)))
  (customize-set-variable 'familiar-budget usd)
  (message "familiar: budget $%.2f (M-x customize-save-variable familiar-budget keeps it)" usd))

(defun +familiar/cycle-sampling ()
  "Cycle MCP sampling: ask, always, never."
  (interactive)
  (require 'familiar-mcp-sampling)
  (setq familiar-mcp-sampling (pcase familiar-mcp-sampling ('ask 'always) ('always 'never) (_ 'ask)))
  (message "familiar: MCP servers' completion requests: %s" familiar-mcp-sampling))

(transient-define-prefix +familiar-menu ()
  "familiar: everything it does, and its settings."
  [:description +familiar-menu--status
   ["Ask"
    ("?" "Ask anything (M-ß)" familiar-ask)
    ("+" "Follow-up" familiar-ask-continue)
    ("N" "New conversation" familiar-ask-new)
    ("A" "Earlier conversations" familiar-ask-sessions)
    ("m" "Show the conversation in a window" familiar-ask-raise)
    ("c" "Compose a long prompt" familiar-ask-compose)
    ("e" "Export a conversation" familiar-ask-export)
    ("p" "Insert a saved prompt" familiar-prompts-insert)]
   ["Code"
    ("x" "Explain" familiar-explain)
    ("d" "Explain diagnostic" familiar-explain-diagnostic)
    ("E" "Explain build error" familiar-explain-compilation-error)
    ("F" "Fix (smerge)" familiar-fix)
    ("v" "Review diff" familiar-review)
    ("C" "Commit message" familiar-commit-message)
    ("TAB" "Complete here" familiar-complete)
    ("R" "Rename buffer" familiar-rename-buffer)]
   ["Claude Code"
    ("w" "Write to a session" familiar-peers-send)
    ("W" "Sessions" familiar-peers)
    ("o" "This Org item to one" familiar-peers-send-heading)
    ("y" "Region to one" familiar-peers-send-region)
    ("H" "Hand off context" familiar-handoff)]]
  [["Looking back"
    ("$" "Spend" familiar-spend)
    ("a" "Analytics" familiar-analytics)
    ("j" "History of every turn" familiar-history)
    ("r" "Replay a turn" familiar-history-replay)
    ("L" "What the AI changed" familiar-footprint)
    ("P" "Review my prompts" familiar-rate-prompts)
    ("u" "Update saved prompts" familiar-prompts-update)]
   ["Bridges (for agents)"
    ("h" "MCP over HTTP: start" familiar-mcp-http-start)
    ("k" "MCP over HTTP: stop" familiar-mcp-http-stop)
    ("i" "ACP server: start" familiar-acp-start)
    ("I" "ACP server: stop" familiar-acp-stop)]
   ["Settings"
    ("b" "Budget…" +familiar/set-budget)
    ("s" "Sampling: ask/always/never" +familiar/cycle-sampling :transient t)
    ("S" "Sampling on/off" familiar-mcp-sampling-mode :transient t)
    ("l" "Spend in mode line" familiar-mode-line-mode :transient t)
    ("t" "Models and tiers…" (lambda () (interactive) (customize-variable 'familiar-models)))
    ("T" "Task tiers…" (lambda () (interactive) (customize-variable 'familiar-task-tiers)))
    ("," "All options…" (lambda () (interactive) (customize-group 'familiar)))]])

(map! :leader :desc "familiar (everything)" "z" #'+familiar-menu)
(after! +agent
  (transient-append-suffix '+agent/transient "$"
    '("Z" "All of familiar…" +familiar-menu)))
;; C-S-SPC: AI completions at point, ranked and explained (corfu-popupinfo).
(map! "C-S-SPC" #'familiar-complete
      :i "C-S-SPC" #'familiar-complete)
(map! "M-ß" #'familiar-ask
      "C-M-ß" #'familiar-ask-compose          ; straight into the multi-line prompt
      ;; rename-buffer, plus a name suggested from the contents.
      :leader :desc "Rename buffer (suggests)" "b R" #'familiar-rename-buffer)
(set-popup-rule! "^\\*familiar-ask\\*$" :side 'right :size 0.45 :select nil :quit nil :ttl nil
  ;; Doom popups skip other-window; this one is a conversation: SPC w w reaches it.
  :parameters '((no-other-window . nil)))
(set-popup-rule! "^\\*familiar-ask prompt\\*$" :size 0.3 :select t :quit nil)
;; SPC m m in a conversation: out of the side window into a regular one.
(map! :after familiar-ask :map familiar-ask-mode-map :localleader "m" #'familiar-ask-raise)

;; The prompt completes words too (+completion.el), as you type: corfu turns
;; itself on only in minibuffers that already have their own capfs, which
;; the prompt gets later in its setup.
(after! familiar
  ;; Every AI turn in one Org history (SPC A j).
  (require 'familiar-history))

;; M-ß prompts are rated as you pause typing (familiar-rate.el).
(after! familiar-ask
  (require 'familiar-rate)
  ;; @p:NAME: your prompts and Fabric's patterns (familiar-prompts.el).
  (require 'familiar-prompts)
  ;; What the model changed, apart from what you did (familiar-footprint.el).
  (require 'familiar-footprint))

(after! familiar-ask
  ;; RET sends at the end of a conversation in insert state too: evil's RET
  ;; won over the mode's map.  (C-c C-c sends from anywhere.)
  (after! evil
    (evil-define-key* 'insert familiar-ask-mode-map (kbd "RET") #'familiar-ask-ret))
  ;; @github, @nixos-mcp…: the MCP servers Claude Code knows for the project.
  (require 'familiar-mcp-client)
  ;; ...and when one of them asks for a completion (MCP sampling), familiar
  ;; answers: asking you first, budgeted, in the ledger.
  (require 'familiar-mcp-sampling)
  (familiar-mcp-sampling-mode 1)
  (add-to-list 'familiar-ask-prompt-capfs #'+completion-prose-capf t)
  (add-hook 'familiar-ask-prompt-setup-hook
            (defun +familiar-ask-corfu-h ()
              (when (fboundp 'corfu-mode) (corfu-mode 1)))))

;; MCP bridge for agents (claude mcp add ... emacs-mcp-stdio.sh
;; --init-function=familiar-mcp-start); see familiar-mcp.el.
(autoload 'familiar-mcp-start "familiar-mcp")
(autoload 'familiar-mcp-stop "familiar-mcp")

;; The same tools over HTTP, served by this Emacs (familiar-mcp-http.el):
;; http://127.0.0.1:39391/mcp with a bearer token, no emacsclient per
;; message.  Only the main daemon serves: test daemons would take the port.
(autoload 'familiar-mcp-http-start "familiar-mcp-http" nil t)
(autoload 'familiar-mcp-http-stop "familiar-mcp-http" nil t)
(autoload 'familiar-acp-start "familiar-acp" nil t)
(autoload 'familiar-acp-stop "familiar-acp" nil t)
(when (eq (daemonp) t)
  (run-with-idle-timer
   3 nil (lambda ()
           (condition-case err
               (progn (require 'familiar-openai)   ; /v1/: OpenAI-compatible, same server
                      (require 'familiar-atuin)    ; /api/cli/: Atuin AI's server
                      (require 'familiar-a2a)      ; /a2a and its agent card
                      (familiar-mcp-http-start)
                      (familiar-acp-start))       ; ACP agent (familiar-acp command)
             (error (message "familiar MCP over HTTP not started: %s" (error-message-string err)))))))

(after! familiar
  ;; Show the budget against what the key is actually charged with.
  (setq familiar-budget 10.0)
  ;; Your call (2026-11-04): M-ß runs every tool, eval_elisp included, without
  ;; asking.  Text the model reads could steer it; set to 'auto to approve
  ;; evals and edits one by one again.
  (setq familiar-ask-confirm-tools nil)
  ;; Hand off to agent-shell even when none runs: start one (+agent.el), the
  ;; prompt waits until it's ready.  Clipboard stays as the last resort.
  (setf (alist-get 'agent-shell familiar-handoff-targets)
        (list :available (lambda () (locate-library "agent-shell"))
              :send (lambda (text)
                      (agent-shell-insert :text text :submit t
                                          :shell-buffer (+agent-shell-buffer))))))

(set-popup-rule! "^\\*familiar\\*$" :size 0.35 :select nil :quit t :ttl nil
  :parameters '((no-other-window . nil)))  ; an answer to read: SPC w w reaches it
(set-popup-rule! "^\\*familiar spend\\*$" :size 0.4 :select t :quit t)

;; The spend counter loads familiar (and so gptel); do it when Emacs is idle
;; rather than at startup.
(defun +familiar-mode-line-h ()
  (run-with-idle-timer 3 nil #'familiar-mode-line-mode 1))
(add-hook 'doom-after-init-hook #'+familiar-mode-line-h)

;; `ß' at an empty shell prompt asks familiar, as in zsh
;; (home/shell/zsh/familiar-ai.zsh; ghostel runs zsh itself, so it works
;; there).  `?' is Atuin's AI, as in zsh too (lisp/+atuin-ai.el).  Elsewhere
;; they are just typed.
(defun +familiar/shell-question-mark ()
  "At an empty eshell or shell prompt, `familiar-ask'; else type the key."
  (interactive)
  (if (and (eobp)
           (cond ((derived-mode-p 'eshell-mode)
                  (= (point) (marker-position eshell-last-output-end)))
                 ((derived-mode-p 'comint-mode)
                  (when-let* ((proc (get-buffer-process (current-buffer))))
                    (= (point) (marker-position (process-mark proc)))))))
      (call-interactively #'familiar-ask)
    (self-insert-command 1)))

(map! :after eshell :map eshell-mode-map :i "ß" #'+familiar/shell-question-mark)
(map! :after shell :map shell-mode-map :i "ß" #'+familiar/shell-question-mark)

(after! git-commit
  (map! :map git-commit-mode-map
        "M-g" #'familiar-commit-message
        :localleader
        :desc "Write message (familiar)" "g" #'familiar-commit-message))

(after! embark
  (map! :map (embark-region-map embark-defun-map embark-identifier-map)
        "X" #'familiar-explain))

;; C-c p picks a saved prompt in M-ß (the package itself binds C-c C-p:
;; C-c and a plain letter are the user's).
(after! familiar-prompts
  (define-key familiar-ask-minibuffer-map (kbd "C-c p") #'familiar-prompts-insert))

;;; config.el ends here
