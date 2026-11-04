;;; lisp/+suggest.el --- Copilot-like inline suggestions (minuet, Claude) -*- lexical-binding: t; -*-
;;
;; As you pause typing code, a suggestion for what comes next shows as ghost
;; text after point: the rest of the line or a whole block.  minuet-ai.el
;; does it, with Claude (the fast model, the API key gptel already uses).
;;
;;   TAB     take the whole suggestion
;;   M-RET   take its first line (C-u N M-RET: N lines)
;;   M-]  M-[   next / previous suggestion
;;   C-g     dismiss
;;
;; In code buffers on their own (prog-mode); M-x minuet-show-suggestion
;; anywhere else.  With corfu's popup open too, TAB is corfu's (its map
;; comes first); once it's closed, TAB takes the suggestion.
;; Each pause is a request: debounce and throttle keep them few.
;;
;;; Code:

(declare-function gptel-api-key-from-auth-source "gptel" (&optional host user))

(defvar +suggest--key nil "The Anthropic API key, looked up once.")

(defun +suggest-api-key ()
  "The Anthropic key from auth-source, as gptel finds it (cached: minuet
asks before every request)."
  (or +suggest--key
      (setq +suggest--key (gptel-api-key-from-auth-source "api.anthropic.com"))))

(use-package! minuet
  :hook (prog-mode . minuet-auto-suggestion-mode)
  :config
  (setq minuet-provider 'claude
        minuet-auto-suggestion-debounce-delay 0.8
        minuet-auto-suggestion-throttle-delay 2.0)
  (plist-put minuet-claude-options :api-key #'+suggest-api-key)
  (map! :map minuet-active-mode-map
        "TAB"   #'minuet-accept-suggestion
        [tab]   #'minuet-accept-suggestion
        "M-RET" #'minuet-accept-suggestion-line
        "M-]"   #'minuet-next-suggestion
        "M-["   #'minuet-previous-suggestion
        "C-g"   #'minuet-dismiss-suggestion))

(provide '+suggest)
;;; +suggest.el ends here
