;;; lisp/+well-formed.el --- Doom integration for well-formed (lisp/well-formed/) -*- lexical-binding: t; -*-
;;
;; well-formed is the writing assistant: Grammarly's categories (correctness,
;; clarity, engagement, delivery, consistency) as rules and statistics in
;; Emacs Lisp, English and German; see lisp/well-formed/well-formed.el.  It
;; replaced LanguageTool (ltex-ls-plus through eglot), which held 2.8 GB of
;; Java per project, took 30 s to start, and made SPC X capture buffers wait
;; on it.  This file wires it in: on in prose buffers (files or not),
;; findings through flycheck after the mode's own checker, keys.
;;
;;   SPC P m   the menu: the finding here, the text, style, categories
;;   SPC P x   fix the finding at point (rule-based, or rewritten with AI)
;;   SPC P X   fix one rule throughout
;;   SPC P g   ignore it (here, the rule here, everywhere)
;;   SPC P e   explain its rule             SPC P L   every finding (consult)
;;   SPC P v   the report: scores, readability, tone, plots
;;   SPC P S   style for this buffer (a document: #+well_formed: academic)
;;   ]e / [e   next / previous (flycheck), embark (C-;) acts on a finding
;;
;;; Code:

(add-to-list 'load-path (expand-file-name "lisp/well-formed" doom-user-dir))

(dolist (cmd '(well-formed-mode global-well-formed-mode well-formed-fix well-formed-fix-all
               well-formed-ignore well-formed-unignore well-formed-explain well-formed-list
               well-formed-next well-formed-previous well-formed-set-style well-formed-toggle-category))
  (autoload cmd "well-formed" nil t))
(autoload 'well-formed-report "well-formed-report" nil t)
(autoload 'well-formed-menu "well-formed-menu" nil t)
(autoload 'well-formed-ai-report "well-formed-ai" nil t)
(autoload 'well-formed-ai-mode "well-formed-ai" nil t)

;; On after startup: the rules load (about 20 ms) a second after the first
;; buffer, not while Emacs starts (an idle timer never fired in a daemon
;; nobody had typed in yet).  The report's time tracking comes with it.
(add-hook 'doom-first-buffer-hook
          (defun +well-formed-enable-h ()
            (run-with-timer 1 nil
                                 (lambda ()
                                   (require 'well-formed)
                                   (require 'well-formed-report)
                                   (global-well-formed-mode 1)
                                   ;; The model's reading too (you asked for it on by default).
                                   (when (require 'well-formed-ai nil t)
                                     (well-formed-ai-mode 1))))))


;; Every finding can be fixed: rule-based fixes first (a split for a long
;; sentence, the active form of "was done by", the word to use), and for
;; any finding "Rewrite the sentence with AI…": familiar rewrites the
;; sentence toward the finding's message and +prose/improve shows the
;; change word by word (C-c C-c applies it, g asks again, q keeps yours).
(declare-function +prose--improve-ask "+prose" (buf beg end goal))
(defvar well-formed-rewrite-function)
(setq well-formed-rewrite-function
      (lambda (beg end goal)
        (+prose--improve-ask (current-buffer) (copy-marker beg) (copy-marker end t) goal)))

;; Not in AI conversations (familiar-ask, gptel): the findings there were
;; mostly about the model's answers.
(add-hook 'well-formed-inhibit-functions
          (defun +well-formed-ai-chat-p ()
            (or (bound-and-true-p gptel-mode)
                (string-match-p "\\`\\*\\(?:familiar\\|gptel\\|claude\\)" (buffer-name)))))
(map! :leader
      (:prefix ("P" . "prose")
       :desc "Writing assistant menu" "m" #'well-formed-menu
       :desc "Fix finding"            "x" #'well-formed-fix
       :desc "Fix rule throughout"    "X" #'well-formed-fix-all
       :desc "Ignore finding"         "g" #'well-formed-ignore
       :desc "Explain finding"        "e" #'well-formed-explain
       :desc "List findings"          "L" #'well-formed-list
       :desc "Writing style"          "S" #'well-formed-set-style
       :desc "AI assessment"          "a" #'well-formed-ai-report))

(provide '+well-formed)
;;; +well-formed.el ends here
