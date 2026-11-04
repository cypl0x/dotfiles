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
(map! "M-ß" #'familiar-ask
      ;; rename-buffer, plus a name suggested from the contents.
      :leader :desc "Rename buffer (suggests)" "b R" #'familiar-rename-buffer)
(set-popup-rule! "^\\*familiar-ask\\*$" :side 'right :size 0.45 :select nil :quit nil :ttl nil)
(set-popup-rule! "^\\*familiar-ask prompt\\*$" :size 0.3 :select t :quit nil)

;; MCP bridge for agents (claude mcp add ... emacs-mcp-stdio.sh
;; --init-function=familiar-mcp-start); see familiar-mcp.el.
(autoload 'familiar-mcp-start "familiar-mcp")
(autoload 'familiar-mcp-stop "familiar-mcp")

(after! familiar
  ;; Show the budget against what the key is actually charged with.
  (setq familiar-budget 10.0)
  ;; Hand off to agent-shell even when none runs: start one (+agent.el), the
  ;; prompt waits until it's ready.  Clipboard stays as the last resort.
  (setf (alist-get 'agent-shell familiar-handoff-targets)
        (list :available (lambda () (locate-library "agent-shell"))
              :send (lambda (text)
                      (agent-shell-insert :text text :submit t
                                          :shell-buffer (+agent-shell-buffer))))))

(set-popup-rule! "^\\*familiar\\*$" :size 0.35 :select nil :quit t :ttl nil)
(set-popup-rule! "^\\*familiar spend\\*$" :size 0.4 :select t :quit t)

;; The spend counter loads familiar (and so gptel); do it when Emacs is idle
;; rather than at startup.
(defun +familiar-mode-line-h ()
  (run-with-idle-timer 3 nil #'familiar-mode-line-mode 1))
(add-hook 'doom-after-init-hook #'+familiar-mode-line-h)

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
