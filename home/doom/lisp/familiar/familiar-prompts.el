;;; familiar-prompts.el --- A library of prompts: yours, and Fabric's patterns -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; Prompts worth keeping, used by name in M-ß:
;;
;;   @p:NAME         in the prompt: NAME's instructions, applied to what you
;;                   typed and the context (region, text around point)
;;   @p:A @p:B       composed like Fabric's pipes: B runs on A's output;
;;                   the last one answers in the conversation
;;   C-c C-p (prompt)  pick one, its purpose shown: inserts @p:NAME
;;                   (M-x familiar-prompts-insert elsewhere: its text)
;;
;; Where they come from:
;;
;;   `familiar-prompts-directory'   your own: NAME.md, NAME.org or NAME.txt;
;;                                  {{var}} is asked for when used, {{input}}
;;                                  is what you typed (else it goes after)
;;   Fabric's patterns              266 tested prompts (summarize,
;;                                  extract_wisdom, improve_writing, ...),
;;                                  MIT, github.com/danielmiessler/fabric;
;;                                  `familiar-prompts-update' downloads them
;;                                  (~1 MB, at `familiar-prompts-fabric-ref')
;;
;; Yours win over Fabric's of the same name.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'familiar-ask)

(defcustom familiar-prompts-directory
  (expand-file-name "familiar/prompts" (or (getenv "XDG_CONFIG_HOME") "~/.config"))
  "Your prompts: NAME.md, NAME.org or NAME.txt, {{var}} placeholders."
  :type 'directory :group 'familiar)

(defcustom familiar-prompts-fabric-directory
  (expand-file-name "familiar/fabric" (or (getenv "XDG_DATA_HOME") "~/.local/share"))
  "Where Fabric's patterns are kept (PATTERN/system.md)."
  :type 'directory :group 'familiar)

(defcustom familiar-prompts-fabric-ref "8e8511c770b2589a6066398a86343fbf8c2a56a3"
  "Fabric commit (or branch) `familiar-prompts-update' downloads."
  :type 'string :group 'familiar)

(defvar familiar-prompts--cache nil
  "(STAMP . PROMPTS): PROMPTS read when the directories had STAMP.")

;;;; The library

(defun familiar-prompts--purpose (text)
  "What the prompt TEXT does.
The first sentence of its identity part, else of its first line of prose
\(headings and // comments skipped)."
  (let* ((body (if (string-match "^#+ *IDENTITY[^\n]*\n+" text)
                   (substring text (match-end 0))
                 text))
         (line (seq-find (lambda (l) (not (string-match-p "\\`[ \t]*\\(?:#\\|//\\|$\\)" l)))
                         (split-string body "\n"))))
    (when line
      (let ((line (string-trim line)))
        (truncate-string-to-width
         (if (string-match "\\`.*?\\(?:[.!?]\\(?: \\|\\'\\)\\|。\\)" line) (string-trim (match-string 0 line)) line)
         100 nil nil "…")))))

(defun familiar-prompts--files ()
  "(NAME FILE SOURCE) for each prompt; yours first."
  (append
   (when (file-directory-p familiar-prompts-directory)
     (mapcar (lambda (f) (list (file-name-base f) f 'yours))
             (directory-files familiar-prompts-directory t "\\.\\(?:md\\|org\\|txt\\)\\'")))
   (when (file-directory-p familiar-prompts-fabric-directory)
     (delq nil
           (mapcar (lambda (d)
                     (let ((f (expand-file-name "system.md" d)))
                       (and (file-readable-p f) (list (file-name-nondirectory d) f 'fabric))))
                   (directory-files familiar-prompts-fabric-directory t "\\`[^.]"))))))

(defun familiar-prompts ()
  "The library: alist of (NAME :text TEXT :purpose STRING :source SOURCE).
Read again when a directory changed."
  (let ((stamp (mapcar (lambda (d) (and (file-directory-p d)
                                        (file-attribute-modification-time (file-attributes d))))
                       (list familiar-prompts-directory familiar-prompts-fabric-directory))))
    (unless (equal stamp (car familiar-prompts--cache))
      (setq familiar-prompts--cache
            (cons stamp
                  (let (seen out)
                    (pcase-dolist (`(,name ,file ,source) (familiar-prompts--files))
                      (unless (member name seen)
                        (push name seen)
                        (let ((text (with-temp-buffer
                                      (insert-file-contents file)
                                      (buffer-string))))
                          (push (list name :text text :purpose (familiar-prompts--purpose text)
                                      :source source)
                                out))))
                    (nreverse out)))))
    (cdr familiar-prompts--cache)))

(defun familiar-prompts--get (name)
  "The prompt named NAME, a plist, or a user error if there is none."
  (or (cdr (assoc name (familiar-prompts)))
      (user-error "No prompt named %s (M-x familiar-prompts-update fetches Fabric's)" name)))

;;;; Using them

(defun familiar-prompts--fill (text input)
  "TEXT with {{input}} as INPUT and each other {{var}} asked for.
Without {{input}}, INPUT goes after the text."
  (let ((vars (delete-dups
               (let (vs (start 0))
                 (while (string-match "{{\\([[:alnum:]_ -]+\\)}}" text start)
                   (push (match-string 1 text) vs)
                   (setq start (match-end 0)))
                 (nreverse vs))))
        (has-input nil))
    (dolist (var vars)
      (if (equal var "input")
          (setq has-input t)
        (setq text (string-replace (format "{{%s}}" var)
                                   (read-string (format "%s: " var))
                                   text))))
    (if has-input
        (string-replace "{{input}}" input text)
      (concat (string-trim-right text) "\n\n" input))))

(defun familiar-prompts--spec (prompt)
  "PROMPT without its @p:NAMEs, and the names in order: (TEXT . NAMES)."
  (let (names)
    (while (string-match "\\(?:^\\|[ \t]+\\)@p:\\([^ \t\n]+\\)" prompt)
      (push (match-string 1 prompt) names)
      (setq prompt (replace-match "" t t prompt)))
    (cons (string-trim prompt) (nreverse names))))

(defun familiar-prompts--wrap (heading text)
  "A turn: HEADING, then TEXT (a prompt filled in) as Markdown.
TEXT is quoted as Org quotes code (a line starting with * stays text)."
  (format "%s\n#+begin_src markdown\n%s\n#+end_src"
          heading (org-escape-code-in-string (string-trim text))))

(defun familiar-prompts--run-chain (names input origin finish)
  "Run prompts NAMES on INPUT, each on the one before's output.
Call FINISH with the last output.  ORIGIN is where it was asked from."
  (if (null names)
      (funcall finish input)
    (let ((p (familiar-prompts--get (car names))))
      (message "familiar: %s…" (car names))
      (familiar-request
       (familiar-prompts--fill (plist-get p :text) input)
       :task 'ask
       :callback
       (lambda (response _info)
         (when (stringp response)
           (familiar-prompts--run-chain (cdr names) response origin finish)))))))

(defun familiar-prompts--ask-a (fn prompt &rest args)
  "Around `familiar-ask' (FN): @p:NAMEs in PROMPT apply those prompts.
ARGS are the rest of FN's.  One: its instructions with what you typed
and the context.  Several: all but the last run first, each on the one
before's output (input: what you typed and the context); the last
answers in the conversation."
  (pcase-let ((`(,text . ,names) (familiar-prompts--spec prompt)))
    (if (null names)
        (apply fn prompt args)
      (let* ((origin (or (nth 1 args) (familiar-ask--capture)))
             (last (car (last names)))
             (send (lambda (input)
                     (apply fn
                            (familiar-prompts--wrap
                             ;; What you typed → the prompts it went through.
                             (string-join (delete "" (cons (car (split-string text "\n")) names))
                                          " → ")
                             (familiar-prompts--fill
                              (plist-get (familiar-prompts--get last) :text) input))
                            (car args) origin (nthcdr 2 args)))))
        (if (cdr names)
            (familiar-prompts--run-chain
             (butlast names)
             (concat text "\n\n" (familiar-ask--context origin))
             origin send)
          (funcall send text))))))

(advice-add 'familiar-ask :around #'familiar-prompts--ask-a)

;;;; Completion and picking

(defun familiar-prompts--annotate (name)
  "The completion annotation of prompt NAME: ★ if yours, and its purpose."
  (when-let* ((p (cdr (assoc name (familiar-prompts)))))
    (format "  %s%s" (if (eq (plist-get p :source) 'yours) "★ " "")
            (or (plist-get p :purpose) ""))))

(defun familiar-prompts-capf ()
  "Complete the NAME of @p:NAME in the prompt."
  (when (looking-back "@p:\\([^ \t\n]*\\)" (line-beginning-position))
    (list (match-beginning 1) (point) (mapcar #'car (familiar-prompts))
          :annotation-function #'familiar-prompts--annotate
          :exclusive 'no)))

;; C-c C-p: C-c and a plain letter are yours (the Doom glue binds C-c p).
(define-key familiar-ask-minibuffer-map (kbd "C-c C-p") #'familiar-prompts-insert)

(add-hook 'familiar-ask-prompt-setup-hook
          (defun familiar-prompts-setup-h ()
            (add-hook 'completion-at-point-functions #'familiar-prompts-capf nil t)))

;;;###autoload
(defun familiar-prompts-insert (name)
  "Insert @p:NAME (in the M-ß prompt) or prompt NAME's text (elsewhere)."
  (interactive
   (list (completing-read
          "Prompt: "
          (lambda (str pred action)
            (if (eq action 'metadata)
                '(metadata (annotation-function . familiar-prompts--annotate))
              (complete-with-action action (mapcar #'car (familiar-prompts)) str pred)))
          nil t)))
  (if (minibufferp)
      (insert (if (or (bolp) (eq (char-before) ?\s)) "" " ") "@p:" name " ")
    (insert (plist-get (familiar-prompts--get name) :text))))

;;;; Fabric's patterns

;;;###autoload
(defun familiar-prompts-update ()
  "Download Fabric's patterns at `familiar-prompts-fabric-ref' (~1 MB).
One file each, into `familiar-prompts-fabric-directory'."
  (interactive)
  (let* ((ref familiar-prompts-fabric-ref)
         (tree (with-current-buffer
                   (url-retrieve-synchronously
                    (format "https://api.github.com/repos/danielmiessler/fabric/git/trees/%s?recursive=1" ref)
                    t)
                 (goto-char (point-min))
                 (re-search-forward "\n\n")
                 (prog1 (json-parse-buffer :object-type 'plist :array-type 'list)
                   (kill-buffer))))
         (paths (seq-keep (lambda (e)
                            (let ((p (plist-get e :path)))
                              (and (string-match "\\`data/patterns/\\([^/]+\\)/system\\.md\\'" p)
                                   (match-string 1 p))))
                          (plist-get tree :tree)))
         (config (make-temp-file "familiar-fabric" nil ".curl")))
    (unless paths (user-error "No patterns found at %s" ref))
    (with-temp-file config
      (dolist (name paths)
        (insert (format "url = \"https://raw.githubusercontent.com/danielmiessler/fabric/%s/data/patterns/%s/system.md\"\noutput = \"%s\"\n"
                        ref name
                        (expand-file-name (concat name "/system.md") familiar-prompts-fabric-directory)))))
    (message "familiar: downloading %d Fabric patterns…" (length paths))
    (make-process
     :name "familiar-fabric" :buffer " *familiar-fabric*"
     :command (list "curl" "--fail" "--silent" "--show-error" "--parallel" "--create-dirs"
                    "--config" config)
     :sentinel (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (delete-file config)
                   (setq familiar-prompts--cache nil)
                   (if (zerop (process-exit-status proc))
                       (message "familiar: %d Fabric patterns in %s" (length paths)
                                (abbreviate-file-name familiar-prompts-fabric-directory))
                     (message "familiar: Fabric download failed, see buffer  *familiar-fabric*")))))))

(provide 'familiar-prompts)
;;; familiar-prompts.el ends here
