;;; familiar.el --- An AI familiar woven into your editing -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (gptel "0.9.9") (transient "0.7.0"))
;; Keywords: tools, convenience, vc
;; SPDX-License-Identifier: GPL-3.0-or-later
;; URL: https://github.com/cypl0x/familiar.el
;;
;;; Commentary:
;;
;; A familiar is the spirit that sits on your shoulder.  This one speaks LLM,
;; through gptel, but lives in the places you already work instead of in a
;; chat window:
;;
;;   `familiar-commit-message'      write the commit message for the staged diff,
;;                                  in the style of the repository's own history
;;   `familiar-explain'             explain region / defun / symbol, streamed
;;   `familiar-explain-diagnostic'  explain the flymake/flycheck error at point
;;   `familiar-fix'                 propose a fix as smerge conflict markers:
;;                                  keep, reject or edit with stock smerge keys
;;
;; Every request is priced from gptel's model table and the token counts the
;; API returns, appended to `familiar-ledger-file', and checked against
;; `familiar-budget'.  `familiar-mode-line-mode' shows the spend; `familiar-spend'
;; itemizes it.
;;
;; Cheap work goes to a cheap model: each task has a tier (see
;; `familiar-task-tiers'), and a prefix argument escalates one tier.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gptel)
(declare-function familiar-history-record "familiar-history" (&rest args))
(declare-function familiar-history-prompt-text "familiar-history" (prompt))

(declare-function flymake-diagnostics "flymake")
(declare-function flymake-diagnostic-text "flymake")
(declare-function flymake-diagnostic-beg "flymake")
(declare-function flycheck-overlay-errors-at "ext:flycheck")
(declare-function flycheck-error-message "ext:flycheck")
(declare-function flycheck-error-line "ext:flycheck")
(declare-function smerge-mode "smerge-mode")
(declare-function gfm-view-mode "ext:markdown-mode")
(declare-function project-root "project")
(declare-function compile-goto-error "compile")
(declare-function compilation-next-error "compile")
(defvar flycheck-mode)
(defvar smerge-mode)


;;;; Customization

(defgroup familiar nil
  "An AI familiar woven into Emacs."
  :group 'tools
  :prefix "familiar-")

(defcustom familiar-models
  '((fast . claude-haiku-5-5)
    (smart . claude-sonnet-5-5)
    (deep . claude-opus-5-5))
  "Model for each tier, cheapest first.  A prefix argument escalates one tier."
  :type '(alist :key-type symbol :value-type symbol))

(defcustom familiar-task-tiers
  '((commit . fast) (explain . fast) (diagnostic . fast) (name . fast) (fix . smart) (review . smart))
  "Default tier for each task."
  :type '(alist :key-type symbol :value-type symbol))

(defcustom familiar-backend nil
  "The gptel backend to use, or nil for the current `gptel-backend'."
  :type '(choice (const :tag "gptel-backend" nil) (sexp :tag "Backend")))

(defcustom familiar-budget 10.0
  "Spending budget in USD; nil for none."
  :type '(choice (const nil) number))

(defcustom familiar-budget-alerts '(0.5 0.8 0.95)
  "Fractions of `familiar-budget' at which to alert once."
  :type '(repeat number))

(defcustom familiar-ledger-file (locate-user-emacs-file "familiar-ledger.eld")
  "File recording every request: one Lisp list per line."
  :type 'file)

(defcustom familiar-context-lines 40
  "Lines of surrounding code to send when nothing narrower is selected."
  :type 'integer)

(defcustom familiar-commit-style-samples 20
  "Recent commit subjects shown to the model as the house style."
  :type 'integer)

(defcustom familiar-notify-function #'familiar-notify-desktop
  "Function called with TITLE and BODY for alerts (budget, failures)."
  :type 'function)


;;;; Pricing and the ledger

(defcustom familiar-model-prices
  '((claude-haiku-5-5 0.10 0.50)
    (claude-sonnet-5-5 2.0 10.0)
    (claude-opus-5-5 4.0 20.0)
    (claude-fable-5-1 10.0 50.0))
  "Fallback (MODEL INPUT OUTPUT) prices in USD per million tokens.
Used when gptel's model table has no price for MODEL, e.g. with a gptel
older than the model.  From platform.claude.com, 2026-10."
  :type '(repeat (list symbol number number)))

(defvar familiar--unpriced-warned nil "Models already warned about.")

(defun familiar--prices (model)
  "(INPUT . OUTPUT) USD per million tokens for MODEL, or nil if unknown."
  (let ((in (get model :input-cost)) (out (get model :output-cost)))
    (if (and in out) (cons in out)
      (when-let* ((p (alist-get model familiar-model-prices)))
        (cons (nth 0 p) (nth 1 p))))))

(defun familiar-cost (model tokens)
  "USD cost of TOKENS (gptel's :tokens plist) on MODEL.
Prices come from gptel's model table, else `familiar-model-prices'.  Cache
reads are billed at a tenth of the input price (an upper bound: some models
charge less).  An unknown price counts as 0, with a one-time warning."
  (let ((prices (familiar--prices model)))
    (unless (or prices (memq model familiar--unpriced-warned))
      (push model familiar--unpriced-warned)
      (display-warning 'familiar
                       (format "No price known for %s; its spend counts as $0. \
Add it to `familiar-model-prices'." model)))
    (let ((in (or (car prices) 0)) (out (or (cdr prices) 0)))
      (/ (+ (* in (or (plist-get tokens :input) 0))
            (* in 0.1 (or (plist-get tokens :cached) 0))
            (* out (or (plist-get tokens :output) 0)))
         1e6))))

(defun familiar--ledger ()
  "All ledger entries: (TIME MODEL TASK INPUT OUTPUT CACHED COST . REST).
REST, in newer entries: SECONDS PROJECT STATUS (see `familiar--record')."
  (when (file-readable-p familiar-ledger-file)
    (with-temp-buffer
      (insert-file-contents familiar-ledger-file)
      (let (entries)
        (condition-case nil
            (while t (push (read (current-buffer)) entries))
          (end-of-file nil))
        (nreverse entries)))))

(defvar familiar--spent nil "Cached total spend, or nil to recompute.")

(defun familiar-spent ()
  "Total USD spent according to the ledger."
  (or familiar--spent
      (setq familiar--spent
            (apply #'+ 0 (mapcar (lambda (e) (nth 6 e)) (familiar--ledger))))))

(defun familiar--record (model task tokens &optional seconds project status)
  "Append a ledger entry for TASK on MODEL with TOKENS; return its cost.
SECONDS the request took, PROJECT it was made in, STATUS (nil: answered,
`error': failed) go at the entry's end, for familiar-analytics."
  (let* ((cost (familiar-cost model tokens))
         (before (familiar-spent))
         (entry (list (format-time-string "%FT%T%z") model task
                      (or (plist-get tokens :input) 0)
                      (or (plist-get tokens :output) 0)
                      (or (plist-get tokens :cached) 0)
                      cost
                      (and seconds (/ (round (* seconds 100)) 100.0)) project status)))
    (make-directory (file-name-directory familiar-ledger-file) t)
    (let ((print-length nil) (print-level nil))
      (write-region (concat (prin1-to-string entry) "\n") nil
                    familiar-ledger-file 'append 'silent))
    (setq familiar--spent (+ before cost))
    (familiar--check-budget before familiar--spent)
    (force-mode-line-update t)
    cost))

(defun familiar--check-budget (before after)
  "Alert for each budget fraction crossed going from BEFORE to AFTER."
  (when familiar-budget
    (dolist (f familiar-budget-alerts)
      (let ((mark (* f familiar-budget)))
        (when (and (< before mark) (>= after mark))
          (funcall familiar-notify-function
                   (format "familiar: %d%% of budget used" (round (* 100 f)))
                   (format "$%.4f of $%.2f spent" after familiar-budget)))))))

(defun familiar-notify-desktop (title body)
  "Show TITLE and BODY as a desktop notification, falling back to `message'."
  (message "%s — %s" title body)
  (when (executable-find "notify-send")
    (call-process "notify-send" nil 0 nil "-a" "Emacs · familiar" title body)))


;;;; Mode line

(defvar familiar--mode-line-map (make-mode-line-mouse-map 'mouse-1 #'familiar-spend)
  "Built once: the segment is evaluated on every redisplay.")

(defun familiar--mode-line ()
  "The mode line segment: spend so far, colored against `familiar-budget'."
  (when familiar-budget
    (let ((spent (familiar-spent)))
      (propertize (format (if (< spent 1) " ✦$%.3f" " ✦$%.2f") spent)
                  'face (cond ((>= spent (* 0.8 familiar-budget)) 'error)
                              ((>= spent (* 0.5 familiar-budget)) 'warning)
                              (t 'shadow))
                  'help-echo (format "familiar: $%.4f of $%.2f spent — mouse-1: details"
                                     spent familiar-budget)
                  'local-map familiar--mode-line-map))))

(defconst familiar--mode-line-construct '(:eval (familiar--mode-line)))

;;;###autoload
(define-minor-mode familiar-mode-line-mode
  "Show familiar's spend in the mode line."
  :global t
  (if familiar-mode-line-mode
      (add-to-list 'global-mode-string familiar--mode-line-construct t)
    (setq global-mode-string
          (delete familiar--mode-line-construct global-mode-string))))

;;;###autoload
(defun familiar-spend ()
  "Show every request familiar made, newest first, with totals."
  (interactive)
  (let ((entries (reverse (familiar--ledger))))
    (with-current-buffer (get-buffer-create "*familiar spend*")
      (tabulated-list-mode)
      (setq tabulated-list-format
            [("When" 20 t) ("Task" 11 t) ("Model" 20 t)
             ("In" 8 t :right-align t) ("Out" 7 t :right-align t)
             ("Cached" 7 t :right-align t) ("USD" 9 t :right-align t)])
      (setq tabulated-list-entries
            (cl-loop for e in entries for i from 0
                     collect (list i (vector (substring (nth 0 e) 0 19)
                                             (format "%s" (nth 2 e))
                                             (format "%s" (nth 1 e))
                                             (number-to-string (nth 3 e))
                                             (number-to-string (nth 4 e))
                                             (number-to-string (nth 5 e))
                                             (format "%.5f" (nth 6 e))))))
      (setq header-line-format
            (format " %d requests · $%.4f spent%s"
                    (length entries) (familiar-spent)
                    (if familiar-budget
                        (format " of $%.2f (%.1f%%)" familiar-budget
                                (* 100 (/ (familiar-spent) familiar-budget)))
                      "")))
      (tabulated-list-init-header)
      (tabulated-list-print)
      (pop-to-buffer (current-buffer)))))


;;;; Requests

(defun familiar--model (task &optional escalate)
  "Model for TASK, one tier up when ESCALATE."
  (let* ((tiers (mapcar #'car familiar-models))
         (tier (or (alist-get task familiar-task-tiers) 'fast))
         (pos (or (cl-position tier tiers) 0)))
    (when escalate (setq pos (min (1+ pos) (1- (length tiers)))))
    (alist-get (nth pos tiers) familiar-models)))
(defvar familiar-footprint--actor nil
  "What of familiar's changes buffers right now (a tool name, \"@inline\"), or nil.
Changes made meanwhile go in familiar-footprint.el's ledger.")


(cl-defun familiar-request (prompt &key task system escalate stream callback tools model backend silent)
  "Send PROMPT for TASK with SYSTEM prompt; call CALLBACK like `gptel-request'.
The model comes from TASK's tier (one higher when ESCALATE), unless MODEL
\(on BACKEND) is given.  STREAM gets the answer in pieces as it arrives.
The request is priced and recorded once it completes.  TOOLS (gptel
tools) are offered; when the model calls them, the streamed segment ends
\(with t) with the calls in INFO's :tool-use and :stop-reason
\"tool_use\", before gptel runs them and continues.  SILENT: a
background request, priced but not kept in the history, failing quietly.
Returns the model used."
  (let* ((model (or model (familiar--model task escalate)))
         ;; The request runs curl here; a directory deleted since (a test
         ;; project, a removed checkout) made every request fail.
         (default-directory (if (file-directory-p default-directory) default-directory
                              (expand-file-name "~/")))
         (gptel-backend (or backend familiar-backend gptel-backend))
         (gptel-model model)
         (gptel-tools tools)
         (gptel-use-tools (and tools t))
         (gptel-use-context nil)
         (started (float-time))
         (project (familiar--ledger-project)))
    (gptel-request prompt
      :system system
      :stream stream
      :callback
      (let ((answer ""))
        (lambda (response info)
          (when (stringp response) (setq answer (concat answer response)))
          (when (or (eq response t) (and (stringp response) (not stream)))
            (let* ((tokens (plist-get info :tokens))
                   (cost (and tokens (familiar--record model task tokens (- (float-time) started) project))))
              ;; One Org history of every turn (familiar-history.el).
              (when (and (not silent) (fboundp 'familiar-history-record))
                (familiar-history-record
                 :prompt (familiar-history-prompt-text prompt) :answer answer
                 :task task :model model :tokens tokens :cost cost
                 :calls (mapcar (lambda (call)
                                  (format "%s %S" (plist-get call :name) (plist-get call :args)))
                                (plist-get info :tool-use))))
              (setq answer "")))
          (when (null response)
            (familiar--record model task nil (- (float-time) started) project 'error))
          (when (and (null response) (not silent))
            (funcall familiar-notify-function "familiar: request failed"
                     (or (plist-get info :status) "no response")))
          (funcall callback response info))))
    model))


;;;; Context

(defun familiar--ledger-project ()
  "The project of `default-directory' for the ledger: its git root's name.
Not looked up on remote or handled directories (TRAMP, /github), where a
lookup would cost a round trip per request."
  (unless (or (file-remote-p default-directory)
              (find-file-name-handler default-directory 'file-exists-p))
    (when-let* ((root (locate-dominating-file default-directory ".git")))
      (file-name-nondirectory (directory-file-name root)))))

(defun familiar--project-name ()
  "The current project's directory name, or nil outside a project."
  (when-let* ((pr (project-current)))
    (file-name-nondirectory (directory-file-name (project-root pr)))))

(defun familiar--target-bounds ()
  "Region, else the defun at point, else `familiar-context-lines' around point."
  (cond ((use-region-p) (cons (region-beginning) (region-end)))
        ((bounds-of-thing-at-point 'defun))
        (t (save-excursion
             (let ((half (/ familiar-context-lines 2)))
               (cons (progn (forward-line (- half)) (line-beginning-position))
                     (progn (forward-line familiar-context-lines)
                            (line-end-position))))))))

(defun familiar--describe-location (beg)
  "Describe BEG for a prompt: file or buffer, mode, line, Emacs, project."
  (format "%s (%s, line %d%s%s)"
          (if buffer-file-name (file-name-nondirectory buffer-file-name) (buffer-name))
          (string-remove-suffix "-mode" (symbol-name major-mode))
          (line-number-at-pos beg)
          ;; Emacs Lisp runs in this Emacs, and models judge it by older
          ;; ones (one called `evenp' "not in the standard library"; it is in
          ;; subr since Emacs 31).
          (if (derived-mode-p 'emacs-lisp-mode)
              (format ", Emacs %s" emacs-version)
            "")
          (if-let* ((p (familiar--project-name))) (format ", project %s" p) "")))

(defun familiar--fenced (text)
  "TEXT in a Markdown code fence named after the major mode."
  (format "```%s\n%s\n```" (string-remove-suffix "-mode" (symbol-name major-mode)) text))

(defun familiar--unfence (text)
  "Strip a single surrounding Markdown code fence from TEXT, if any."
  (let ((s (string-trim text)))
    (if (string-match "\\````[^\n]*\n\\(\\(?:.\\|\n\\)*?\\)\n?```\\'" s)
        (match-string 1 s)
      s)))

(defun familiar--diagnostics-at-point ()
  "Messages of the flymake or flycheck diagnostics at point."
  (or (and (bound-and-true-p flycheck-mode)
           (mapcar #'flycheck-error-message (flycheck-overlay-errors-at (point))))
      (and (bound-and-true-p flymake-mode)
           (mapcar #'flymake-diagnostic-text (flymake-diagnostics (point))))))


;;;; Output buffer

(defun familiar--output-buffer (title)
  "Fresh read-only buffer for a streamed answer about TITLE."
  (let ((buf (get-buffer-create "*familiar*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (fboundp 'gfm-view-mode) (gfm-view-mode) (special-mode))
        (when (bound-and-true-p display-line-numbers-mode)
          (display-line-numbers-mode -1))
        (setq header-line-format (format " ✦ %s" title))))
    (display-buffer buf)
    buf))

(defun familiar--stream-into (buf)
  "Callback streaming a response into BUF."
  (lambda (response info)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (cond ((stringp response)
                 ;; Windows whose point is at the end follow the answer; move
                 ;; point up to read and that window stays put.
                 (let* ((end (point-max))
                        (following (seq-filter (lambda (w) (= (window-point w) end))
                                               (get-buffer-window-list buf nil t))))
                   (save-excursion (goto-char end) (insert response))
                   (dolist (w following) (set-window-point w (point-max)))))
                ((eq response t)
                 (setq header-line-format
                       (concat header-line-format
                               (when-let* ((tk (plist-get info :tokens)))
                                 (format "  ·  %s in / %s out"
                                         (plist-get tk :input) (plist-get tk :output)))))
                 (force-mode-line-update))
                ((null response)
                 (save-excursion
                   (goto-char (point-max))
                   (insert (format "\n\n[request failed: %s]" (plist-get info :status)))))))))))


;;;; Explain

(defconst familiar--explain-system
  "You are an expert pair programmer embedded in the user's editor. Explain \
concisely and concretely: what the code does, why, and anything surprising or \
wrong. You see only the code shown, not the rest of the file: never describe \
or warn about lines you were not given. Use Markdown. No preamble.")

;;;###autoload
(defun familiar-explain (&optional escalate)
  "Explain the region, the defun at point, or the code around point.
With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
               (where (familiar--describe-location beg))
               (code (familiar--fenced (buffer-substring-no-properties beg end)))
               ;; Last: displaying the output can change the current buffer.
               (buf (familiar--output-buffer (concat "Explain " where))))
    (deactivate-mark)
    (familiar-request (format "Explain this code from %s:\n\n%s" where code)
                      :task 'explain :escalate escalate :stream t
                      :system familiar--explain-system
                      :callback (familiar--stream-into buf))))

;;;###autoload
(defun familiar-explain-diagnostic (&optional escalate)
  "Explain the flymake/flycheck diagnostic at point, in context.
With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (let ((diags (or (familiar--diagnostics-at-point)
                   (user-error "No diagnostic at point"))))
    (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
                 (where (familiar--describe-location (point)))
                 (line (line-number-at-pos))
                 (code (familiar--fenced (buffer-substring-no-properties beg end)))
                 ;; Last: displaying the output can change the current buffer.
                 (buf (familiar--output-buffer (concat "Diagnostic in " where))))
      (familiar-request
       (format "In %s the checker reports:\n%s\n\nThe code (point is on line %d):\n\n%s\n\n\
Explain the cause and how to fix it."
               where (mapconcat (lambda (d) (concat "- " d)) diags "\n")
               line code)
       :task 'diagnostic :escalate escalate :stream t
       :system familiar--explain-system
       :callback (familiar--stream-into buf)))))


;;;###autoload
(defun familiar-explain-compilation-error (&optional escalate)
  "Explain the compilation error at point, with the code at its locus.
Works in `compilation-mode' buffers and `compilation-minor-mode' (e.g. the
*run: …* buffers).  With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (let* ((message-text
          (buffer-substring-no-properties
           (line-beginning-position)
           (save-excursion
             (let ((start (point)))
               (condition-case nil (compilation-next-error 1)
                 (error (goto-char (point-max))))
               (when (<= (point) start) (goto-char (point-max)))
               (forward-line -1)
               (min (line-end-position)
                    (save-excursion (goto-char start) (forward-line 30) (point)))))))
         (locus (save-window-excursion
                  (save-excursion
                    (condition-case nil (compile-goto-error)
                      (error (user-error "No compilation error at point")))
                    (let ((half (/ familiar-context-lines 2)))
                      (list (familiar--describe-location (point))
                            (line-number-at-pos)
                            (familiar--fenced
                             (buffer-substring-no-properties
                              (save-excursion (forward-line (- half)) (point))
                              (save-excursion (forward-line half) (line-end-position)))))))))
         (buf (familiar--output-buffer (concat "Compilation error in " (car locus)))))
    (familiar-request
     (format "The build reports:\n```\n%s\n```\n\nThe code at %s (error on line %d):\n\n%s\n\n\
Explain the cause and the fix."
             (string-trim message-text) (nth 0 locus) (nth 1 locus) (nth 2 locus))
     :task 'diagnostic :escalate escalate :stream t
     :system familiar--explain-system
     :callback (familiar--stream-into buf))))


;;;; Review

(defconst familiar--review-system
  "You review a diff as a senior engineer. Report only real problems: bugs, \
edge cases, races, security, misleading names, missing tests. One bullet each, \
most severe first, with file and line. If it is fine, say so in one line.")

(defcustom familiar-review-max-chars 60000
  "Diffs longer than this are truncated before review, to bound cost."
  :type 'integer)

;;;###autoload
(defun familiar-review (&optional escalate)
  "Review the staged changes (or, with nothing staged, the unstaged ones).
With prefix arg ESCALATE, use the next model tier."
  (interactive "P")
  (let* ((staged (familiar--git "diff" "--cached" "--no-color" "--no-ext-diff"))
         (which (if (string-empty-p (string-trim (or staged ""))) "unstaged" "staged"))
         (diff (if (equal which "staged") staged
                 (familiar--git "diff" "--no-color" "--no-ext-diff"))))
    (when (string-empty-p (string-trim (or diff "")))
      (user-error "No changes to review"))
    (when (> (length diff) familiar-review-max-chars)
      (setq diff (concat (substring diff 0 familiar-review-max-chars)
                         "\n[… truncated by familiar-review-max-chars]")))
    (familiar-request
     (format "Review these %s changes%s:\n\n```diff\n%s\n```" which
             (if-let* ((p (familiar--project-name))) (format " in %s" p) "")
             diff)
     :task 'review :escalate escalate :stream t
     :system familiar--review-system
     :callback (familiar--stream-into
                (familiar--output-buffer (format "Review of %s changes" which))))))


;;;; Fix: proposals as smerge conflicts

(defconst familiar--fix-system
  "You rewrite code. Reply with ONLY the complete replacement for the given \
code, no explanation, no Markdown fences. Keep everything that needs no change \
exactly as it is, including indentation and comments.")

(defun familiar--propose (buf beg end replacement)
  "Show REPLACEMENT for BEG..END of BUF as an smerge conflict and enable smerge."
  (with-current-buffer buf
    (let ((original (buffer-substring-no-properties beg end)))
      (if (string= (string-trim original) (string-trim replacement))
          (message "familiar: no change proposed")
        (undo-boundary)
        (save-excursion
          (goto-char beg)
          (delete-region beg end)
          (insert "<<<<<<< current\n" original
                  (if (string-suffix-p "\n" original) "" "\n")
                  "=======\n" replacement
                  (if (string-suffix-p "\n" replacement) "" "\n")
                  ">>>>>>> familiar\n"))
        (undo-boundary)
        (smerge-mode 1)
        (goto-char beg)
        (message "familiar: proposal inserted; keep it with %s, reject with %s"
                 (substitute-command-keys "\\[smerge-keep-lower]")
                 (substitute-command-keys "\\[smerge-keep-upper]"))))))

;;;###autoload
(defun familiar-fix (instruction &optional escalate)
  "Ask for a fix of the region or defun at point, following INSTRUCTION.
The proposal appears inline as smerge conflict markers.  Defaults to fixing
the diagnostics at point.  With prefix arg ESCALATE, use the next model tier."
  (interactive
   (let ((diags (familiar--diagnostics-at-point)))
     (list (read-string "Fix: " (when diags (concat "Fix: " (string-join diags "; "))))
           current-prefix-arg)))
  (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
               (buf (current-buffer))
               (beg (copy-marker beg))
               (end (copy-marker end t))
               (where (familiar--describe-location beg)))
    (deactivate-mark)
    (message "familiar: thinking about %s…" where)
    (familiar-request
     (format "%s\n\nCode from %s:\n\n%s" instruction where
             (familiar--fenced (buffer-substring-no-properties beg end)))
     :task 'fix :escalate escalate :system familiar--fix-system
     :callback (lambda (response _info)
                 (when (stringp response)
                   (familiar--propose buf beg end (familiar--unfence response)))))))


;;;; Hand-off to agents

(declare-function agent-shell-buffers "ext:agent-shell" ())
(declare-function agent-shell-insert "ext:agent-shell" (&rest args))
(declare-function claude-code-buffer-name "ext:claude-code-core" ())
(declare-function claude-code-send-string "ext:claude-code-core" (string &optional paste-p))

(defcustom familiar-handoff-targets
  '((agent-shell
     :available (lambda () (and (fboundp 'agent-shell-buffers) (car (agent-shell-buffers))))
     :send (lambda (text)
             (agent-shell-insert :text text :submit t
                                 :shell-buffer (car (agent-shell-buffers)))))
    (claude-code
     :available (lambda () (and (fboundp 'claude-code-buffer-name)
                                ;; Signals "not part of a project" outside one.
                                (when-let* ((name (ignore-errors (claude-code-buffer-name))))
                                  (get-buffer name))))
     :send (lambda (text) (claude-code-send-string text t)))
    (clipboard
     :available always
     :send (lambda (text)
             (kill-new text)
             (message "familiar: hand-off copied; paste it into your agent"))))
  "Where `familiar-handoff' sends context, first available first.
Each entry is (NAME :available PREDICATE :send FUNCTION-OF-TEXT)."
  :type '(repeat (cons symbol plist)))

(defun familiar--relative (file)
  "FILE relative to the current project's root, else abbreviated."
  (if-let* ((pr (project-current)) (root (project-root pr)))
      (file-relative-name file root)
    (abbreviate-file-name file)))

(defun familiar-handoff-context ()
  "Markdown describing what is at point, for an agent that can open files.
The region, else the diagnostics at point, else the compilation error at
point, else the defun or surrounding lines."
  (cond
   ((derived-mode-p 'compilation-mode)
    (let ((msg (buffer-substring-no-properties (line-beginning-position)
                                               (min (point-max)
                                                    (save-excursion (forward-line 8) (point))))))
      (format "The build in `%s` reports:\n```\n%s\n```"
              (abbreviate-file-name default-directory) (string-trim msg))))
   (t
    (pcase-let* ((`(,beg . ,end) (familiar--target-bounds))
                 (file (and buffer-file-name (familiar--relative buffer-file-name)))
                 (diags (familiar--diagnostics-at-point))
                 (where (if file (format "%s:%d-%d" file (line-number-at-pos beg)
                                         ;; A defun's bounds end after its newline.
                                         (line-number-at-pos (max beg (1- end))))
                          (buffer-name))))
      (concat (format "In `%s`" where)
              (when diags
                (concat ", the checker reports:\n"
                        (mapconcat (lambda (d) (concat "- " d)) diags "\n")))
              "\n\n" (familiar--fenced (string-trim-right
                                         (buffer-substring-no-properties beg end))))))))

;;;###autoload
(defun familiar-handoff (instruction &optional choose)
  "Hand the context at point and INSTRUCTION to a running coding agent.
Targets come from `familiar-handoff-targets' (agent-shell, a claude-code
session for this project, else the clipboard for an agent in a terminal).
With prefix arg CHOOSE, pick the target.  Costs nothing here: the agent
does the work."
  (interactive
   (list (read-string "Ask the agent: "
                      (when (familiar--diagnostics-at-point) "Fix this. "))
         current-prefix-arg))
  (let* ((available (seq-filter (lambda (tg) (funcall (plist-get (cdr tg) :available)))
                                familiar-handoff-targets))
         (target (if (and choose (cdr available))
                     (assq (intern (completing-read "Hand off to: "
                                                    (mapcar #'car available) nil t))
                           available)
                   (car available)))
         (text (concat (string-trim instruction) "\n\n" (familiar-handoff-context))))
    (deactivate-mark)
    (funcall (plist-get (cdr target) :send) text)
    (message "familiar: handed to %s" (car target))
    (car target)))

;;;; Naming buffers

(defconst familiar--name-system
  "You name Emacs buffers after their contents. Reply with exactly two \
lines: 1. a short buffer name: lowercase words joined by hyphens, with the \
file extension that fits the major mode (e.g. nix-flake-notes.org); 2. a \
file path to save it under, inside the given project directory if there is \
one, else under ~/. No other text.")

(defun familiar--name-suggestion (callback)
  "Ask for a name and path for this buffer; call CALLBACK with (NAME . PATH)."
  (let ((text (buffer-substring-no-properties
               (point-min) (min (point-max) (+ (point-min) 6000)))))
    (familiar-request
     (format "Major mode: %s\nCurrent name: %s\nProject directory: %s\n\nContents:\n%s"
             major-mode (buffer-name)
             (or (and (fboundp 'project-current) (project-current)
                      (abbreviate-file-name (project-root (project-current))))
                 "none")
             (familiar--fenced text))
     :task 'name :system familiar--name-system
     :callback (lambda (response _info)
                 (when (stringp response)
                   (let ((lines (split-string (string-trim response) "\n" t "[ \t`]+")))
                     (when lines
                       (funcall callback (cons (car lines) (cadr lines))))))))))

;;;###autoload
(defun familiar-rename-buffer (&optional save)
  "Rename this buffer; a name suggested from its contents fills in as you wait.
Type your own and the suggestion stays out of the way.  With prefix arg SAVE,
then offer to save it under a suggested path."
  (interactive "P")
  (let* ((buf (current-buffer))
         (suggestion nil)
         (mb nil)
         (name
          (minibuffer-with-setup-hook
              (lambda ()
                (setq mb (current-buffer))
                (with-current-buffer buf
                  (familiar--name-suggestion
                   (lambda (s)
                     (setq suggestion s)
                     ;; Only into an untouched prompt.
                     (when (and (buffer-live-p mb) (minibufferp mb)
                                (string-empty-p (with-current-buffer mb
                                                  (minibuffer-contents-no-properties))))
                       (with-current-buffer mb
                         (insert (car s))
                         (when-let* ((w (get-buffer-window mb t)))
                           (set-window-point w (point-max)))))))))
            (read-string (format "Rename %s to (suggestion on its way): " (buffer-name))))))
    (unless (string-blank-p name)
      (rename-buffer name t))
    (when save
      (write-file (read-file-name "Save as: " nil nil nil
                                  (or (and suggestion (cdr suggestion)
                                           (expand-file-name (cdr suggestion)))
                                      (buffer-name)))))))

;;;; Commit messages

(defconst familiar--commit-system
  "You write git commit messages. Follow the repository's style exactly as \
shown by its recent subjects (e.g. Conventional Commits, scopes, casing, \
language). Subject at most 72 characters, imperative. Add a body, wrapped at \
72, only when the why is not obvious from the subject. Reply with only the \
message.")

(defun familiar--git (&rest args)
  "Output of git with ARGS, or nil if it fails."
  (with-temp-buffer
    (when (zerop (apply #'process-file "git" nil t nil args))
      (buffer-string))))

;;;###autoload
(defun familiar-commit-message (&optional escalate)
  "Write the commit message for the staged changes into this buffer.
Meant for git-commit buffers (magit's COMMIT_EDITMSG).  With prefix arg
ESCALATE, use the next model tier."
  (interactive "P")
  (let ((diff (familiar--git "diff" "--cached" "--stat" "--patch" "--no-color"
                             "--no-ext-diff"))
        (style (familiar--git "log" "-n" (number-to-string familiar-commit-style-samples)
                              "--format=%s"))
        (buf (current-buffer)))
    (when (string-empty-p (string-trim (or diff "")))
      (user-error "Nothing staged"))
    (message "familiar: writing commit message…")
    (familiar-request
     (format "Recent commit subjects (house style):\n%s\nStaged diff:\n%s"
             (or style "") diff)
     :task 'commit :escalate escalate :system familiar--commit-system
     :callback (lambda (response _info)
                 (when (and (stringp response) (buffer-live-p buf))
                   (with-current-buffer buf
                     (save-excursion
                       (goto-char (point-min))
                       (insert (string-trim (familiar--unfence response)) "\n"))
                     (message "familiar: message written")))))))

(provide 'familiar)
;;; familiar.el ends here
