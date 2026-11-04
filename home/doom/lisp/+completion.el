;;; lisp/+completion.el --- C-SPC completes for where you are -*- lexical-binding: t; -*-
;;
;; C-SPC in insert state (it fell through to `set-mark-command') completes
;; with sources picked by context, shown by corfu as usual:
;;
;;   Org link after [[        org-roam nodes, then files
;;   Org #+keyword, :tags:    Org's own (pcomplete): keywords, tags, properties
;;   Org src block            the block's code (cape-elisp-block for elisp)
;;   prose: Org/Markdown/text, comments, strings
;;                            dictionary (English + German) and buffer words
;;   code                     the mode's own (eglot, elisp), buffer words, files
;;
;; The dictionaries are plain word lists built from the hunspell ones jinx
;; uses (home/emacs-deps.nix); `cape-dict-file' pointed at
;; /usr/share/dict/words, which NixOS doesn't have.
;;
;;; Code:

(declare-function cape-dict "ext:cape" (&optional interactive))
(declare-function cape-dabbrev "ext:cape" (&optional interactive))
(declare-function cape-file "ext:cape" (&optional interactive))
(declare-function cape-elisp-block "ext:cape" (&optional interactive))
(declare-function cape-capf-super "ext:cape" (&rest capfs))
(declare-function org-in-src-block-p "org" (&optional inside element))
(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(declare-function org-roam-complete-link-at-point "ext:org-roam-mode" ())
(declare-function pcomplete-completions-at-point "pcomplete" ())
(defvar cape-dict-file)
(defvar cape-dabbrev-buffer-function)
(declare-function cape--dabbrev-list "ext:cape" (input))
(declare-function cape--dict-list "ext:cape" (input))

(defvar +completion-dict-files
  (seq-filter #'file-exists-p
              (mapcan (lambda (dir)
                        (list (expand-file-name "words-en" dir)
                              (expand-file-name "words-de" dir)))
                      (list (expand-file-name "dict" (or (getenv "XDG_DATA_HOME") "~/.local/share")))))
  "Word lists for `cape-dict' (home/emacs-deps.nix: dict-words).")

(with-eval-after-load 'cape
  (when +completion-dict-files
    (setq cape-dict-file +completion-dict-files)))

(defun +completion--word-buffers ()
  "Buffers whose words prose completion offers.
From the minibuffer, the buffers on screen: the M-ß prompt asks about them."
  (if (minibufferp)
      (delete-dups (mapcar #'window-buffer
                           (window-list (window-frame (minibuffer-selected-window)) 'nomini)))
    (ensure-list (funcall cape-dabbrev-buffer-function))))

(defun +completion--words (input)
  "Words starting with INPUT: from buffers first, then the dictionaries.
One list without duplicates (`cape-capf-super' keeps a word once per source)."
  (let ((buffers (+completion--word-buffers))
        (case-fold-search nil))
    (seq-filter
     ;; Prose words only: dabbrev also brings code tokens (Work*, WordMap).
     (lambda (w) (string-match-p "\\`[[:alpha:]]\\(?:[[:lower:]'-]*\\|[[:upper:]]*\\)\\'" w))
     (delete-dups
      (append (cdr (dlet ((cape-dabbrev-buffer-function (lambda () buffers)))
                     (cape--dabbrev-list input)))
              (cdr (cape--dict-list input)))))))

(defun +completion-prose-capf ()
  "Complete words in prose (Org/Markdown/text, comments, strings, prompts).
Recomputed as the input grows, so a longer prefix still finds words past
the dictionaries' first `cape-dict-limit' matches.  The words are looked up
for the text typed, not the string the completion style asks with:
orderless asks with \"\", and dabbrev took 30 s collecting every word of
every Org buffer (11,448 of them, duplicate check quadratic)."
  (when (or (minibufferp) (eq (+completion-context) 'prose))
    (when-let* ((bounds (bounds-of-thing-at-point 'word))
                ((<= (+ (car bounds) 2) (point))))
      (let ((beg (copy-marker (car bounds))) input words)
        (list beg (point)
              (lambda (string pred action)
                (let ((typed (with-current-buffer (marker-buffer beg)
                               (buffer-substring-no-properties beg (max beg (point))))))
                  (unless (equal typed input)
                    (setq input typed
                          words (and (length> typed 1) (+completion--words typed))))
                  (complete-with-action action words string pred)))
              :exclusive 'no
              :company-kind (lambda (_) 'text))))))

(defun +completion--prose ()
  (list #'+completion-prose-capf))

;; corfu completes as you type, but in Org nothing offered words: Org's
;; capfs are keywords, tags and src blocks only.
(add-hook 'text-mode-hook
          (defun +completion-prose-h ()
            (add-hook 'completion-at-point-functions #'+completion-prose-capf 90 t)))

(defun +completion-context ()
  "What point is in, for choosing completion sources: a symbol."
  (cond ((derived-mode-p 'org-mode)
         (cond ((looking-back "\\[\\[[^]\n]*" (line-beginning-position)) 'org-link)
               ((looking-back "^[ \t]*#\\+[[:alnum:]_]*" (line-beginning-position)) 'org-keyword)
               ((and (org-at-heading-p)
                     (looking-back ":[[:alnum:]_@#%:]*" (line-beginning-position)))
                'org-tag)
               ((org-in-src-block-p t) 'org-src)
               (t 'prose)))
        ((derived-mode-p 'text-mode) 'prose)
        ((nth 8 (syntax-ppss)) 'prose)          ; in a comment or string
        (t 'code)))

(defun +completion-capfs (&optional context)
  "Completion functions for CONTEXT (default: `+completion-context')."
  (pcase (or context (+completion-context))
    ('org-link (delq nil (list (and (fboundp 'org-roam-complete-link-at-point)
                                    #'org-roam-complete-link-at-point)
                               #'cape-file)))
    ((or 'org-keyword 'org-tag) (list #'pcomplete-completions-at-point))
    ('org-src (list #'cape-elisp-block #'cape-dabbrev))
    ('prose (+completion--prose))
    (_ (append (remq t completion-at-point-functions)
               (list #'cape-dabbrev #'cape-file)))))

;;;###autoload
(defun +completion/dwim ()
  "Complete at point with sources for where point is."
  (interactive)
  (require 'cape)
  (let ((completion-at-point-functions (+completion-capfs)))
    (completion-at-point)))

;; Doom's corfu module binds C-SPC to plain `completion-at-point' in
;; corfu-mode-map's insert state, which wins over a global binding.
(map! :i "C-SPC" #'+completion/dwim
      :after corfu :map corfu-mode-map :i "C-SPC" #'+completion/dwim)

(provide '+completion)
;;; +completion.el ends here
