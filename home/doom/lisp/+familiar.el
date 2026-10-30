;;; lisp/+familiar.el --- Doom integration for familiar (lisp/familiar/) -*- lexical-binding: t; -*-
;;
;; familiar is an AI layer woven into Emacs, built on gptel; see
;; lisp/familiar/familiar.el.  This file only wires it into Doom: lazy loading,
;; popups, keys, and the spend counter in the mode line.
;;
;;   SPC A x / d / F / C / $   explain · explain diagnostic · fix · commit msg · spend
;;   SPC A E / v               explain the compilation error at point · review diff
;;   M-g, SPC m g              in a commit message buffer: write the message
;;   X                         embark action on regions, defuns and identifiers
;;
;;; Code:

(add-to-list 'load-path (expand-file-name "lisp/familiar" doom-user-dir))

(dolist (cmd '(familiar-explain familiar-explain-diagnostic familiar-fix
               familiar-explain-compilation-error familiar-review
               familiar-commit-message familiar-spend familiar-mode-line-mode))
  (autoload cmd "familiar" nil t))

(after! familiar
  ;; Show the budget against what the key is actually charged with.
  (setq familiar-budget 10.0))

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
