;;; test/test-familiar-ask.el --- Batch tests for familiar-ask -*- lexical-binding: t; -*-
;;
;; No network: `gptel-send' is replaced by a fake that records the buffer it
;; was called in.  Reuses `test-familiar--with' for the ledger.
;;
;;; Code:

(require 'ert)
(unless (fboundp 'test-familiar--with)        ; when run on its own
  (load (expand-file-name "test-familiar" (file-name-directory (or load-file-name buffer-file-name))) nil t))

(when test-familiar-available
  (load (expand-file-name "../lisp/familiar/familiar-ask"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(defun test-familiar-ask--tool (name)
  (gptel-tool-function (seq-find (lambda (tl) (equal (gptel-tool-name tl) name))
                                 familiar-ask-tools)))

(defmacro test-familiar-ask--in (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with point after \"POINT\"."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,text)
     (goto-char (point-min))
     (search-forward "POINT")
     ,@body))

(ert-deftest familiar-ask/context-describes-buffer-point-and-text ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--in "* Notes\nSome text POINT here\n"
    (let ((ctx (familiar-ask--context (familiar-ask--capture))))
      (should (string-match-p "^#\\+begin_context" ctx))
      (should (string-match-p "(visits no file), org-mode" ctx))
      (should (string-match-p "Point: line 2, column 15" ctx))
      (should (string-match-p "Around point, lines 1-3" ctx))
      (should (string-match-p "Some text POINT here" ctx))
      (should (string-match-p "#\\+end_context\\'" ctx)))))

(ert-deftest familiar-ask/context-prefers-the-region ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--in "one\ntwo POINT\nthree\n"
    (let ((transient-mark-mode t))
      (set-mark (line-beginning-position))
      (goto-char (line-end-position))
      (activate-mark)
      (let ((ctx (familiar-ask--context (familiar-ask--capture))))
        (should (string-match-p "Region (what \"this\" refers to), lines 2-2" ctx))
        (should (string-match-p "two POINT" ctx))
        (should-not (string-match-p "three" ctx))))))

(ert-deftest familiar-ask/context-escapes-org-in-the-text ()
  ;; A "* heading" inside the src block would end the block in Org.
  (skip-unless test-familiar-available)
  (test-familiar-ask--in "* heading POINT\n"
    (should (string-match-p "^,\\* heading POINT"
                            (familiar-ask--context (familiar-ask--capture))))))

(ert-deftest familiar-ask/buffer-text-tool-reads-lines ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (rename-buffer "familiar-ask-test-buffer" t)
    (insert "a\nb\nc\nd\n")
    (should (equal (funcall (test-familiar-ask--tool "buffer_text") (buffer-name) 2 3)
                   "b\nc\n"))
    (should (equal (funcall (test-familiar-ask--tool "buffer_text") (buffer-name))
                   "a\nb\nc\nd\n"))))

(ert-deftest familiar-ask/replace-tool-is-an-undoable-unique-edit ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (rename-buffer "familiar-ask-test-replace" t)
    (buffer-enable-undo)
    (insert "alpha beta gamma beta")
    (undo-boundary)
    (let ((replace (test-familiar-ask--tool "replace_in_buffer")))
      (should-error (funcall replace (buffer-name) "beta" "B"))   ; twice
      (should-error (funcall replace (buffer-name) "delta" "D"))  ; never
      (funcall replace (buffer-name) "alpha" "ALPHA")
      (should (equal (buffer-string) "ALPHA beta gamma beta"))
      (primitive-undo 1 buffer-undo-list)
      (should (equal (buffer-string) "alpha beta gamma beta")))))

(ert-deftest familiar-ask/set-minibuffer-needs-a-minibuffer ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask--origin (list :buffer (current-buffer))))
    (should-error (funcall (test-familiar-ask--tool "set_minibuffer") "foo"))))

(ert-deftest familiar-ask/ask-appends-prompt-and-folded-context-then-sends ()
  (skip-unless test-familiar-available)
  (let* ((familiar-ask-directory (make-temp-file "familiar-ask" t))
         (familiar-ask--buffer-name "*familiar-ask-test*")
         (sent nil))
    (cl-letf (((symbol-function 'gptel-send) (lambda (&rest _) (setq sent (current-buffer))))
              ((symbol-function 'display-buffer) #'ignore))
      (unwind-protect
          (test-familiar-ask--in "text POINT\n"
            (setq familiar-ask--origin (familiar-ask--capture))
            (let ((buf (familiar-ask "What is this?" t)))
              (should (eq sent buf))
              (with-current-buffer buf
                (should familiar-ask-mode)
                (should (equal gptel-tools familiar-ask-tools))
                (should (eq gptel-model (alist-get familiar-ask-tier familiar-models)))
                (should (string-match-p "^\\*\\* What is this\\?  \\[[^]]+\\]\n#\\+begin_context" (buffer-string)))
                (should (string-prefix-p (expand-file-name familiar-ask-directory) buffer-file-name))
                ;; @follow-up: the same conversation takes the next question.
                (setq familiar-ask--origin (familiar-ask--capture))
                (should (eq (familiar-ask "And this? @follow-up") buf))
                (should (= 2 (how-many "^\\*\\* " (point-min) (point-max)))))))
        (when-let* ((b (get-buffer familiar-ask--buffer-name)))
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b))
        (delete-directory familiar-ask-directory t)))))

(ert-deftest familiar-ask/turns-are-recorded-in-the-ledger ()
  (test-familiar--with "unused"
    (with-temp-buffer
      (setq-local gptel-model 'claude-haiku-5-5)
      (familiar-ask-mode 1)
      (gptel--update-token-usage '(:input 1000 :output 200 :cached 0))
      (let ((entry (car (last (familiar--ledger)))))
        (should (eq (nth 1 entry) 'claude-haiku-5-5))
        (should (eq (nth 2 entry) 'ask))))))

(ert-deftest familiar-ask/edit-keep-revives-the-draft ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask--draft nil))
    (with-temp-buffer
      (insert "  a longer prompt  ")
      (cl-letf (((symbol-function 'quit-window) #'ignore))
        (familiar-ask-edit-keep)))
    (should (equal familiar-ask--draft "a longer prompt"))))



(ert-deftest familiar-ask/after-response-only-saves ()
  ;; gptel leaves the next "** " itself; adding one doubled the headings.
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert "** q\nanswer\n\n** ")
    (cl-letf (((symbol-function 'save-buffer) #'ignore))
      (familiar-ask--after-response nil nil)
      (familiar-ask--after-response nil nil))
    (should (equal (buffer-string) "** q\nanswer\n\n** "))))

(ert-deftest familiar-ask/asks-under-the-empty-heading-gptel-left ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask--buffer-name "*familiar-ask-test*"))
    (cl-letf (((symbol-function 'gptel-send) #'ignore)
              ((symbol-function 'display-buffer) #'ignore))
      (unwind-protect
          (dolist (tail '("** " "**\n\n"))   ; fresh, and trimmed in older files
            (with-current-buffer (get-buffer-create familiar-ask--buffer-name)
              (erase-buffer)
              (org-mode)
              (insert "** q\nanswer\n\n" tail))
            (test-familiar-ask--in "x POINT\n"
              (setq familiar-ask--origin (familiar-ask--capture))
              (with-current-buffer (familiar-ask "next" 'follow-up)
                (should (= 2 (how-many "^\\*\\*" (point-min) (point-max))))
                (should (string-match-p "answer\n\n\\*\\* next  \\[" (buffer-string))))))
        (kill-buffer familiar-ask--buffer-name)))))


(ert-deftest familiar-ask/transcript-drops-context-and-title ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert ":PROPERTIES:\n:GPTEL_MODEL: m\n:END:\n#+title: familiar-ask x\n\n** q  [2026-11-04 Mi 06:40]\n#+begin_context\nBuffer: b\n#+end_context\n\nanswer\n\n** ")
    (should (equal (familiar-ask--transcript) "** q  [2026-11-04 Mi 06:40]\n\nanswer\n\n**"))))

(ert-deftest familiar-ask/prompt-heading-is-stamped-first-line ()
  (skip-unless test-familiar-available)
  (let* ((familiar-ask-directory (make-temp-file "familiar-ask" t))
         (familiar-ask--buffer-name "*familiar-ask-test*"))
    (cl-letf (((symbol-function 'gptel-send) #'ignore)
              ((symbol-function 'display-buffer) #'ignore))
      (unwind-protect
          (test-familiar-ask--in "x POINT\n"
            (setq familiar-ask--origin (familiar-ask--capture))
            (with-current-buffer (familiar-ask "first line\nsecond line" t)
              (should (string-match-p
                       "^\\*\\* first line  \\[[0-9-]+ [[:alpha:]]+ [0-9:]+\\]\nsecond line\n#\\+begin_context"
                       (buffer-string)))
              (should (string-match-p "1 prompt " (familiar-ask--header-line)))))
        (when-let* ((b (get-buffer familiar-ask--buffer-name)))
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b))
        (delete-directory familiar-ask-directory t)))))

(ert-deftest familiar-ask/confirm-setting-reaches-the-conversation ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask-confirm-tools nil))
    (with-temp-buffer
      (cl-letf (((symbol-function 'gptel-mode) #'ignore))
        (familiar-ask--setup (current-buffer)))
      (should (local-variable-p 'gptel-confirm-tool-calls))
      (should (null gptel-confirm-tool-calls)))))

(ert-deftest familiar-ask/insert-at-prompt-in-eshell-replaces-input ()
  (skip-unless test-familiar-available)
  (require 'eshell)
  (let ((eshell-buffer-name "*familiar-ask-eshell-test*")
        (eshell-history-file-name nil))
    (with-current-buffer (eshell t)
      (unwind-protect
          (progn
            (goto-char (point-max))
            (insert "half-typed")
            (let ((familiar-ask--origin (list :buffer (current-buffer) :point (point))))
              (funcall (test-familiar-ask--tool "insert_at_prompt") "ls -la"))
            (should (equal (buffer-substring eshell-last-output-end (point-max)) "ls -la")))
        (let ((kill-buffer-query-functions nil)) (kill-buffer))))))

(ert-deftest familiar-ask/insert-at-prompt-elsewhere-inserts-at-point ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert "ab")
    (let ((familiar-ask--origin (list :buffer (current-buffer) :point 2)))
      (funcall (test-familiar-ask--tool "insert_at_prompt") "X"))
    (should (equal (buffer-string) "aXb"))))

(ert-deftest familiar-ask/context-functions-primary-replaces-buffer-text ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--in "tile tile tile POINT\n"
    (let* ((familiar-ask-context-functions
            (list (lambda () (list :title "Selection on page 3 (what \"this\" refers to)"
                                   :text "dependently typed programming language" :primary t))
                  (lambda () nil)))
           (ctx (familiar-ask--context (familiar-ask--capture))))
      (should (string-match-p "Selection on page 3 (what \"this\" refers to):\n#\\+begin_src text\ndependently typed" ctx))
      (should-not (string-match-p "Around point" ctx))
      (should-not (string-match-p "tile tile" ctx)))))

(ert-deftest familiar-ask/lisp-callers-get-a-fresh-origin ()
  ;; A stale origin from an earlier interactive ask must not leak in.
  (skip-unless test-familiar-available)
  (let* ((familiar-ask-directory (make-temp-file "familiar-ask" t))
         (familiar-ask--buffer-name "*familiar-ask-test*")
         (familiar-ask--origin (list :buffer (get-buffer-create " *stale*") :point 1)))
    (cl-letf (((symbol-function 'gptel-send) #'ignore)
              ((symbol-function 'display-buffer) #'ignore))
      (unwind-protect
          (test-familiar-ask--in "here POINT\n"
            (with-current-buffer (familiar-ask "q" t)
              (should (string-match-p "here POINT" (buffer-string)))
              (should-not (string-match-p "\\*stale\\*" (buffer-string)))))
        (when-let* ((b (get-buffer familiar-ask--buffer-name)))
          (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b))
        (kill-buffer " *stale*")
        (delete-directory familiar-ask-directory t)))))

(ert-deftest familiar-ask/tool-results-are-capped ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask-tool-result-max 10))
    (with-temp-buffer
      (rename-buffer "familiar-ask-cap-test" t)
      (insert (make-string 50 ?x))
      (let ((out (funcall (test-familiar-ask--tool "buffer_text") (buffer-name))))
        (should (string-prefix-p "xxxxxxxxxx\n[… 40 more characters cut" out))))))

(defconst test-familiar-ask--answer
  "** q  [2026-11-04 Mi 07:40]
#+begin_context
Buffer: x
#+end_context

Use ~forward-word~ or press =C-f=; ~n~ is a variable.

#+begin_src emacs-lisp
(setq test-familiar-ask--applied 'yes)
#+end_src

#+begin_src sh
du -sh .
#+end_src

** ")

(defvar test-familiar-ask--applied nil)

(ert-deftest familiar-ask/suggestions-from-the-latest-answer ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert test-familiar-ask--answer)
    (should (equal (mapcar (lambda (s) (list (car s) (cadr s))) (familiar-ask-suggestions))
                   '((command forward-word) (keys "C-f")
                     (elisp "(setq test-familiar-ask--applied 'yes)\n")
                     (shell "du -sh ."))))))

(ert-deftest familiar-ask/apply-runs-where-asked ()
  (skip-unless test-familiar-available)
  (let ((origin-buf (generate-new-buffer " *origin*"))
        (test-familiar-ask--applied nil))
    (unwind-protect
        (with-temp-buffer
          (insert test-familiar-ask--answer)
          (with-current-buffer origin-buf (insert "one two three") (goto-char 1))
          (let ((familiar-ask--origin (list :buffer origin-buf :point 1))
                (sugg (familiar-ask-suggestions)))
            (familiar-ask--apply (nth 0 sugg))            ; forward-word
            (should (= (with-current-buffer origin-buf (point)) 4))
            (familiar-ask--apply (nth 2 sugg))            ; the elisp block
            (should (eq test-familiar-ask--applied 'yes))))
      (kill-buffer origin-buf))))

(ert-deftest familiar-ask/converter-flushes-a-trailing-marker ()
  ;; gptel held back the final "*" of "*Magit*" forever: "/Magit".
  (skip-unless (and test-familiar-available (require 'gptel-org nil t)))
  (with-temp-buffer
    (org-mode)
    (let* ((start (point-marker))
           (convert (gptel--stream-convert-markdown->org start)))
      (insert (funcall convert "*Ma") (funcall convert "git*"))
      (run-hook-with-args 'gptel-post-response-functions
                          (marker-position start) (point-max))
      (should (equal (buffer-string) "/Magit/")))))

(ert-deftest familiar-ask/set-minibuffer-refuses-a-closed-one ()
  ;; A minibuffer buffer outlives its prompt; writing there would report
  ;; success while changing nothing the user sees.
  (skip-unless test-familiar-available)
  (let* ((mb (get-buffer-create " *Minibuf-9*"))
         (familiar-ask--origin (list :buffer (current-buffer) :minibuffer mb)))
    (unwind-protect
        (should-error (funcall (test-familiar-ask--tool "set_minibuffer") "!dired"))
      (kill-buffer mb))))

;;; test-familiar-ask.el ends here

(ert-deftest familiar-ask/keywords-are-taken-out ()
  (skip-unless test-familiar-available)
  (should (equal (familiar-ask--keywords "what is this @echo") '("what is this" echo)))
  (should (equal (familiar-ask--keywords "@follow-up and then?") '("and then?" follow-up)))
  (should (equal (car (familiar-ask--keywords "mail me@echo.org")) "mail me@echo.org"))
  (should (equal (familiar-ask--keywords "@fast quick") '("@fast quick"))))

(defmacro test-familiar-ask--asking (&rest body)
  "BODY with sends and windows faked, in a throwaway conversation directory."
  `(let ((familiar-ask-directory (make-temp-file "familiar-ask" t))
         (familiar-ask--buffer-name "*familiar-ask-test*")
         (displayed nil))
     (cl-letf (((symbol-function 'gptel-send) #'ignore)
               ((symbol-function 'display-buffer) (lambda (b &rest _) (push b displayed) nil)))
       (unwind-protect
           (test-familiar-ask--in "text POINT\n" ,@body)
         (dolist (b (buffer-list))
           (when (string-prefix-p "*familiar-ask-test*" (buffer-name b))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b)))
         (delete-directory familiar-ask-directory t)))))

(ert-deftest familiar-ask/each-ask-is-fresh-by-default ()
  ;; Following up re-sent every earlier turn and its context: costly.
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let* ((familiar-ask-follow-up nil)
          (first (familiar-ask "one"))
          (second (familiar-ask "two")))
     (should-not (eq first second))
     (with-current-buffer second
       (should (= 1 (how-many "^\\*\\* " (point-min) (point-max)))))
     (should (eq (familiar-ask "three @follow-up") second))
     (let ((familiar-ask-follow-up t))
       (should (eq (familiar-ask "four") second))
       (should-not (eq (familiar-ask "five @new") second))))))

(ert-deftest familiar-ask/a-saved-idle-conversation-is-closed-not-kept ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let ((first (familiar-ask "one")))
     (with-current-buffer first (let ((save-silently t)) (save-buffer)))
     (familiar-ask "two")
     (should-not (buffer-live-p first))
     ;; Unsaved (still streaming): kept, renamed.
     (let ((second (get-buffer familiar-ask--buffer-name)))
       (familiar-ask "three")
       (should (buffer-live-p second))
       (should (string-prefix-p "*familiar-ask (old)*" (buffer-name second)))))))

(ert-deftest familiar-ask/echo-shows-no-window-and-answers-in-the-echo-area ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let ((buf (familiar-ask "what is this? @echo")))
     (should-not displayed)
     (with-current-buffer buf
       (should familiar-ask--echo)
       (should (string-match-p "^\\*\\* what is this\\?  \\[" (buffer-string)))
       (should (string-match-p "echo area" (buffer-string)))
       (goto-char (point-max))
       (insert "#+begin_tool (x)\nresult\n#+end_tool\nIt is a *test*.\n\n** ")
       (cl-letf (((symbol-function 'save-buffer) #'ignore)
                 ((symbol-function 'run-at-time) (lambda (_ _ f) (funcall f))))
         (let (shown)
           (cl-letf (((symbol-function 'message)
                      (lambda (fmt &rest args) (setq shown (apply #'format fmt args)))))
             (familiar-ask--after-response nil nil))
           (should (equal (substring-no-properties shown) "It is a *test*."))
           (should-not familiar-ask--echo)))))
   (should (familiar-ask "and a window this time"))
   (should displayed)))

(ert-deftest familiar-ask/answers-open-from-the-window-asked-from ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let ((win (selected-window)) seen)
     (cl-letf (((symbol-function 'display-buffer)
                (lambda (&rest _) (setq seen (selected-window)) nil)))
       (familiar-ask "q" t (plist-put (familiar-ask--capture) :window win)))
     (should (eq seen win)))))

(ert-deftest familiar-ask/prompt-completes-keywords ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert "explain @fo")
    (let ((capf (familiar-ask--keywords-capf)))
      (should (member "follow-up" (all-completions "fo" (nth 2 capf))))
      (should (string-match-p "continue" (funcall (plist-get (nthcdr 3 capf) :annotation-function)
                                                  "follow-up"))))))

(ert-deftest familiar-ask/asked-from-a-minibuffer-shows-again-after-it-exits ()
  ;; Leaving M-x undid the popup (`read-minibuffer-restore-windows').
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let ((minibuffer-exit-hook nil))
     (cl-letf (((symbol-function 'run-at-time) (lambda (_ _ f &rest args) (apply f args))))
       (let ((buf (familiar-ask "q" t (plist-put (familiar-ask--capture) :minibuffer (current-buffer)))))
         (should (equal displayed (list buf)))
         (should (= 1 (length minibuffer-exit-hook)))
         (run-hooks 'minibuffer-exit-hook)
         (should (equal displayed (list buf buf)))
         (should-not minibuffer-exit-hook))))))

(ert-deftest familiar-ask/header-shows-the-model-that-answered ()
  ;; An @fast turn was shown with the conversation's default model.
  (test-familiar--with "unused"
    (with-temp-buffer
      (setq-local gptel-model 'claude-sonnet-5-5)
      (familiar-ask-mode 1)
      (let ((gptel--fsm-last (gptel-make-fsm :info '(:model claude-haiku-5-5))))
        (familiar-ask--record-a '(:input 10 :output 2 :cached 0)))
      (should (string-match-p "claude-haiku-5-5" (familiar-ask--header-line))))))

;;; familiar-mcp-client

(when test-familiar-available
  (load (expand-file-name "../lisp/familiar/familiar-mcp-client"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(defmacro test-familiar-mcp--with-config (json &rest body)
  (declare (indent 1))
  `(let* ((familiar-mcp-client-config (make-temp-file "claude" nil ".json" ,json))
          (familiar-mcp-client--cache nil))
     (unwind-protect (progn ,@body)
       (delete-file familiar-mcp-client-config))))

(ert-deftest familiar-mcp-client/servers-of-user-and-project ()
  (skip-unless test-familiar-available)
  (test-familiar-mcp--with-config
      "{\"mcpServers\": {\"emacs\": {\"type\": \"stdio\", \"command\": \"e\"},
                         \"web\": {\"type\": \"http\", \"url\": \"https://x\"},
                         \"nix\": {\"command\": \"mcp-nixos\"}},
        \"projects\": {\"/p\": {\"mcpServers\": {\"github\": {\"type\": \"stdio\", \"command\": \"npx\",
                                 \"args\": [\"-y\", \"gh\"], \"env\": {\"TOKEN\": \"t\"}}}}}}"
    (should (equal (familiar-mcp-client-servers "/p")
                   '(("nix" :command "mcp-nixos" :args nil :env nil)
                     ("github" :command "npx" :args ("-y" "gh") :env (:TOKEN "t")))))
    (should (equal (mapcar #'car (familiar-mcp-client-servers "/elsewhere")) '("nix")))))

(ert-deftest familiar-mcp-client/server-keywords-are-prompt-keywords ()
  (skip-unless test-familiar-available)
  (cl-letf (((symbol-function 'familiar-mcp-client-servers)
             (lambda (&rest _) '(("github" :command "npx")))))
    (should (equal (familiar-ask--keywords "@github open issues?")
                   '("open issues?" github)))
    (with-temp-buffer
      (insert "@git")
      (should (member "github" (all-completions "git" (nth 2 (familiar-ask--keywords-capf))))))))

(ert-deftest familiar-mcp-client/tools-only-for-the-turn-that-names-them ()
  (skip-unless test-familiar-available)
  (let (asked ran)
    (cl-letf (((symbol-function 'familiar-mcp-client-servers)
               (lambda (&rest _) '(("github" :command "npx"))))
              ((symbol-function 'familiar-mcp-client--connection) (lambda (&rest _) 'conn))
              ((symbol-function 'mcp--tools)
               (lambda (_) '((:name "list_issues") (:name "create_issue"))))
              ((symbol-function 'mcp-make-text-tool)
               (lambda (_server tool _async)
                 (list :name tool :async t :description "d" :args nil
                       :function (lambda (cb &rest _) (push tool ran) (funcall cb "ok")))))
              ((symbol-function 'y-or-n-p) (lambda (p) (push p asked) nil)))
      (should-not (familiar-mcp-client-turn-tools '(echo) nil))
      (let* ((tools (familiar-mcp-client-turn-tools '(github) nil))
             (call (lambda (name)
                     (let (out)
                       (funcall (gptel-tool-function
                                 (seq-find (lambda (tl) (equal (gptel-tool-name tl) name)) tools))
                                (lambda (r) (setq out r)))
                       out))))
        (should (equal (mapcar #'gptel-tool-name tools) '("list_issues" "create_issue")))
        (should (equal (funcall call "list_issues") "ok"))       ; reads: at once
        (should (string-match-p "declined" (funcall call "create_issue")))
        (should (equal ran '("list_issues")))
        (should (= 1 (length asked)))))))

(ert-deftest familiar-mcp-client/read-only-by-hint-server-then-name ()
  (skip-unless test-familiar-available)
  (let ((familiar-mcp-client-read-only-servers '("nixos-mcp")))
    (should (familiar-mcp-client--read-only-p "nixos-mcp" '(:name "nix")))
    (should (familiar-mcp-client--read-only-p "github" '(:name "list_issues")))
    (should-not (familiar-mcp-client--read-only-p "github" '(:name "merge_pull_request")))
    ;; The tool's own word wins either way.
    (should (familiar-mcp-client--read-only-p "x" '(:name "merge" :annotations (:readOnlyHint t))))
    (should-not (familiar-mcp-client--read-only-p "nixos-mcp" '(:name "nix" :annotations (:readOnlyHint :false))))))

;;; familiar-mcp-http

(load (expand-file-name "../lisp/familiar/familiar-mcp-http"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro test-mcp-http--with (&rest body)
  "BODY with a throwaway token and a processor that echoes the method."
  `(let* ((familiar-mcp-http-token-file (make-temp-file "mcp-token"))
          (familiar-mcp-http-process-function
           (lambda (json _id)
             (let ((m (json-parse-string json :object-type 'alist)))
               (when (assq 'id m)
                 (json-serialize `((jsonrpc . "2.0") (id . ,(alist-get 'id m))
                                   (result . ((echo . ,(alist-get 'method m)))))))))))
     (delete-file familiar-mcp-http-token-file)   ; created on first use
     (unwind-protect (progn ,@body)
       (ignore-errors (delete-file familiar-mcp-http-token-file)))))

(defun test-mcp-http--auth (&rest more)
  (append (list (cons "authorization" (concat "Bearer " (familiar-mcp-http-token)))) more))

(ert-deftest familiar-mcp-http/answers-by-the-spec ()
  (test-mcp-http--with
   (let ((req "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")
         (note "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"))
     ;; A request: one JSON object.
     (pcase-let ((`(,status ,headers ,body) (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth) req)))
       (should (= status 200))
       (should (equal (cdr (assoc "Content-Type" headers)) "application/json"))
       (should (string-match-p "\"echo\":\"tools/list\"" body)))
     ;; A notification: 202, no body.
     (should (equal (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth) note) '(202 nil "")))
     ;; No stream, no sessions.
     (should (= 405 (car (familiar-mcp-http-respond "GET" "/mcp" (test-mcp-http--auth) ""))))
     (should (= 405 (car (familiar-mcp-http-respond "DELETE" "/mcp" (test-mcp-http--auth) ""))))
     ;; Versions: known pass, unknown 400.
     (should (= 200 (car (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth '("mcp-protocol-version" . "2025-06-18")) req))))
     (should (= 400 (car (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth '("mcp-protocol-version" . "1999-01-01")) req))))
     (should (= 400 (car (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth) "{not json"))))
     (should (= 404 (car (familiar-mcp-http-respond "POST" "/other" (test-mcp-http--auth) req)))))))

(ert-deftest familiar-mcp-http/refuses-strangers ()
  (test-mcp-http--with
   (let ((req "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"))
     (should (= 401 (car (familiar-mcp-http-respond "POST" "/mcp" nil req))))
     (should (= 401 (car (familiar-mcp-http-respond "POST" "/mcp" '(("authorization" . "Bearer wrong")) req))))
     ;; DNS rebinding: a web page's origin, even with the token.
     (should (= 403 (car (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth '("origin" . "https://evil.example")) req))))
     (should (= 200 (car (familiar-mcp-http-respond "POST" "/mcp" (test-mcp-http--auth '("origin" . "http://localhost:3000")) req))))
     ;; The token file is private and stable.
     (should (= #o600 (file-modes familiar-mcp-http-token-file)))
     (should (equal (familiar-mcp-http-token) (familiar-mcp-http-token))))))

(ert-deftest familiar-mcp-http/parses-a-body-that-arrives-in-pieces ()
  (let ((raw "POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Length: 7\r\n\r\n{\"a\":"))
    (should-not (familiar-mcp-http--parse raw))
    (should (equal (familiar-mcp-http--parse (concat raw "1}"))
                   '("POST" "/mcp" (("host" . "x") ("content-length" . "7")) "{\"a\":1}")))
    (should (eq (familiar-mcp-http--parse "garbage\r\n\r\n") :bad))))

(ert-deftest familiar-mcp-http/round-trip-over-a-socket ()
  (test-mcp-http--with
   (let* ((url (familiar-mcp-http-start 0))
          (port (string-to-number (car (last (split-string (string-remove-suffix "/mcp" url) ":")))))
          (out "")
          (body (encode-coding-string "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\",\"params\":{\"q\":\"ü\"}}" 'utf-8))
          (client (make-network-process :name "test-mcp-client" :host "127.0.0.1" :service port
                                        :coding 'binary
                                        :filter (lambda (_ s) (setq out (concat out s))))))
     (unwind-protect
         (progn
           (process-send-string client (format "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n%s"
                                               (familiar-mcp-http-token) (length body) body))
           (with-timeout (5 (error "No answer"))
             (while (not (string-match-p "\r\n\r\n.*}" out))
               (accept-process-output nil 0.05)))
           (should (string-prefix-p "HTTP/1.1 200 OK\r\n" out))
           (should (string-match-p "\"id\":7" out)))
       (delete-process client)
       (familiar-mcp-http-stop)))))

;;; familiar-openai

(when test-familiar-available
  (load (expand-file-name "../lisp/familiar/familiar-openai"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(ert-deftest familiar-openai/messages-become-alternating-turns ()
  (skip-unless test-familiar-available)
  (should (equal (familiar-openai-conversation
                  '(((role . "system") (content . "Be brief."))
                    ((role . "user") (content . "a"))
                    ((role . "user") (content . (((type . "text") (text . "b")))))
                    ((role . "assistant") (content . "c"))
                    ((role . "user") (content . "d"))))
                 '("Be brief." "a\n\nb" "c" "d")))
  ;; Starting with the model: an empty user turn first.
  (should (equal (cdr (familiar-openai-conversation '(((role . "assistant") (content . "hi")))))
                 '("" "hi"))))

(ert-deftest familiar-openai/model-names ()
  (skip-unless test-familiar-available)
  (let ((familiar-models '((fast . claude-haiku-5-5) (smart . claude-sonnet-5-5))))
    (should (equal (familiar-openai--resolve "smart") '(smart)))
    (should (equal (familiar-openai--resolve "emacs-fast") '(fast . t)))
    (should (equal (familiar-openai--resolve "claude-sonnet-5-5") '(smart)))
    (should (equal (familiar-openai--resolve "gpt-4o") (list familiar-openai-default-tier)))
    (should (member "emacs-smart" (familiar-openai-models)))))

(ert-deftest familiar-openai/completion-through-familiar-with-the-tier-asked-for ()
  (skip-unless test-familiar-available)
  (test-mcp-http--with
   (let ((familiar-models '((fast . claude-haiku-5-5) (smart . claude-sonnet-5-5)))
         seen)
     (cl-letf (((symbol-function 'familiar-request)
                (lambda (prompt &rest args)
                  (setq seen (list prompt (plist-get args :system) (familiar--model 'openai)))
                  (funcall (plist-get args :callback) "Hello!" '(:tokens (:input 5 :output 2)))))
               ((symbol-function 'familiar-openai--emacs-context) (lambda () "Buffer: x.org")))
       (pcase (familiar-mcp-http-respond
               "POST" "/v1/chat/completions" (test-mcp-http--auth)
               "{\"model\":\"emacs-smart\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
         (`(:async ,fn)
          (funcall fn (lambda (status _h body)
                        (should (= status 200))
                        (let ((r (json-parse-string body :object-type 'alist)))
                          (should (equal (alist-get 'object r) "chat.completion"))
                          (should (equal (alist-get 'model r) "claude-sonnet-5-5"))
                          (should (equal (alist-get 'content (alist-get 'message (aref (alist-get 'choices r) 0)))
                                         "Hello!"))
                          (should (= 7 (alist-get 'total_tokens (alist-get 'usage r))))))))
         (other (ert-fail (list "not async" other))))
       (should (equal (car seen) '("hi")))
       (should (string-match-p "Buffer: x.org" (nth 1 seen)))
       (should (eq (nth 2 seen) 'claude-sonnet-5-5))
       ;; Without the token: refused before any model is asked.
       (should (= 401 (car (familiar-mcp-http-respond "POST" "/v1/chat/completions" nil "{}"))))
       (should (= 200 (car (familiar-mcp-http-respond "GET" "/v1/models" (test-mcp-http--auth) ""))))))))

(ert-deftest familiar-openai/streams-chunks-then-done-over-a-socket ()
  (skip-unless test-familiar-available)
  (test-mcp-http--with
   (cl-letf (((symbol-function 'familiar-request)
              (lambda (_prompt &rest args)
                (let ((cb (plist-get args :callback)))
                  (run-at-time 0 nil (lambda () (funcall cb "Hal" nil) (funcall cb "lo" nil) (funcall cb t nil)))))))
     (let* ((url (familiar-mcp-http-start 0))
            (port (string-to-number (car (last (split-string (string-remove-suffix "/mcp" url) ":")))))
            (out "")
            (body "{\"model\":\"fast\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
            (client (make-network-process :name "test-openai-client" :host "127.0.0.1" :service port
                                          :coding 'binary
                                          :filter (lambda (_ s) (setq out (concat out s))))))
       (unwind-protect
           (progn
             (process-send-string client (format "POST /v1/chat/completions HTTP/1.1\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n%s"
                                                 (familiar-mcp-http-token) (length body) body))
             (with-timeout (5 (error "No [DONE]: %S" out))
               (while (not (string-match-p "\\[DONE\\]" out)) (accept-process-output nil 0.05)))
             (should (string-match-p "text/event-stream" out))
             (should (string-match-p "\"content\":\"Hal\"" out))
             (should (string-match-p "\"content\":\"lo\"" out))
             (should (string-match-p "\"finish_reason\":\"stop\"" out)))
         (delete-process client)
         (familiar-mcp-http-stop))))))
