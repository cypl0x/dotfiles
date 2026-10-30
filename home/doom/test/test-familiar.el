;;; test/test-familiar.el --- Batch tests for lisp/familiar -*- lexical-binding: t; -*-
;;
;; No network: `gptel-request' is replaced by a fake that answers instantly
;; with canned text and token counts.  Needs gptel on the load path (the
;; shims add Doom's build of it); skipped otherwise.
;;
;;; Code:

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "shims" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defconst test-familiar-available
  (and (require 'gptel nil t) (require 'gptel-anthropic nil t)))
(defvar test-familiar-backend
  (when test-familiar-available
    (gptel-make-anthropic "Claude-test" :key "sk-test" :stream t))
  "A Claude backend, as in the real config; creating it attaches model prices.")

(when test-familiar-available
  (load (expand-file-name "../lisp/familiar/familiar"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(defmacro test-familiar--with (reply &rest body)
  "Run BODY with an empty ledger, alerts captured in `alerts', and a fake
`gptel-request' answering REPLY with 1000 input / 200 output tokens.
Requests are captured in `requests' as (PROMPT MODEL SYSTEM)."
  (declare (indent 1))
  `(progn
     (skip-unless test-familiar-available)
     (let* ((familiar-backend test-familiar-backend)
            (familiar-ledger-file (make-temp-file "familiar-ledger"))
            (familiar--spent nil)
            (alerts nil)
            (requests nil)
            (familiar-notify-function (lambda (title body) (push (list title body) alerts))))
       (cl-letf (((symbol-function 'gptel-request)
                  (cl-function
                   (lambda (prompt &key callback system stream &allow-other-keys)
                     (push (list prompt gptel-model system) requests)
                     (let ((info (list :tokens (list :input 1000 :output 200 :cached 0))))
                       (if stream
                           (progn (funcall callback ,reply info)
                                  (funcall callback t info))
                         (funcall callback ,reply info)))))))
         (unwind-protect (progn ,@body)
           (delete-file familiar-ledger-file))))))

(ert-deftest familiar/cost-uses-gptel-prices-and-cache-discount ()
  (skip-unless test-familiar-available)
  ;; Haiku 5.5: $0.10 in, $0.50 out per MTok.
  (should (< (abs (- (familiar-cost 'claude-haiku-5-5 '(:input 1000000 :output 1000000 :cached 0))
                     0.6))
             1e-9))
  (should (< (abs (- (familiar-cost 'claude-haiku-5-5 '(:input 0 :output 0 :cached 1000000))
                     0.01))
             1e-9)))

(ert-deftest familiar/tiers-and-escalation ()
  (skip-unless test-familiar-available)
  (should (eq (familiar--model 'commit) 'claude-haiku-5-5))
  (should (eq (familiar--model 'commit t) 'claude-sonnet-5-5))
  (should (eq (familiar--model 'fix) 'claude-sonnet-5-5))
  (should (eq (familiar--model 'fix t) 'claude-opus-5-5))
  ;; The top tier does not overflow.
  (let ((familiar-task-tiers '((x . deep))))
    (should (eq (familiar--model 'x t) 'claude-opus-5-5))))

(ert-deftest familiar/requests-are-recorded-in-ledger ()
  (test-familiar--with "ok"
    (familiar-request "hi" :task 'commit :callback #'ignore)
    (let ((e (car (familiar--ledger))))
      (should (eq (nth 1 e) 'claude-haiku-5-5))
      (should (eq (nth 2 e) 'commit))
      (should (equal (seq-subseq e 3 6) '(1000 200 0)))
      (should (> (familiar-spent) 0)))))

(ert-deftest familiar/streamed-requests-recorded-once ()
  (test-familiar--with "chunk"
    (familiar-request "hi" :task 'explain :stream t :callback #'ignore)
    (should (= 1 (length (familiar--ledger))))))

(ert-deftest familiar/budget-alerts-fire-once-per-threshold ()
  (test-familiar--with "ok"
    (let ((familiar-budget 0.0003)        ; one fake haiku call costs $0.0002
          (familiar-budget-alerts '(0.5 0.8)))
      (familiar-request "a" :task 'commit :callback #'ignore)
      (should (= 1 (length alerts)))      ; crossed 50%
      (familiar-request "b" :task 'commit :callback #'ignore)
      (should (= 2 (length alerts))))))   ; crossed 80%, 50% not repeated

(ert-deftest familiar/failures-alert ()
  (test-familiar--with nil
    (familiar-request "a" :task 'commit :callback #'ignore)
    (should (string-match-p "failed" (caar alerts)))))

(ert-deftest familiar/unfence ()
  (skip-unless test-familiar-available)
  (should (equal (familiar--unfence "```elisp\n(a)\n(b)\n```") "(a)\n(b)"))
  (should (equal (familiar--unfence "  plain\n") "plain")))

(ert-deftest familiar/fix-inserts-smerge-proposal-for-defun ()
  (test-familiar--with "(defun f ()\n  2)"
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert ";; head\n(defun f ()\n  1)\n;; tail\n")
      (goto-char (point-min)) (forward-line 2)
      (familiar-fix "make it return 2")
      (should (bound-and-true-p smerge-mode))
      (should (string-match-p
               "<<<<<<< current\n(defun f ()\n  1)\n=======\n(defun f ()\n  2)\n>>>>>>> familiar\n"
               (buffer-string)))
      ;; Accepting the proposal leaves clean code.
      (goto-char (point-min))
      (smerge-next)
      (smerge-keep-lower)
      (should (equal (buffer-string) ";; head\n(defun f ()\n  2)\n;; tail\n")))))

(ert-deftest familiar/fix-identical-proposal-changes-nothing ()
  (test-familiar--with "(defun f ()\n  1)"
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "(defun f ()\n  1)\n")
      (goto-char 3)
      (familiar-fix "noop")
      (should (equal (buffer-string) "(defun f ()\n  1)\n")))))

(ert-deftest familiar/explain-streams-into-output-buffer ()
  (test-familiar--with "It returns one."
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "(defun f () 1)\n")
      (goto-char 3)
      (cl-letf (((symbol-function 'display-buffer) #'ignore))
        (familiar-explain))
      (should (string-match-p "(defun f () 1)" (car (car requests))))
      (with-current-buffer "*familiar*"
        (should (string-match-p "It returns one." (buffer-string)))
        (should (string-match-p "1000 in / 200 out" header-line-format))))))

(ert-deftest familiar/explain-reads-the-source-before-showing-output ()
  ;; Showing the output can make another buffer current (seen live: the
  ;; code fence was labelled with that buffer's mode, "+dashboard").
  (test-familiar--with "ok"
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "(defun f () 1)\n")
      (goto-char 3)
      (cl-letf (((symbol-function 'display-buffer)
                 (lambda (&rest _) (set-buffer (get-buffer-create " other")))))
        (familiar-explain))
      (should (string-match-p "```emacs-lisp\n(defun f () 1)" (car (car requests)))))))

(ert-deftest familiar/commit-message-from-staged-diff-in-house-style ()
  (test-familiar--with "feat(x): add file"
    (let* ((repo (make-temp-file "familiar-repo" t))
           (default-directory (file-name-as-directory repo)))
      (unwind-protect
          (progn
            (dolist (args '(("init" "-q" "-b" "main")
                            ("-c" "user.name=t" "-c" "user.email=t@t"
                             "commit" "-q" "--allow-empty" "-m" "chore: start")))
              (apply #'process-file "git" nil nil nil args))
            (write-region "hello\n" nil "a.txt")
            (process-file "git" nil nil nil "add" "a.txt")
            (with-temp-buffer
              (insert "\n# Please enter the commit message\n")
              (familiar-commit-message)
              (should (string-prefix-p "feat(x): add file\n" (buffer-string)))
              (let ((prompt (car (car requests))))
                (should (string-match-p "chore: start" prompt))   ; house style
                (should (string-match-p "\\+hello" prompt)))))    ; staged diff
        (delete-directory repo t)))))

(ert-deftest familiar/commit-message-refuses-empty-stage ()
  (test-familiar--with "x"
    (let* ((repo (make-temp-file "familiar-repo" t))
           (default-directory (file-name-as-directory repo)))
      (unwind-protect
          (progn
            (process-file "git" nil nil nil "init" "-q")
            (with-temp-buffer
              (should-error (familiar-commit-message) :type 'user-error)
              (should-not requests)))
        (delete-directory repo t)))))


(defmacro test-familiar--in-repo (&rest body)
  "Run BODY in a fresh git repo with one commit and `repo' bound."
  `(let* ((repo (file-name-as-directory (make-temp-file "familiar-repo" t)))
          (default-directory repo))
     (unwind-protect
         (progn
           (dolist (args '(("init" "-q" "-b" "main")
                           ("-c" "user.name=t" "-c" "user.email=t@t"
                            "commit" "-q" "--allow-empty" "-m" "start")))
             (apply #'process-file "git" nil nil nil args))
           ,@body)
       (delete-directory repo t))))

(ert-deftest familiar/review-prefers-staged-changes ()
  (test-familiar--with "Looks fine."
    (test-familiar--in-repo
     (write-region "staged\n" nil "a.txt")
     (process-file "git" nil nil nil "add" "a.txt")
     (write-region "unstaged\n" nil "b.txt")
     (process-file "git" nil nil nil "add" "-N" "b.txt")
     (cl-letf (((symbol-function 'display-buffer) #'ignore))
       (familiar-review))
     (let ((prompt (caar requests)))
       (should (string-match-p "these staged changes" prompt))
       (should (string-match-p "\\+staged" prompt))
       (should-not (string-match-p "\\+unstaged" prompt)))
     ;; Reviews default to the smart tier.
     (should (eq (nth 1 (car requests)) 'claude-sonnet-5-5)))))

(ert-deftest familiar/review-falls-back-to-unstaged-and-truncates ()
  (test-familiar--with "ok"
    (test-familiar--in-repo
     (write-region "x\n" nil "a.txt")
     (process-file "git" nil nil nil "add" "a.txt")
     (process-file "git" nil nil nil "-c" "user.name=t" "-c" "user.email=t@t"
                   "commit" "-q" "-m" "a")
     (write-region (make-string 5000 ?y) nil "a.txt")
     (let ((familiar-review-max-chars 1000))
       (cl-letf (((symbol-function 'display-buffer) #'ignore))
         (familiar-review)))
     (let ((prompt (caar requests)))
       (should (string-match-p "these unstaged changes" prompt))
       (should (string-match-p "truncated by familiar-review-max-chars" prompt))
       (should (< (length prompt) 1300))))))

(ert-deftest familiar/review-refuses-clean-tree ()
  (test-familiar--with "x"
    (test-familiar--in-repo
     (should-error (familiar-review) :type 'user-error)
     (should-not requests))))

(ert-deftest familiar/explain-compilation-error-sends-message-and-locus ()
  (test-familiar--with "Undefined variable."
    (let* ((dir (file-name-as-directory (make-temp-file "familiar-build" t)))
           (default-directory dir))
      (unwind-protect
          (progn
            (write-region "line one\nline two\n(boom)\nline four\n" nil "src.el")
            (with-current-buffer (get-buffer-create "*familiar-test-compilation*")
              (let ((inhibit-read-only t)) (erase-buffer))
              (setq default-directory dir)
              (insert "make: building\nsrc.el:3:2: error: void-variable boom\n  more detail\n")
              (compilation-mode)
              (compilation--ensure-parse (point-max))
              (goto-char (point-min)) (forward-line 1)
              (cl-letf (((symbol-function 'display-buffer) #'ignore))
                (familiar-explain-compilation-error))
              (kill-buffer))
            (let ((prompt (caar requests)))
              (should (string-match-p "error: void-variable boom" prompt))
              (should (string-match-p "more detail" prompt))
              (should (string-match-p "src.el" prompt))
              (should (string-match-p "error on line 3" prompt))
              (should (string-match-p "(boom)" prompt))))
        (delete-directory dir t)))))

(ert-deftest familiar/explain-compilation-error-needs-an-error ()
  (test-familiar--with "x"
    (with-temp-buffer
      (insert "all good\n")
      (compilation-mode)
      (goto-char (point-min))
      (should-error (familiar-explain-compilation-error) :type 'user-error)
      (should-not requests))))


(ert-deftest familiar/prices-fall-back-when-gptel-lacks-the-model ()
  "An older gptel without the model's metadata must not make spend $0."
  (skip-unless test-familiar-available)
  (let ((in (get 'claude-haiku-5-5 :input-cost))
        (out (get 'claude-haiku-5-5 :output-cost)))
    (unwind-protect
        (progn
          (put 'claude-haiku-5-5 :input-cost nil)
          (put 'claude-haiku-5-5 :output-cost nil)
          (should (equal (familiar--prices 'claude-haiku-5-5) '(0.10 . 0.50)))
          (should (> (familiar-cost 'claude-haiku-5-5 '(:input 1000)) 0)))
      (put 'claude-haiku-5-5 :input-cost in)
      (put 'claude-haiku-5-5 :output-cost out))))

(ert-deftest familiar/unknown-price-warns-once-and-counts-zero ()
  (skip-unless test-familiar-available)
  (let ((familiar--unpriced-warned nil) (warnings 0))
    (cl-letf (((symbol-function 'display-warning) (lambda (&rest _) (cl-incf warnings))))
      (should (= 0 (familiar-cost 'claude-unknown-9 '(:input 1000 :output 10))))
      (familiar-cost 'claude-unknown-9 '(:input 1))
      (should (= warnings 1)))))


(ert-deftest familiar/handoff-picks-first-available-target ()
  (skip-unless test-familiar-available)
  (let* ((sent nil)
         (familiar-handoff-targets
          `((dead :available ignore :send ,(lambda (_) (error "Not me")))
            (live :available always :send ,(lambda (text) (setq sent text)))
            (later :available always :send ,(lambda (_) (error "Not me either"))))))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "(defun f () 1)\n")
      (goto-char 3)
      (should (eq (familiar-handoff "Make it return 2.") 'live)))
    (should (string-prefix-p "Make it return 2.\n\nIn `" sent))
    (should (string-match-p "(defun f () 1)" sent))))

(ert-deftest familiar/handoff-context-names-file-and-lines ()
  (skip-unless test-familiar-available)
  (let ((file (make-temp-file "familiar-ctx" nil ".el")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert ";; x\n(defun g ()\n  2)\n")
          (goto-char (point-min)) (forward-line 2)
          (let ((ctx (familiar-handoff-context)))
            (should (string-match-p ":2-3`" ctx))
            (should (string-match-p "(defun g ()" ctx)))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(ert-deftest familiar/handoff-clipboard-fallback ()
  (skip-unless test-familiar-available)
  (let ((kill-ring nil))
    (with-temp-buffer
      (insert "plain text here\n")
      (should (eq (familiar-handoff "Explain.") 'clipboard)))
    (should (string-prefix-p "Explain." (car kill-ring)))))


;;; familiar-mcp (tool functions; the MCP wiring is tested live)

(load (expand-file-name "../lisp/familiar/familiar-mcp"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro test-familiar--with-elisp-file (content &rest body)
  "Write CONTENT to a temp .el file bound to `file' and run BODY."
  `(let ((file (make-temp-file "familiar-mcp" nil ".el" ,content)))
     (cl-letf (((symbol-function 'mcp-server-lib-tool-throw)
                (lambda (msg) (error "%s" msg))))
       (unwind-protect (progn ,@body)
         (when-let* ((b (find-buffer-visiting file))) (kill-buffer b))
         (delete-file file)))))

(ert-deftest familiar-mcp/definitions-via-elisp-xref ()
  (test-familiar--with-elisp-file
   ";;; x -*- lexical-binding: t -*-\n(defun my-f (s)\n  (string-trim s))\n"
   (let ((out (familiar-mcp-definitions file "3" "string-trim")))
     (should (string-match-p "\\[definitions via elisp\\]" out))
     ;; A real line, not "?": elisp locations are resolved via markers.
     (should (string-match-p "subr\\(-x\\)?\\.el:[0-9]+: (defun string-trim)" out)))))

(ert-deftest familiar-mcp/outline-lists-definitions-with-lines ()
  (test-familiar--with-elisp-file
   ";;; x -*- lexical-binding: t -*-\n(defun alpha () 1)\n\n(defvar beta 2)\n(defun gamma () 3)\n"
   (let ((out (familiar-mcp-outline file)))
     (should (string-match-p "^2: .*alpha" out))
     (should (string-match-p "^5: .*gamma" out)))))

(ert-deftest familiar-mcp/errors-are-reported ()
  (test-familiar--with-elisp-file
   "(defun a () 1)\n"
   (should-error (familiar-mcp-definitions file "0" "a"))
   (should-error (familiar-mcp-definitions file "1" "nonexistent-xyz"))
   (should-error (familiar-mcp-outline "/nonexistent/file.el"))))

(ert-deftest familiar-mcp/reads-the-file-as-on-disk ()
  ;; An agent edits the file after an earlier call left a buffer behind.
  (test-familiar--with-elisp-file
   "(defun alpha () 1)\n"
   (familiar-mcp-outline file)
   (with-temp-file file (insert "\n\n(defun beta () 2)\n"))
   (set-file-times file (time-add nil 5))
   (should (string-match-p "^3: .*beta" (familiar-mcp-outline file)))
   ;; Unsaved edits in Emacs and a newer file on disk: refuse, don't guess.
   (with-current-buffer (find-buffer-visiting file) (insert ";; edit\n"))
   (set-file-times file (time-add nil 10))
   (should-error (familiar-mcp-outline file))
   (with-current-buffer (find-buffer-visiting file) (set-buffer-modified-p nil))))

(ert-deftest familiar-mcp/tool-specs-are-read-only ()
  (dolist (spec familiar-mcp--tools)
    (should (fboundp (car spec)))
    (should (plist-get (cdr spec) :read-only))))

(provide 'test-familiar)
;;; test-familiar.el ends here
