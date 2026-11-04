;;; lisp/+familiar.el --- Doom integration for familiar (lisp/familiar/) -*- lexical-binding: t; -*-
;;
;; familiar is an AI layer woven into Emacs, built on gptel; see
;; lisp/familiar/familiar.el.  This file only wires it into Doom: lazy loading,
;; popups, keys, and the spend counter in the mode line.
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

(add-to-list 'load-path (expand-file-name "lisp/familiar" doom-user-dir))

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
(map! "M-ß" #'familiar-ask
      ;; rename-buffer, plus a name suggested from the contents.
      :leader :desc "Rename buffer (suggests)" "b R" #'familiar-rename-buffer)
(set-popup-rule! "^\\*familiar-ask\\*$" :side 'right :size 0.45 :select nil :quit nil :ttl nil
  ;; Doom popups skip other-window; this one is a conversation: SPC w w reaches it.
  :parameters '((no-other-window . nil)))
(set-popup-rule! "^\\*familiar-ask prompt\\*$" :size 0.3 :select t :quit nil)

;; The prompt completes words too (+completion.el), as you type: corfu turns
;; itself on only in minibuffers that already have their own capfs, which
;; the prompt gets later in its setup.
(after! familiar-ask
  ;; @github, @nixos-mcp…: the MCP servers Claude Code knows for the project.
  (require 'familiar-mcp-client)
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
(when (eq (daemonp) t)
  (run-with-idle-timer
   3 nil (lambda ()
           (condition-case err
               (progn (require 'familiar-openai)   ; /v1/: OpenAI-compatible, same server
                      (familiar-mcp-http-start))
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

;; `?' at an empty shell prompt asks, as Atuin's `?' does in zsh (ghostel runs
;; zsh itself, so Atuin's own works there).  Elsewhere `?' is just `?'.
(defun +familiar/shell-question-mark ()
  "At an empty eshell or shell prompt, `familiar-ask'; else insert ?."
  (interactive)
  (if (and (eobp)
           (cond ((derived-mode-p 'eshell-mode)
                  (= (point) (marker-position eshell-last-output-end)))
                 ((derived-mode-p 'comint-mode)
                  (when-let* ((proc (get-buffer-process (current-buffer))))
                    (= (point) (marker-position (process-mark proc)))))))
      (call-interactively #'familiar-ask)
    (self-insert-command 1 ??)))

(map! :after eshell :map eshell-mode-map :i "?" #'+familiar/shell-question-mark)
(map! :after shell :map shell-mode-map :i "?" #'+familiar/shell-question-mark)

(after! git-commit
  (map! :map git-commit-mode-map
        "M-g" #'familiar-commit-message
        :localleader
        :desc "Write message (familiar)" "g" #'familiar-commit-message))

(after! embark
  (map! :map (embark-region-map embark-defun-map embark-identifier-map)
        "X" #'familiar-explain))

(provide '+familiar)
;;; +familiar.el ends here
