;;; lisp/+asked.el --- Made from what you asked the assistant -*- lexical-binding: t; -*-
;;
;; familiar's history (SPC A j) had 54 questions by 2026-11-06; some came
;; back again and again.  The answers, made into commands (and all of
;; them, with the Org how-tos, in C-ß's search):
;;
;;   +org/ai-tidy                 "format, structure, beautify this" (6×): the
;;                                region or buffer, tidied by the assistant as
;;                                a proposal to accept or reject (smerge)
;;   +org/remove-tag-everywhere   "remove all :incomplete: tags"
;;   +org-vault/save-into-vault   "save this buffer in my org notes"
;;   +discover/key-notation       "the syntax for the shift key?"
;;   the M-ß prompt says what C-c ' and C-r do ("how do I raise this prompt
;;   to its own buffer", 3×)
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function familiar-fix "familiar" (instruction &optional escalate))
(declare-function org-get-buffer-tags "org" ())
(declare-function org-map-entries "org" (func &optional match scope &rest skip))
(declare-function org-get-tags "org" (&optional epom local))
(declare-function org-toggle-tag "org" (tag &optional onoff))

;;;; Tidy with the assistant

(defvar +org-ai-tidy-instruction
  "Tidy this text: clear structure (headings, short paragraphs, lists where \
there are lists), consistent markup, nothing lost: keep every fact, link, \
date, name and code exactly.  Add nothing, invent nothing.  Same language."
  "What `+org/ai-tidy' asks for.")

;;;###autoload
(defun +org/ai-tidy (&optional instruction)
  "Tidy the region (or the whole buffer) with the assistant.
The result comes as a proposal in the text (smerge): accept or reject it
hunk by hunk.  With \\[universal-argument], say what to do instead."
  (interactive (list (and current-prefix-arg (read-string "Tidy how: " +org-ai-tidy-instruction))))
  (unless (use-region-p)
    (push-mark (point-min) t t)
    (goto-char (point-max)))
  (familiar-fix (or instruction +org-ai-tidy-instruction)))

;;;; A tag, out of every heading

;;;###autoload
(defun +org/remove-tag-everywhere (tag)
  "Remove TAG from every heading of this buffer (not from #+filetags)."
  (interactive
   (progn (require 'org)
          (list (completing-read "Remove tag everywhere: "
                                 (mapcar #'car (org-get-buffer-tags)) nil t))))
  (let ((n 0))
    (org-map-entries
     (lambda ()
       (when (member tag (org-get-tags nil t))
         (org-toggle-tag tag 'off)
         (cl-incf n))))
    (message "Removed :%s: from %d heading%s" tag n (if (= n 1) "" "s"))
    n))

;;;; Save this buffer into the vault

(defvar org-directory)

;;;###autoload
(defun +org-vault/save-into-vault (file)
  "Save this buffer as FILE in the vault (`org-directory'); it then visits it."
  (interactive
   (let* ((base (string-trim (replace-regexp-in-string "[*<>0-9]+" "" (buffer-name)) "[ -]+" "[ -]+"))
          (default (concat (if (string-empty-p base) "note" base)
                           (if (string-suffix-p ".org" base) "" ".org"))))
     (list (read-file-name "Save into the vault as: " (file-name-as-directory org-directory)
                           nil nil default))))
  (write-file file t)
  (when (and (string-suffix-p ".org" file) (not (derived-mode-p 'org-mode)))
    (org-mode))
  (message "Saved as %s" (abbreviate-file-name file)))

;;;; Key notation

;;;###autoload
(defun +discover/key-notation ()
  "How Emacs writes keys: C- M- S- s- …, and Doom's SPC and SPC m."
  (interactive)
  (with-current-buffer (get-buffer-create "*Key notation*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "How Emacs writes keys\n\n"
              "  C-x      Control+x\n"
              "  M-x      Meta+x: Alt+x (or Esc, then x)\n"
              "  S-x      Shift+x, written that way with other modifiers or special keys:\n"
              "           S-<return>, C-S-t.  A plain shifted letter is just X.\n"
              "  s-x      Super+x (the Windows / logo key); H-x Hyper; A-x Alt as its own key\n"
              "  C-M-x    Control+Meta+x: several modifiers at once\n"
              "  C-x C-f  first C-x, then C-f (a key sequence)\n\n"
              "  RET  Return      TAB  Tab       SPC  Space    DEL  Backspace\n"
              "  ESC  Escape      <f1> F1        <up> <down> <left> <right>\n"
              "  <return>, <tab>: the keys themselves (RET, TAB: what they send)\n\n"
              "In Lisp: (kbd \"C-c C-k\") or (keymap-set map \"C-c C-k\" …)\n\n"
              "Doom and Evil\n\n"
              "  SPC      the leader in normal state (M-SPC elsewhere)\n"
              "  SPC m    the localleader: this mode's own keys\n"
              "  SPC u    the prefix argument, C-u\n"
              "  g z [ ]  Evil prefixes: press one and wait, or C-ß p to search what is under it\n")
      (goto-char (point-min))
      (special-mode))
    (pop-to-buffer (current-buffer))))

;;;; The M-ß prompt says what it can do

(defvar-local +asked--prompt-hint nil)

(defun +asked--prompt-hint-h ()
  "In an empty M-ß prompt: the keys you asked about, dimmed after it."
  (setq +asked--prompt-hint (make-overlay (point-max) (point-max) nil t t))
  (add-hook 'post-command-hook #'+asked--prompt-hint-update nil t)
  (+asked--prompt-hint-update))

(defun +asked--prompt-hint-update ()
  (when (overlayp +asked--prompt-hint)
    (move-overlay +asked--prompt-hint (point-max) (point-max))
    (overlay-put +asked--prompt-hint 'after-string
                 ;; Empty, or only the @modifiers kept from the last prompt.
                 (and (string-match-p "\\`\\(?:[ \t]*@[^ \t\n]+\\)*[ \t]*\\'"
                                      (minibuffer-contents-no-properties))
                      (propertize (substitute-command-keys
                                   "  \\<familiar-ask-minibuffer-map>\\[familiar-ask-edit-prompt] write it in a buffer · \\[familiar-ask-pick-history] earlier prompts · @ keywords")
                                  'face 'shadow)))))

(with-eval-after-load 'familiar-ask
  (add-hook 'familiar-ask-prompt-setup-hook #'+asked--prompt-hint-h))

(provide '+asked)
;;; +asked.el ends here
