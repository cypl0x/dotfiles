;;; familiar-ask-test.el --- Tests for familiar-ask and friends -*- lexical-binding: t; -*-
;;
;; No network: `gptel-send' is replaced by a fake that records the buffer it
;; was called in.  Reuses `test-familiar--with' for the ledger.
;;
;;; Code:

(require 'ert)
(unless (fboundp 'test-familiar--with)        ; when run on its own
  (load (expand-file-name "familiar-test" (file-name-directory (or load-file-name buffer-file-name))) nil t))

(when test-familiar-available
  (load (expand-file-name "../familiar-ask"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t)
  (load (expand-file-name "../familiar-rate"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t)
  (load (expand-file-name "../familiar-prompts"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t)
  (load (expand-file-name "../familiar-complete"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t)
  (load (expand-file-name "../familiar-footprint"
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
           ;; Said who wrote it: familiar and the model, not Emacs itself.
           (should (string-match-p "\\`✦ familiar · [^ ]+: It is a \\*test\\*\\.\\'"
                                   (substring-no-properties shown)))
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


(ert-deftest familiar-ask/model-picks-who-answers-the-turn ()
  (skip-unless test-familiar-available)
  (require 'gptel-openai)
  (let* ((gptel--known-backends nil)    ; the backends below register there
         (a (gptel-make-openai "test-a" :models '(m-one m-two) :key "x"))
         (b (gptel-make-openai "test-b" :models '(m-two) :key "x"))
         (gptel-backend b)
         (familiar-backend nil)
         (handed nil)
         (familiar-handoff-targets
          `((agent-shell :available always :send ,(lambda (text) (setq handed text)))
            (claude-code :available ignore :send ignore)
            (clipboard :available always :send ignore))))
    ;; @model[:NAME] comes out of the prompt; bare means "ask me".
    (should (equal (familiar-ask--model-spec "why @model:m-one this") '("why this" . "m-one")))
    (should (equal (familiar-ask--model-spec "@model why") '("why" . t)))
    (should (equal (familiar-ask--model-spec "mail me@model.org") '("mail me@model.org")))
    ;; Names: a full label, a model (the current backend's first), an agent
    ;; that's running; not one that isn't, nor the clipboard.
    (should (equal (familiar-ask--resolve-model "test-a:m-two") (cons a 'm-two)))
    (should (equal (familiar-ask--resolve-model "m-two") (cons b 'm-two)))
    (should (equal (familiar-ask--resolve-model "m-one") (cons a 'm-one)))
    (should (equal (familiar-ask--resolve-model "agent-shell") '(agent . agent-shell)))
    (should-error (familiar-ask--resolve-model "claude-code") :type 'user-error)
    (should-error (familiar-ask--resolve-model "clipboard") :type 'user-error)
    ;; Completion after @model: offers models and agents, with the backend.
    (with-temp-buffer
      (insert "explain @model:m-")
      (let ((capf (familiar-ask--keywords-capf)))
        (should (equal (sort (all-completions "m-" (nth 2 capf)) #'string<) '("m-one" "m-two")))
        (should (string-match-p "test-a" (funcall (plist-get (nthcdr 3 capf) :annotation-function)
                                                  "m-one")))))
    ;; The turn is sent with that model; the conversation keeps its own.
    (test-familiar-ask--asking
     (let (used)
       (cl-letf (((symbol-function 'gptel-send)
                  (lambda (&rest _) (setq used (cons gptel-backend gptel-model)))))
         (let ((buf (familiar-ask "what is this @model:test-a:m-one")))
           (should (equal used (cons a 'm-one)))
           (with-current-buffer buf
             (should-not (eq gptel-model 'm-one))
             (should-not (string-match-p "@model" (buffer-string))))))))
    ;; An agent gets the prompt and the context; no conversation is made.
    (test-familiar-ask--asking
     (familiar-ask "fix it @model:agent-shell")
     (should-not (get-buffer familiar-ask--buffer-name))
     (should (string-prefix-p "fix it\n\n" handed)))))

(defmacro test-familiar-ask--inline (text prompt &rest body)
  "Ask PROMPT about TEXT (point after POINT, region from [ to ] if any),
answered \"one \" \"two\" in chunks; BODY sees the buffer, the request in
`asked'."
  (declare (indent 2))
  `(with-temp-buffer
     (buffer-enable-undo)
     (setq-local transient-mark-mode t)
     (insert ,text)
     (goto-char (point-min))
     (when (search-forward "[" nil t)
       (delete-char -1)
       (push-mark (point) t t)
       (search-forward "]")
       (delete-char -1))
     (unless (mark t)
       (goto-char (point-min))
       (search-forward "POINT")
       (replace-match ""))
     (undo-boundary)
     (let (asked)
       (cl-letf (((symbol-function 'familiar-request)
                  (lambda (request &rest args)
                    (setq asked (list request (plist-get args :system)))
                    (dolist (r '("one " "two" t))
                      (funcall (plist-get args :callback) r nil))))
                 ((symbol-function 'pulse-momentary-highlight-region) #'ignore))
         (familiar-ask ,prompt)
         ,@body))))

(ert-deftest familiar-ask/inline-writes-at-point-and-undoes-at-once ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--inline "Dear POINT,\nbye" "a name @inline"
    (should (equal (buffer-string) "Dear one two,\nbye"))
    (should (string-match-p "Dear ⟦here⟧,\nbye" (car asked)))
    (should (string-match-p "What to write: a name\\'" (car asked)))
    (should (string-match-p "only" (cadr asked)))
    (undo-boundary)
    (primitive-undo 1 (cdr buffer-undo-list))   ; past the boundary
    (should (equal (buffer-string) "Dear ,\nbye"))))

(ert-deftest familiar-ask/inline-goes-after-the-region-replace-into-it ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--inline "a [old] b" "translate @inline"
    (should (equal (buffer-string) "a oldone two b"))
    (should (string-match-p "a ⟦selection⟧old⟦/selection⟧⟦here⟧ b" (car asked))))
  (test-familiar-ask--inline "a [old] b" "translate @replace"
    (should (equal (buffer-string) "a one two b"))
    (should (string-match-p "⟦selection⟧old⟦/selection⟧" (car asked)))
    ;; One undo: the answer out, the old text back.
    (undo-boundary)
    (primitive-undo 1 (cdr buffer-undo-list))
    (should (equal (buffer-string) "a old b")))
  (with-temp-buffer
    (should-error (familiar-ask "x @replace") :type 'user-error)))

(ert-deftest familiar-ask/inline-in-normal-state-opens-a-line ()
  (skip-unless test-familiar-available)
  (dlet ((evil-state 'normal))
    (test-familiar-ask--inline "first POINTline\nlast" "more @inline"
      (should (equal (buffer-string) "first line\none two\nlast"))
      (should (string-match-p "first line\n⟦here⟧\n\nlast" (car asked))))))

(ert-deftest familiar-ask/transient-opens-before-sending-and-sends-its-choices ()
  (skip-unless test-familiar-available)
  ;; @transient: nothing is sent; the transient opens on the prompt, its
  ;; switches set from the prompt's other keywords.
  (let (setup asked)
    (cl-letf (((symbol-function 'transient-setup)
               (lambda (&rest args) (setq setup args)))
              ((symbol-function 'familiar-ask--send) (lambda (&rest _) (error "Sent"))))
      (with-temp-buffer
        (familiar-ask "fix this @inline @transient @model:m-one")))
    (should (eq (car setup) 'familiar-ask-transient))
    (should (equal (car (plist-get (nthcdr 3 setup) :scope)) "fix this"))
    (should (equal (plist-get (nthcdr 3 setup) :value) '("--where=inline" "--model=m-one")))
    (let ((familiar-ask-follow-up t))
      (should (equal (familiar-ask--transient-value '(new) nil) nil))
      (should (equal (familiar-ask--transient-value nil t) '("--follow-up"))))
    ;; Its choices go back in as keywords, read by `familiar-ask' as usual.
    (should (equal (familiar-ask--transient-prompt "fix this" '("--where=echo" "--model=m-one"))
                   "fix this @echo @new @model:m-one"))
    (should (equal (familiar-ask--transient-prompt "fix this" '("--follow-up"))
                   "fix this @follow-up"))
    (cl-letf (((symbol-function 'transient-scope) (lambda (&rest _) (list "fix this" '(:buffer x))))
              ((symbol-function 'familiar-ask) (lambda (&rest args) (setq asked args))))
      (familiar-ask-transient-send '("--where=replace")))
    (should (equal asked '("fix this @replace @new" nil (:buffer x))))))

(ert-deftest familiar-rate/live-rating-shows-after-the-prompt-unless-stale ()
  (skip-unless test-familiar-available)
  (let (asked reply)
    (cl-letf (((symbol-function 'familiar-request)
               (lambda (text &rest args)
                 (setq asked (cons text args))
                 (setq reply (plist-get args :callback))))
              ((symbol-function 'active-minibuffer-window) (lambda () (selected-window)))
              ((symbol-function 'minibufferp) (lambda (&rest _) t))
              ((symbol-function 'minibuffer-contents-no-properties) #'buffer-string))
      (with-temp-buffer
        (set-window-buffer (selected-window) (current-buffer))
        (insert "fix the thing @inline")
        (familiar-rate--live (current-buffer))
        ;; Directives out; a background request, not in the history.
        (should (equal (car asked) "fix the thing"))
        (should (plist-get (cdr asked) :silent))
        ;; The same text isn't asked twice.
        (setq asked nil)
        (familiar-rate--live (current-buffer))
        (should-not asked)
        (funcall reply "```json\n{\"score\": 2, \"tip\": \"Say which thing\"}\n```" nil)
        (should (equal (overlay-get familiar-rate--overlay 'after-string)
                       "   ★★☆☆☆ Say which thing"))
        ;; Typed on before the answer came: it's not shown.
        (familiar-rate--show nil)
        (insert " now")
        (funcall reply "{\"score\": 5, \"tip\": \"\"}" nil)
        (should-not (overlay-get familiar-rate--overlay 'after-string))))))

(ert-deftest familiar-rate/review-shows-only-findings-about-real-prompts ()
  (skip-unless test-familiar-available)
  (let* ((familiar-ask-history '("fix it" "explain this @fast" "fix it" "explain this"))
         (prompts (familiar-rate--collect))
         (answer '(:summary "Short prompts."
                   :patterns ((:prompts (1 2) :issue "Terse" :suggestion "Say more" :template "Fix {what}")
                              (:prompts (1 9) :issue "Invented"))
                   :ratings ((:prompt 1 :score 1 :why "Vague" :better "Fix the failing test")
                             (:prompt 7 :score 1 :why "Not a prompt of yours"))))
         (org (familiar-rate--render answer prompts)))
    ;; Newest first, each once, directives out, counted.
    (should (equal prompts '(("fix it" . 2) ("explain this" . 2))))
    ;; Quotes come from the history, not from the model.
    (should (string-match-p "^: \\[1\\] fix it   (×2)$" org))
    (should (string-match-p "^: \\[2\\] explain this   (×2)$" org))
    (should (string-match-p "Fix {what}" org))
    ;; A pattern citing one real prompt and a rating citing none: dropped.
    (should-not (string-match-p "Invented\\|Not a prompt" org))
    (should (string-match-p "2 findings dropped" org))))

(defmacro test-familiar-prompts--with (&rest body)
  "BODY with a library of one own prompt and two Fabric patterns."
  `(let* ((root (make-temp-file "familiar-prompts" t))
          (familiar-prompts-directory (expand-file-name "mine" root))
          (familiar-prompts-fabric-directory (expand-file-name "fabric" root))
          (familiar-prompts--cache nil))
     (unwind-protect
         (progn
           (make-directory familiar-prompts-directory t)
           (dolist (p '(("summarize" . "# IDENTITY and PURPOSE\n\nYou are a summarizer. More.\n\n# INPUT:\n\nINPUT:")
                        ("improve_writing" . "# IDENTITY and PURPOSE\n\nYou improve writing.\n\nINPUT:")))
             (make-directory (expand-file-name (car p) familiar-prompts-fabric-directory) t)
             (with-temp-file (expand-file-name (concat (car p) "/system.md") familiar-prompts-fabric-directory)
               (insert (cdr p))))
           (with-temp-file (expand-file-name "letter.md" familiar-prompts-directory)
             (insert "Write a letter to {{who}} about: {{input}}"))
           ,@body)
       (delete-directory root t))))

(ert-deftest familiar-prompts/library-yours-and-fabric-with-purposes ()
  (skip-unless test-familiar-available)
  (test-familiar-prompts--with
   (should (equal (mapcar #'car (familiar-prompts)) '("letter" "improve_writing" "summarize")))
   (should (equal (plist-get (cdr (assoc "summarize" (familiar-prompts))) :purpose)
                  "You are a summarizer."))
   (should (string-match-p "★" (familiar-prompts--annotate "letter")))
   ;; {{var}} asked for, {{input}} is what was typed; else it goes after.
   (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Ada")))
     (should (equal (familiar-prompts--fill "Write a letter to {{who}} about: {{input}}" "tea")
                    "Write a letter to Ada about: tea")))
   (should (equal (familiar-prompts--fill "Do X.\nINPUT:\n" "tea") "Do X.\nINPUT:\n\ntea"))
   ;; @p:NAME completes in the prompt.
   (with-temp-buffer
     (insert "please @p:sum")
     (should (equal (all-completions "sum" (nth 2 (familiar-prompts-capf))) '("summarize"))))))

(ert-deftest familiar-prompts/one-applies-several-compose-like-pipes ()
  (skip-unless test-familiar-available)
  (test-familiar-prompts--with
   (let (sent chain)
     (cl-letf (((symbol-function 'familiar-ask--send)
                (lambda (prompt &rest _) (setq sent prompt)))
               ((symbol-function 'familiar-ask--context) (lambda (_) "CONTEXT"))
               ((symbol-function 'familiar-request)
                (lambda (prompt &rest args)
                  (push prompt chain)
                  (funcall (plist-get args :callback) (format "out%d" (length chain)) nil))))
       (with-temp-buffer
         ;; One: its instructions, then what was typed; a heading of its name.
         (familiar-ask "these notes @p:summarize")
         (should (string-prefix-p "these notes → summarize\n#+begin_src markdown\n# IDENTITY" sent))
         (should (string-match-p "INPUT:\n\nthese notes\n#\\+end_src\\'" sent))
         ;; Two: the first runs on what was typed and the context, the
         ;; last gets its output.
         (familiar-ask "fix @p:improve_writing @p:summarize")
         (should (equal (length chain) 1))
         (should (string-match-p "You improve writing.\n\nINPUT:\n\nfix\n\nCONTEXT\\'" (car chain)))
         (should (string-match-p "INPUT:\n\nout1\n#\\+end_src\\'" sent))
         (should (string-prefix-p "fix → improve_writing → summarize\n" sent))
         (should-error (familiar-ask "x @p:nope") :type 'user-error))))))

(ert-deftest familiar-complete/ranked-explained-and-dropped-when-stale ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun f ()\n  (with-cur")
    (save-excursion (insert ")"))
    (let (asked reply shown)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (prompt &rest args) (setq asked (cons prompt args)
                                                   reply (plist-get args :callback))))
                ((symbol-function 'run-at-time) (lambda (_ _ fn) (funcall fn)))
                ((symbol-function 'completion-at-point)
                 (lambda () (setq shown (funcall (car completion-at-point-functions))))))
        (familiar-complete)
        ;; Marked where point is, the word typed named; a background request.
        (should (string-match-p "typed: \"with-cur\"" (car asked)))
        (should (string-match-p "(with-cur⟦here⟧)" (car asked)))
        (should (plist-get (cdr asked) :silent))
        (funcall reply "{\"completions\": [{\"text\": \"with-current-buffer\", \"why\": \"switch buffers\"},
                        {\"text\": \"unrelated\", \"why\": \"x\"},
                        {\"text\": \"with-current-buffer-window\", \"why\": \"and a window\"}]}" nil)
        ;; Only what continues the word, in the model's order, explained.
        (pcase-let ((`(,beg ,end ,table . ,props) shown))
          (should (equal (buffer-substring beg end) "with-cur"))
          (should (equal (all-completions "with-cur" table)
                         '("with-current-buffer" "with-current-buffer-window")))
          (should (eq (alist-get 'display-sort-function (cdr (funcall table "" nil 'metadata))) 'identity))
          (with-current-buffer (funcall (plist-get props :company-doc-buffer) "with-current-buffer")
            (should (string-prefix-p "switch buffers" (buffer-string)))))
        ;; Typed on meanwhile: nothing pops up.
        (setq shown nil)
        (familiar-complete)
        (insert "r")
        (funcall reply "{\"completions\": [{\"text\": \"with-current-buffer\"}]}" nil)
        (should-not shown))))
  ;; Shown as given: no common prefix inserted, nothing filtered out.
  (let ((table (lambda (s p a) (complete-with-action a (list "ab" "abc") s p))))
    (should (equal (familiar-complete--try "a" table nil 1) (cons "a" 1)))
    (should (equal (familiar-complete--all "zz" table nil 2) (quote ("ab" "abc" . 0))))))

(ert-deftest familiar-ask/fresh-conversation-restores-no-gptel-state ()
  ;; gptel complained "Could not activate gptel backend nil" on every ask.
  (skip-unless test-familiar-available)
  (let (restored)
    (cl-letf (((symbol-function 'gptel--restore-state) (lambda () (setq restored t))))
      (with-temp-buffer
        (insert "#+title: new\n")
        (familiar-ask--setup (current-buffer))
        (should-not restored))
      (with-temp-buffer
        (insert ":PROPERTIES:\n:GPTEL_MODEL: claude-sonnet-5-5\n:END:\n#+title: old\n")
        (familiar-ask--setup (current-buffer))
        (should restored)))))

(ert-deftest familiar-footprint/model-changes-recorded-yours-not ()
  (skip-unless test-familiar-available)
  (let ((familiar-footprint--log nil))
    (with-temp-buffer
      (rename-buffer "fp-test" t)
      (insert "hello world")
      ;; Yours: not recorded.
      (should-not familiar-footprint--log)
      ;; A tool's, by name: through the real replace_in_buffer, wrapped.
      (funcall (test-familiar-ask--tool "replace_in_buffer") (buffer-name) "world" "there")
      (should (equal (buffer-string) "hello there"))
      (let ((e (car familiar-footprint--log)))
        (should (equal (plist-get e :actor) "replace_in_buffer"))
        (should (equal (plist-get e :old) "world"))
        (should (equal (plist-get e :new) "there")))
      ;; A streamed answer: chunks join into one change.
      (let ((familiar-footprint--actor "@inline"))
        (goto-char (point-max))
        (insert ", one") (insert " two"))
      (should (= (length familiar-footprint--log) 2))
      (should (equal (plist-get (car familiar-footprint--log) :new) ", one two"))
      ;; Taken back from the ledger while untouched; refused once edited.
      (with-current-buffer (get-buffer-create "*familiar footprint*")
        (familiar-footprint-mode)
        (tabulated-list-print)
        (goto-char (point-min))
        (familiar-footprint-revert))
      (should (equal (buffer-string) "hello there"))
      (with-current-buffer "*familiar footprint*"
        (tabulated-list-print)
        (goto-char (point-min))
        (forward-line 1)
        (with-current-buffer "fp-test"
          (goto-char (point-max)) (insert "!"))
        (should-error (familiar-footprint-revert) :type 'user-error))
      (kill-buffer "*familiar footprint*"))))
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
  (load (expand-file-name "../familiar-mcp-client"
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

(load (expand-file-name "../familiar-mcp-http"
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
  (load (expand-file-name "../familiar-openai"
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

;;; familiar-atuin

(when test-familiar-available
  (load (expand-file-name "../familiar-atuin"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(ert-deftest familiar-atuin/claude-messages-become-turns ()
  (skip-unless test-familiar-available)
  (should (equal (familiar-atuin-conversation
                  '(((role . "user") (content . "list big files"))
                    ((role . "assistant")
                     (content . (((type . "text") (text . "Here:"))
                                 ((type . "tool_use") (name . "suggest_command")
                                  (input . ((command . "du -sh *")))))))
                    ((role . "user") (content . (((type . "tool_result") (content . "ran"))
                                                 ((type . "text") (text . "sorted?")))))))
                 '("list big files" "Here:\n(suggest_command: du -sh *)" "(result: ran)\nsorted?"))))

(defun test-familiar-atuin--chat (fake)
  "Events (NAME . DATA) the server sends for one chat, familiar faked by FAKE."
  (test-mcp-http--with
   (cl-letf (((symbol-function 'familiar-request)
              (lambda (_prompt &rest args)
                (should (plist-get args :tools))
                (let ((cb (plist-get args :callback)))
                  (run-at-time 0 nil (lambda () (funcall fake cb)))))))
     (let* ((url (familiar-mcp-http-start 0))
            (port (string-to-number (car (last (split-string (string-remove-suffix "/mcp" url) ":")))))
            (out "")
            (body "{\"messages\":[{\"role\":\"user\",\"content\":\"list big files\"}],\"context\":{\"shell\":\"zsh\"},\"config\":{},\"invocation_id\":\"x\"}")
            (client (make-network-process :name "test-atuin-client" :host "127.0.0.1" :service port
                                          :coding 'binary
                                          :filter (lambda (_ s) (setq out (concat out s))))))
       (unwind-protect
           (progn
             (process-send-string client (format "POST /api/cli/chat HTTP/1.1\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n%s"
                                                 (familiar-mcp-http-token) (length body) body))
             (with-timeout (5 (error "No done: %S" out))
               (while (not (string-match-p "event: \\(done\\|error\\)" out)) (accept-process-output nil 0.05)))
             (let (events (start 0))
               (while (string-match "event: \\([a-z_]+\\)\ndata: \\(.*\\)\n\n" out start)
                 (push (cons (match-string 1 out) (json-parse-string (match-string 2 out) :object-type 'alist)) events)
                 (setq start (match-end 0)))
               (nreverse events)))
         (delete-process client)
         (familiar-mcp-http-stop))))))

(ert-deftest familiar-atuin/streams-text-and-a-suggested-command ()
  (skip-unless test-familiar-available)
  (let ((events (test-familiar-atuin--chat
                 (lambda (cb)
                   (funcall cb "Biggest first:" nil)
                   ;; As gptel delivers it: the segment ends with the call pending.
                   (funcall cb t '(:stop-reason "tool_use"
                                   :tool-use ((:id "toolu_1" :name "suggest_command"
                                               :args (:command "du -sh * | sort -h" :danger "low")))))))))
    (should (equal (mapcar #'car events) '("text" "tool_call" "done")))
    (should (equal (alist-get 'content (cdr (nth 0 events))) "Biggest first:"))
    (let ((call (cdr (nth 1 events))))
      (should (equal (alist-get 'name call) "suggest_command"))
      (should (equal (alist-get 'command (alist-get 'input call)) "du -sh * | sort -h"))
      (should (equal (alist-get 'danger (alist-get 'input call)) "low")))))

(ert-deftest familiar-atuin/a-plain-answer-ends-with-done ()
  (skip-unless test-familiar-available)
  (let ((events (test-familiar-atuin--chat
                 (lambda (cb) (funcall cb "It lists files." nil) (funcall cb t nil)))))
    (should (equal (mapcar #'car events) '("text" "done")))))

;;; familiar-history

(when test-familiar-available
  (load (expand-file-name "../familiar-history"
                          (file-name-directory (or load-file-name buffer-file-name)))
        nil t)
  ;; Other tests make requests too: they must not write a real history.
  (setq familiar-history-enabled nil))

(defmacro test-history--with (&rest body)
  `(let ((familiar-history-directory (make-temp-file "familiar-history" t))
         (familiar-history-enabled t))
     (unwind-protect (progn ,@body)
       (delete-directory familiar-history-directory t))))

(defun test-history--text ()
  (with-temp-buffer (insert-file-contents (familiar-history-file)) (buffer-string)))

(ert-deftest familiar-history/a-turn-is-an-escaped-org-entry ()
  (skip-unless test-familiar-available)
  (test-history--with
   (familiar-history-record :prompt "What is * this?\nsecond line" :answer "* not a heading\n#+begin_src x"
                            :task 'openai :model 'claude-haiku-5-5 :tokens '(:input 12 :output 3) :cost 0.0001
                            :calls '("suggest_command (:command \"ls\")"))
   (let ((text (test-history--text)))
     (should (string-match-p "^\\* What is \\* this\\?  :openai:$" text))
     (should (string-match-p ":MODEL:    claude-haiku-5-5" text))
     (should (string-match-p ":TOKENS:   12 in, 3 out" text))
     (should (string-match-p "^- suggest_command" text))
     ;; Answer lines can't become headings or blocks.
     (should (string-match-p "^,\\* not a heading$" text))
     (should (string-match-p "^,#\\+begin_src x$" text))
     (should (= #o600 (file-modes (familiar-history-file)))))))

(ert-deftest familiar-history/every-familiar-request-is-recorded ()
  (skip-unless test-familiar-available)
  (test-history--with
   (test-familiar--with "unused"
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (_prompt &rest args)
                  (let ((cb (plist-get args :callback)))
                    (funcall cb "Hel" nil) (funcall cb "lo" nil)
                    (funcall cb t '(:tokens (:input 10 :output 2)
                                    :tool-use ((:name "suggest_command" :args (:command "ls"))))))))
               ((symbol-function 'familiar-cost) (lambda (&rest _) 0.0002)))
       (familiar-request '("first" "reply" "the question") :task 'atuin :stream t :callback #'ignore)
       (let ((text (test-history--text)))
         (should (string-match-p "^\\* the question  :atuin:" text))
         (should (string-match-p ":COST:     0.000200" text))
         (should (string-match-p "^Hello$" text))
         (should (string-match-p "^- suggest_command (:command \"ls\")" text)))))))

(ert-deftest familiar-history/m-ss-turns-link-their-conversation-and-replay ()
  (skip-unless test-familiar-available)
  (test-history--with
   (with-temp-buffer
     (org-mode)
     (setq buffer-file-name (expand-file-name "conv.org" familiar-history-directory))
     (insert "#+title: x\n\n** Explain this  [2026-11-04 Wed 13:00]\nmore lines\n#+begin_context\nctx\n#+end_context\n"
             "#+begin_tool (x)\nr\n#+end_tool\nIt is a test.\n\n** ")
     (setq familiar-ask--last-model 'claude-sonnet-5-5 familiar-ask--last-cost 0.01
           familiar-ask--last-tokens '(:input 1 :output 1))
     (familiar-ask--history)
     (set-buffer-modified-p nil))
   (let ((text (test-history--text)) asked)
     (should (string-match-p "^\\* Explain this  :ask:" text))
     (should (string-match-p ":LINK:     \\[\\[file:.*conv.org::\\*Explain this  \\[2026" text))
     (should (string-match-p "^It is a test\\.$" text))
     (should-not (string-match-p "ctx\\|begin_tool" text))
     ;; Replay asks the same again, fresh.
     (cl-letf (((symbol-function 'familiar-ask) (lambda (p &optional fresh _) (setq asked (list p fresh)))))
       (with-temp-buffer
         (insert text) (org-mode)
         (goto-char (point-min)) (re-search-forward "^\\* Explain")
         (familiar-history-replay)))
     (should (equal asked '("Explain this\nmore lines" t))))))

(ert-deftest familiar-history/search-covers-agent-transcripts ()
  (skip-unless (and test-familiar-available (executable-find "fd")))
  (let* ((root (make-temp-file "roots" t))
         (familiar-history-transcript-roots
          (list (expand-file-name "global/transcripts" root) root))
         (familiar-history--transcripts nil))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "global/transcripts" root) t)
          (make-directory (expand-file-name "proj/.agent-shell/transcripts" root) t)
          (make-directory (expand-file-name "proj/notes/transcripts" root) t) ; not agent-shell's
          (let ((dirs (mapcar #'directory-file-name (familiar-history-transcript-directories))))
            (should (member (expand-file-name "global/transcripts" root) dirs))
            (should (member (expand-file-name "proj/.agent-shell/transcripts" root) dirs))
            (should-not (member (expand-file-name "proj/notes/transcripts" root) dirs))))
      (delete-directory root t))))

;;; familiar-acp

(when test-familiar-available
  (load (expand-file-name "../familiar-acp" (file-name-directory (or load-file-name buffer-file-name))) nil t))

(defmacro test-acp--session (fake &rest body)
  "BODY with an ACP connection `client', `say' to send a message, `lines'
to wait for N lines and get them parsed; familiar-request faked by FAKE."
  (declare (indent 1))
  `(test-mcp-http--with
    (let ((familiar-acp--sessions (make-hash-table :test #'equal)) (out "") cbs
          (familiar-acp-sessions-directory (or (bound-and-true-p test-acp--dir)
                                               (make-temp-file "acp-sessions" t))))
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (prompt &rest args)
                   (push (list prompt (plist-get args :callback)) cbs)
                   (funcall ,fake (plist-get args :callback))))
                ((symbol-function 'gptel-abort)
                 (lambda (_buf) (funcall (cadr (car cbs)) 'abort nil))))
        (let* ((port (familiar-acp-start 0))
               (client (make-network-process :name "test-acp" :host "127.0.0.1" :service port
                                             :coding 'binary
                                             :filter (lambda (_ s) (setq out (concat out s)))))
               (say (lambda (obj) (process-send-string client (concat (json-serialize obj) "\n"))))
               (lines (lambda (n)
                        (with-timeout (5 (error "Only got: %S" out))
                          (while (< (cl-count ?\n out) n) (accept-process-output nil 0.05)))
                        (mapcar (lambda (l) (json-parse-string l :object-type 'alist :array-type 'list))
                                (split-string out "\n" t)))))
          (unwind-protect
              (progn (process-send-string client (format "AUTH %s\n" (familiar-mcp-http-token)))
                     ,@body)
            (delete-process client)
            (familiar-acp-stop)))))))

(ert-deftest familiar-acp/a-session-streams-and-ends-its-turn ()
  (skip-unless test-familiar-available)
  (test-acp--session (lambda (cb) (run-at-time 0 nil (lambda () (funcall cb "Hi" nil) (funcall cb "!" nil) (funcall cb t nil))))
    (funcall say `((jsonrpc . "2.0") (id . 0) (method . "initialize")
                   (params . ((protocolVersion . 1) (clientCapabilities . ,(make-hash-table))))))
    (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new")
                   (params . ((cwd . "/tmp") (mcpServers . [])))))
    (let* ((got (funcall lines 2))
           (init (alist-get 'result (nth 0 got)))
           (sid (alist-get 'sessionId (alist-get 'result (nth 1 got)))))
      (should (= 1 (alist-get 'protocolVersion init)))
      (should (equal (alist-get 'name (alist-get 'agentInfo init)) "familiar"))
      (should (string-prefix-p "sess_" sid))
      (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                     (params . ((sessionId . ,sid)
                                (prompt . [((type . "text") (text . "hello"))
                                           ((type . "resource")
                                            (resource . ((uri . "file:///a.el") (text . "(x)"))))])))))
      (let ((got (funcall lines 5)))
        (should (equal (mapcar (lambda (m) (alist-get 'sessionUpdate (alist-get 'update (alist-get 'params m))))
                               (seq-subseq got 2 4))
                       '("agent_message_chunk" "agent_message_chunk")))
        (should (equal (alist-get 'text (alist-get 'content (alist-get 'update (alist-get 'params (nth 2 got)))))
                       "Hi"))
        (should (equal (alist-get 'stopReason (alist-get 'result (nth 4 got))) "end_turn"))
        (should (string-match-p "hello\n\nFile file:///a.el" (car (car (car cbs)))))
        ;; The next turn carries the conversation.
        (funcall say `((jsonrpc . "2.0") (id . 3) (method . "session/prompt")
                       (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "more"))])))))
        (funcall lines 8)
        (should (equal (car (car cbs)) (list (car (car (cadr cbs))) "Hi!" "more")))))))

(ert-deftest familiar-acp/cancel-answers-cancelled ()
  (skip-unless test-familiar-available)
  (test-acp--session #'ignore              ; never answers by itself
    (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new") (params . ((cwd . "/tmp")))))
    (let ((sid (alist-get 'sessionId (alist-get 'result (car (funcall lines 1))))))
      (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                     (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "long"))])))))
      (sleep-for 0.1)
      (funcall say `((jsonrpc . "2.0") (method . "session/cancel") (params . ((sessionId . ,sid)))))
      (should (equal (alist-get 'stopReason (alist-get 'result (nth 1 (funcall lines 2)))) "cancelled")))))

(ert-deftest familiar-acp/a-wrong-token-is-turned-away ()
  (skip-unless test-familiar-available)
  (test-mcp-http--with
   (let* ((port (familiar-acp-start 0))
          (closed nil)
          (client (make-network-process :name "test-acp-bad" :host "127.0.0.1" :service port
                                        :sentinel (lambda (_ _) (setq closed t)))))
     (unwind-protect
         (progn
           (process-send-string client "AUTH wrong\n")
           (with-timeout (3 (error "Not closed"))
             (while (not closed) (accept-process-output nil 0.05)))
           (should closed))
       (delete-process client)
       (familiar-acp-stop)))))

(ert-deftest familiar-acp/tools-go-through-the-client-and-writes-ask-first ()
  (skip-unless test-familiar-available)
  (let (tools)
    (test-acp--session (lambda (_cb) nil)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (_prompt &rest args) (setq tools (plist-get args :tools)))))
        (funcall say `((jsonrpc . "2.0") (id . 0) (method . "initialize")
                       (params . ((protocolVersion . 1)
                                  (clientCapabilities . ((fs . ((readTextFile . t) (writeTextFile . t)))))))))
        (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new") (params . ((cwd . "/proj")))))
        (let ((sid (alist-get 'sessionId (alist-get 'result (nth 1 (funcall lines 2)))))
              (tool (lambda (name) (gptel-tool-function
                                    (seq-find (lambda (tl) (equal (gptel-tool-name tl) name)) tools))))
              (last-request (lambda (n) (car (last (funcall lines n)))))
              result)
          (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                         (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "x"))])))))
          (with-timeout (3 (error "no tools")) (while (not tools) (accept-process-output nil 0.05)))
          (should (equal (mapcar #'gptel-tool-name tools) '("read_file" "write_file")))
          ;; read_file: shown as a tool call, asked of the client, answered with its content.
          (funcall (funcall tool "read_file") (lambda (r) (setq result r)) "src/a.el" 3)
          (let ((req (funcall last-request 4)))
            (should (equal (alist-get 'method req) "fs/read_text_file"))
            (should (equal (alist-get 'path (alist-get 'params req)) "/proj/src/a.el"))
            (should (= 3 (alist-get 'line (alist-get 'params req))))
            (funcall say `((jsonrpc . "2.0") (id . ,(alist-get 'id req)) (result . ((content . "(defun a ())"))))))
          (with-timeout (3 (error "no read result")) (while (not result) (accept-process-output nil 0.05)))
          (should (equal result "(defun a ())"))
          (should (equal (alist-get 'sessionUpdate (alist-get 'update (alist-get 'params (nth 2 (funcall lines 5)))))
                         "tool_call"))
          ;; write_file: permission first; rejected, nothing written.
          (setq result nil)
          (funcall (funcall tool "write_file") (lambda (r) (setq result r)) "/proj/b.el" "new")
          (let ((req (funcall last-request 7)))
            (should (equal (alist-get 'method req) "session/request_permission"))
            (funcall say `((jsonrpc . "2.0") (id . ,(alist-get 'id req))
                           (result . ((outcome . ((outcome . "selected") (optionId . "reject"))))))))
          (with-timeout (3 (error "no write result")) (while (not result) (accept-process-output nil 0.05)))
          (should (string-match-p "declined" result))
          (should-not (cl-some (lambda (m) (equal (alist-get 'method m) "fs/write_text_file")) (funcall lines 8)))
          ;; Allowed: then the client writes it.
          (setq result nil)
          (funcall (funcall tool "write_file") (lambda (r) (setq result r)) "/proj/b.el" "new")
          (let ((req (funcall last-request 10)))
            (funcall say `((jsonrpc . "2.0") (id . ,(alist-get 'id req))
                           (result . ((outcome . ((outcome . "selected") (optionId . "allow"))))))))
          (let ((req (seq-find (lambda (m) (equal (alist-get 'method m) "fs/write_text_file"))
                               (progn (with-timeout (3 (error "no write request"))
                                        (while (not (string-match-p "fs/write_text_file" out))
                                          (accept-process-output nil 0.05)))
                                      (funcall lines 12)))))
            (should (equal (alist-get 'content (alist-get 'params req)) "new"))
            (funcall say `((jsonrpc . "2.0") (id . ,(alist-get 'id req)) (result . ,(make-hash-table)))))
          (with-timeout (3 (error "no written result")) (while (not result) (accept-process-output nil 0.05)))
          (should (equal result "Wrote /proj/b.el")))))))

(ert-deftest familiar-acp/no-file-capabilities-no-tools ()
  (skip-unless test-familiar-available)
  (let (tools asked)
    (test-acp--session (lambda (_cb) nil)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (_prompt &rest args) (setq asked t tools (plist-get args :tools)))))
        (funcall say '((jsonrpc . "2.0") (id . 0) (method . "initialize") (params . ((protocolVersion . 1)))))
        (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new") (params . ((cwd . "/proj")))))
        (let ((sid (alist-get 'sessionId (alist-get 'result (nth 1 (funcall lines 2))))))
          (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                         (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "x"))])))))
          (with-timeout (3 (error "not asked")) (while (not asked) (accept-process-output nil 0.05)))
          (should-not tools))))))

(ert-deftest familiar-acp/run-command-asks-then-uses-the-client-terminal ()
  (skip-unless test-familiar-available)
  (let (tools)
    (test-acp--session (lambda (_cb) nil)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (_prompt &rest args) (setq tools (plist-get args :tools)))))
        (funcall say '((jsonrpc . "2.0") (id . 0) (method . "initialize")
                       (params . ((protocolVersion . 1) (clientCapabilities . ((terminal . t)))))))
        (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new") (params . ((cwd . "/proj")))))
        (let* ((sid (alist-get 'sessionId (alist-get 'result (nth 1 (funcall lines 2)))))
               (requests (lambda () (seq-filter (lambda (m) (and (alist-get 'method m) (alist-get 'id m)))
                                                (funcall lines 0))))
               (answer (lambda (method result)
                         (with-timeout (3 (error "No %s in %S" method out))
                           (while (not (seq-find (lambda (m) (equal (alist-get 'method m) method)) (funcall requests)))
                             (accept-process-output nil 0.05)))
                         (let ((req (seq-find (lambda (m) (equal (alist-get 'method m) method)) (funcall requests))))
                           (funcall say `((jsonrpc . "2.0") (id . ,(alist-get 'id req)) (result . ,result)))
                           req)))
               result)
          (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                         (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "x"))])))))
          (with-timeout (3 (error "no tools")) (while (not tools) (accept-process-output nil 0.05)))
          (should (equal (mapcar #'gptel-tool-name tools) '("run_command")))
          (funcall (gptel-tool-function (car tools)) (lambda (r) (setq result r)) "make test")
          (funcall answer "session/request_permission" '((outcome . ((outcome . "selected") (optionId . "allow")))))
          (let ((create (funcall answer "terminal/create" '((terminalId . "term_1")))))
            (should (equal (alist-get 'args (alist-get 'params create)) '("-c" "make test")))
            (should (equal (alist-get 'cwd (alist-get 'params create)) "/proj")))
          (funcall answer "terminal/wait_for_exit" '((exitCode . 2)))
          (funcall answer "terminal/output" '((output . "1 failed") (truncated . :false)))
          (with-timeout (3 (error "no result")) (while (not result) (accept-process-output nil 0.05)))
          (should (equal result "Exit code: 2\n1 failed"))
          ;; The terminal was shown in the tool call, and released.
          (should (string-match-p "\"terminalId\":\"term_1\"" out))
          (with-timeout (3 (error "no release")) (while (not (string-match-p "terminal/release" out)) (accept-process-output nil 0.05)))
          ;; Declined: no terminal at all.
          (setq result nil out "")
          (funcall (gptel-tool-function (car tools)) (lambda (r) (setq result r)) "rm -rf x")
          (funcall answer "session/request_permission" '((outcome . ((outcome . "selected") (optionId . "reject")))))
          (with-timeout (3 (error "no result")) (while (not result) (accept-process-output nil 0.05)))
          (should (string-match-p "declined" result))
          (should-not (string-match-p "terminal/create" out)))))))

(defvar test-acp--dir nil "Sessions directory shared by two connections in one test.")

(ert-deftest familiar-acp/a-session-is-loaded-again-on-a-new-connection ()
  (skip-unless test-familiar-available)
  (let* ((test-acp--dir (make-temp-file "acp-sessions" t)) sid prompts)
    (unwind-protect
        (progn
          ;; First connection: one turn, which is kept.
          (test-acp--session (lambda (cb) (run-at-time 0 nil (lambda () (funcall cb "Paris." nil) (funcall cb t nil))))
            (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/new") (params . ((cwd . "/proj")))))
            (setq sid (alist-get 'sessionId (alist-get 'result (car (funcall lines 1)))))
            (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                           (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "Capital of France?"))])))))
            (should (equal "end_turn" (alist-get 'stopReason (alist-get 'result (nth 2 (funcall lines 3)))))))
          (should (file-exists-p (expand-file-name (concat sid ".eld") test-acp--dir)))
          ;; Second connection: loaded, replayed, and it continues from there.
          (test-acp--session (lambda (cb) (run-at-time 0 nil (lambda () (funcall cb "Berlin." nil) (funcall cb t nil))))
            (funcall say `((jsonrpc . "2.0") (id . 1) (method . "session/load")
                           (params . ((sessionId . ,sid) (cwd . "/proj") (mcpServers . [])))))
            (let ((got (funcall lines 3)))
              (should (equal (mapcar (lambda (m) (alist-get 'sessionUpdate (alist-get 'update (alist-get 'params m))))
                                     (seq-take got 2))
                             '("user_message_chunk" "agent_message_chunk")))
              (should (equal (alist-get 'text (alist-get 'content (alist-get 'update (alist-get 'params (nth 1 got)))))
                             "Paris."))
              (should (equal (alist-get 'id (nth 2 got)) 1)))  ; the response, after the replay
            (funcall say `((jsonrpc . "2.0") (id . 2) (method . "session/prompt")
                           (params . ((sessionId . ,sid) (prompt . [((type . "text") (text . "And Germany?"))])))))
            (funcall lines 5)
            (setq prompts (car (car cbs)))
            (should (equal prompts '("Capital of France?" "Paris." "And Germany?"))))
          ;; Unknown sessions are an error.
          (test-acp--session #'ignore
            (funcall say '((jsonrpc . "2.0") (id . 1) (method . "session/load") (params . ((sessionId . "sess_nope")))))
            (should (alist-get 'error (car (funcall lines 1))))))
      (delete-directory test-acp--dir t))))

;;; familiar-a2a

(when test-familiar-available
  (load (expand-file-name "../familiar-a2a" (file-name-directory (or load-file-name buffer-file-name))) nil t))

(defmacro test-a2a--with (fake &rest body)
  "BODY with A2A state fresh and familiar-request faked by FAKE (gets the
prompt turns and the callback)."
  (declare (indent 1))
  `(test-mcp-http--with
    (let ((familiar-a2a--tasks (make-hash-table :test #'equal))
          (familiar-a2a--contexts (make-hash-table :test #'equal))
          (bufs nil))
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (prompt &rest args)
                   (push (cons (current-buffer) (plist-get args :callback)) bufs)
                   (funcall ,fake prompt (plist-get args :callback))))
                ((symbol-function 'gptel-abort)
                 (lambda (buf) (funcall (cdr (assq buf bufs)) 'abort nil))))
        ,@body))))

(defun test-a2a--call (method params &optional headers)
  "Call METHOD over the route handler; the JSON-RPC response, parsed."
  (let ((reply (familiar-mcp-http-respond
                "POST" "/a2a" (append (test-mcp-http--auth) headers)
                (json-serialize `((jsonrpc . "2.0") (id . 7) (method . ,method) (params . ,params)))))
        out)
    (pcase reply
      (`(:async ,fn) (funcall fn (lambda (_s _h body) (setq out body)))
       (with-timeout (3 (error "No answer")) (while (not out) (accept-process-output nil 0.05))))
      (`(,_status ,_h ,body) (setq out body)))
    (json-parse-string out :object-type 'alist :array-type 'list)))

(defun test-a2a--msg (text &optional context)
  `((messageId . "m1") (role . "ROLE_USER") (parts . [((text . ,text))])
    ,@(and context `((contextId . ,context)))))

(ert-deftest familiar-a2a/the-card-is-public-and-names-the-interface ()
  (skip-unless test-familiar-available)
  (test-mcp-http--with
   (familiar-mcp-http-start 0)
   (unwind-protect
       (pcase-let ((`(,status ,_ ,body) (familiar-mcp-http-respond "GET" "/.well-known/agent-card.json" nil "")))
         (should (= status 200))
         (let* ((card (json-parse-string body :object-type 'alist :array-type 'list))
                (iface (car (alist-get 'supportedInterfaces card))))
           (should (equal (alist-get 'name card) "familiar"))
           (should (equal (alist-get 'protocolBinding iface) "JSONRPC"))
           (should (equal (alist-get 'protocolVersion iface) "1.0"))
           (should (string-suffix-p "/a2a" (alist-get 'url iface)))
           (should (alist-get 'skills card))))
     (familiar-mcp-http-stop))
   ;; Everything else still needs the token.
   (should (= 401 (car (familiar-mcp-http-respond "POST" "/a2a" nil "{}"))))))

(ert-deftest familiar-a2a/send-message-answers-with-a-completed-task ()
  (skip-unless test-familiar-available)
  (let (prompts)
    (test-a2a--with (lambda (prompt cb) (push prompt prompts)
                      (run-at-time 0 nil (lambda () (funcall cb "Paris." nil) (funcall cb t nil))))
      (let* ((task (alist-get 'task (alist-get 'result (test-a2a--call "SendMessage" `((message . ,(test-a2a--msg "Capital of France?" "ctx-1")))))))
             (art (car (alist-get 'artifacts task))))
        (should (equal (alist-get 'state (alist-get 'status task)) "TASK_STATE_COMPLETED"))
        (should (equal (alist-get 'text (car (alist-get 'parts art))) "Paris."))
        (should (equal (alist-get 'contextId task) "ctx-1"))
        ;; Same context: the conversation goes on.
        (test-a2a--call "SendMessage" `((message . ,(test-a2a--msg "And Germany?" "ctx-1"))))
        (should (equal (car prompts) '("Capital of France?" "Paris." "And Germany?")))
        ;; GetTask finds it; unknown ids are TaskNotFound.
        (should (equal (alist-get 'id (alist-get 'result (test-a2a--call "GetTask" `((id . ,(alist-get 'id task))))))
                       (alist-get 'id task)))
        (should (= -32001 (alist-get 'code (alist-get 'error (test-a2a--call "GetTask" '((id . "nope")))))))))))

(ert-deftest familiar-a2a/return-immediately-then-get-task ()
  (skip-unless test-familiar-available)
  (let (finish)
    (test-a2a--with (lambda (_prompt cb) (setq finish (lambda () (funcall cb "Done." nil) (funcall cb t nil))))
      (let* ((task (alist-get 'task (alist-get 'result
                                              (test-a2a--call "SendMessage" `((message . ,(test-a2a--msg "long job"))
                                                                              (configuration . ((returnImmediately . t))))))))
             (id (alist-get 'id task)))
        (should (equal (alist-get 'state (alist-get 'status task)) "TASK_STATE_WORKING"))
        (funcall finish)
        (should (equal (alist-get 'state (alist-get 'status (alist-get 'result (test-a2a--call "GetTask" `((id . ,id))))))
                       "TASK_STATE_COMPLETED"))))))

(ert-deftest familiar-a2a/cancel-and-errors ()
  (skip-unless test-familiar-available)
  (test-a2a--with #'ignore
    (let ((id (alist-get 'id (alist-get 'task (alist-get 'result
                                                         (test-a2a--call "SendMessage" `((message . ,(test-a2a--msg "x"))
                                                                                         (configuration . ((returnImmediately . t))))))))))
      (should (equal (alist-get 'state (alist-get 'status (alist-get 'result (test-a2a--call "CancelTask" `((id . ,id))))))
                     "TASK_STATE_CANCELED"))
      (should (= -32002 (alist-get 'code (alist-get 'error (test-a2a--call "CancelTask" `((id . ,id))))))))
    (should (= -32009 (alist-get 'code (alist-get 'error (test-a2a--call "GetTask" '((id . "x")) '(("a2a-version" . "0.2")))))))
    (should (= -32004 (alist-get 'code (alist-get 'error (test-a2a--call "GetExtendedAgentCard" nil)))))))

(ert-deftest familiar-a2a/streams-task-chunks-and-a-final-status ()
  (skip-unless test-familiar-available)
  (test-a2a--with (lambda (_p cb) (run-at-time 0 nil (lambda () (funcall cb "Hel" nil) (funcall cb "lo" nil) (funcall cb t nil))))
    (let* ((url (familiar-mcp-http-start 0))
           (port (string-to-number (car (last (split-string (string-remove-suffix "/mcp" url) ":")))))
           (out "")
           (body (json-serialize `((jsonrpc . "2.0") (id . 3) (method . "SendStreamingMessage")
                                   (params . ((message . ,(test-a2a--msg "hi")))))))
           (client (make-network-process :name "test-a2a" :host "127.0.0.1" :service port :coding 'binary
                                         :filter (lambda (_ s) (setq out (concat out s))))))
      (unwind-protect
          (progn
            (process-send-string client (format "POST /a2a HTTP/1.1\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n%s"
                                                (familiar-mcp-http-token) (length body) body))
            (with-timeout (5 (error "No end: %S" out))
              (while (not (string-match-p "TASK_STATE_COMPLETED" out)) (accept-process-output nil 0.05)))
            (let ((events (mapcar (lambda (d) (alist-get 'result (json-parse-string d :object-type 'alist :array-type 'list)))
                                  (let (ds (start 0))
                                    (while (string-match "^data: \\(.*\\)$" out start)
                                      (push (match-string 1 out) ds) (setq start (match-end 0)))
                                    (nreverse ds)))))
              (should (equal (mapcar (lambda (e) (car (car e))) events)
                             '(task artifactUpdate artifactUpdate statusUpdate)))
              (should (equal (alist-get 'text (car (alist-get 'parts (alist-get 'artifact (alist-get 'artifactUpdate (nth 1 events))))))
                             "Hel"))))
        (delete-process client)
        (familiar-mcp-http-stop)))))

(ert-deftest familiar-a2a/the-client-delegates-over-http ()
  ;; familiar asks familiar: the client reads the card, then SendMessage.
  (skip-unless test-familiar-available)
  (test-a2a--with (lambda (_p cb) (run-at-time 0 nil (lambda () (funcall cb "42." nil) (funcall cb t nil))))
    (let* ((url (familiar-mcp-http-start 0))
           (familiar-a2a-agents `(("self" :url ,(string-remove-suffix "/mcp" url) :token familiar-mcp-http-token)))
           answer)
      (unwind-protect
          (progn
            (familiar-a2a-send "self" "What is six times seven?" (lambda (a) (setq answer a)))
            (with-timeout (5 (error "No answer")) (while (not answer) (accept-process-output nil 0.05)))
            (should (equal answer "42."))
            (should (equal (mapcar #'car (familiar-a2a-keywords)) '("self")))
            (should (equal (mapcar #'gptel-tool-name (familiar-a2a-turn-tools '(self) nil))
                           '("ask_agent_self"))))
        (familiar-mcp-http-stop)))))

(ert-deftest familiar-ask/abandoned-prompts-are-kept-in-the-history ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask-history nil))
    (with-temp-buffer
      (setq-local familiar-ask--prompt-p t)
      (insert "  half a question  ")
      (familiar-ask--keep-prompt-h)
      ;; Sent after all: read-string adds it too, and it stays once.
      (familiar-ask--keep-prompt-h))
    (should (equal familiar-ask-history '("half a question")))
    ;; Other minibuffers are not M-ß's.
    (with-temp-buffer (insert "find-file input") (familiar-ask--keep-prompt-h))
    (should (equal familiar-ask-history '("half a question")))))

(ert-deftest familiar-ask/c-c-c-c-sends-the-follow-up-from-anywhere ()
  (skip-unless test-familiar-available)
  (let (sent)
    (cl-letf (((symbol-function 'gptel-send) (lambda (&rest _) (setq sent (point)))))
      (with-temp-buffer
        (org-mode)
        (insert "** q\nanswer\n\n** and then?\n")
        (goto-char (point-min))
        (familiar-ask-send-follow-up)
        (should (= sent (point-max))))
      ;; Nothing typed yet under the last heading: nothing sent.
      (setq sent nil)
      (with-temp-buffer
        (org-mode)
        (insert "** q\nanswer\n\n** ")
        (goto-char (point-min))
        (should-error (familiar-ask-send-follow-up) :type 'user-error)
        (should-not sent)))))

(ert-deftest familiar-ask/a-typed-follow-up-is-its-own-turn ()
  ;; It has no context block: the history took the turn before it.
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (org-mode)
    (insert "** First  [2026-11-04 Wed 20:00]\n#+begin_context\nctx\n#+end_context\n"
            (propertize "Answer one.\n" 'gptel 'response)
            "\n** \nAnd the follow-up?\n"
            (propertize "#+begin_tool (x)\n" 'gptel '(tool . "id1"))
            "r\n#+end_tool\n"
            (propertize "Answer two.\n" 'gptel 'response)
            "\n** ")
    (let ((turn (familiar-ask--last-turn)))
      (should (equal (plist-get turn :title) ""))
      (should (equal (buffer-substring-no-properties (plist-get turn :heading) (plist-get turn :prompt-end))
                     "** \nAnd the follow-up?\n"))
      (should (string-prefix-p "#+begin_tool"
                               (buffer-substring-no-properties (car (plist-get turn :answer))
                                                               (cdr (plist-get turn :answer))))))
    (let (recorded)
      (cl-letf (((symbol-function 'familiar-history-record) (lambda (&rest args) (setq recorded args))))
        (familiar-ask--history))
      (should (equal (plist-get recorded :prompt) "And the follow-up?"))
      (should (string-match-p "\\`Answer two\\.\\'" (string-trim (plist-get recorded :answer)))))))

(ert-deftest familiar-ask/compose-opens-the-prompt-buffer-about-here ()
  (skip-unless test-familiar-available)
  (let ((familiar-ask-history '("second" "first")) (familiar-ask--draft nil)
        (familiar-ask-prompt-capfs nil))
    (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b))))
      (with-current-buffer (get-buffer-create "notes.org")
        (insert "some text")
        (familiar-ask-compose))
      (with-current-buffer "*familiar-ask prompt*"
        (unwind-protect
            (progn
              (should familiar-ask-edit-mode)
              (should (memq #'familiar-ask--keywords-capf completion-at-point-functions))
              (should (string-match-p "about notes.org" (familiar-ask--edit-header)))
              ;; M-p / M-n go through the history and back to an empty prompt.
              (familiar-ask-edit-previous 1)
              (should (equal (buffer-string) "second"))
              (familiar-ask-edit-previous 1)
              (should (equal (buffer-string) "first"))
              (should-error (familiar-ask-edit-previous 1) :type 'user-error)
              (familiar-ask-edit-next 2)
              (should (equal (buffer-string) ""))
              ;; Discarding keeps the text in the history.
              (insert "a draft")
              (cl-letf (((symbol-function 'quit-window) #'ignore))
                (familiar-ask-edit-discard))
              (should (equal (car familiar-ask-history) "a draft")))
          (kill-buffer)
          (kill-buffer "notes.org"))))))

(ert-deftest familiar-ask/modifiers-are-remembered-for-the-next-prompt ()
  (skip-unless test-familiar-available)
  (should (equal (familiar-ask--modifiers "why @echo is @follow-up x @model:haiku @p:summary @nope @replace")
                 '("@echo" "@follow-up" "@model:haiku")))   ; @replace acts once
  (let ((familiar-ask-modifiers '("@echo" "@fast")) initial)
    (cl-letf (((symbol-function 'read-string) (lambda (_p init &rest _) (setq initial init) "x")))
      (let ((familiar-ask-remember-modifiers t)) (familiar-ask--read))
      (should (equal initial "@echo @fast "))
      (let ((familiar-ask-remember-modifiers nil)) (familiar-ask--read))
      (should-not initial)
      ;; A kept draft (C-c C-k) wins.
      (let ((familiar-ask--draft "draft")) (familiar-ask--read))
      (should (equal initial "draft"))))
  ;; M-1 … C-u C-u: a remembered @model would win over the model picked.
  (let ((familiar-ask-modifiers '("@echo" "@model:haiku")) (familiar-ask-remember-modifiers t) initial)
    (cl-letf (((symbol-function 'read-string) (lambda (_p init &rest _) (setq initial init) "x")))
      (familiar-ask--read "m-deep")
      (should (equal initial "@echo ")))))

(ert-deftest familiar-ask/known-modifiers-are-highlighted ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (insert "explain @echo this @nope and @p:summary")
    (familiar-ask--highlight-modifiers)
    (should (equal (sort (mapcar (lambda (o) (buffer-substring (overlay-start o) (overlay-end o)))
                                 familiar-ask--modifier-overlays)
                         #'string<)
                   '("@echo" "@p:summary")))
    ;; Redone on each change, not piled up.
    (familiar-ask--highlight-modifiers)
    (should (= 2 (length (seq-filter (lambda (o) (overlay-get o 'face))
                                     (overlays-in (point-min) (point-max)))))))
  ;; In the minibuffer: the first @word, right after the prompt, too.
  (with-temp-buffer
    (insert "Ask (m): @echo why")
    (cl-letf (((symbol-function 'minibuffer-prompt-end) (lambda () 10)))
      (familiar-ask--highlight-modifiers))
    (should (equal (mapcar (lambda (o) (buffer-substring (overlay-start o) (overlay-end o)))
                           familiar-ask--modifier-overlays)
                   '("@echo")))))

(ert-deftest familiar-ask/prefix-picks-the-model ()
  (skip-unless test-familiar-available)
  (let ((familiar-models '((fast . m-fast) (smart . m-smart) (deep . m-deep)))
        (familiar-backend 'backend))
    (should (equal (familiar-ask--prefix-model 1) '(backend . m-fast)))
    (should (equal (familiar-ask--prefix-model 3) '(backend . m-deep)))
    (should-not (familiar-ask--prefix-model '(4)))   ; C-u: follow-up, as before
    (should-not (familiar-ask--prefix-model nil))
    (cl-letf (((symbol-function 'familiar-ask--resolve-model) (lambda (spec) (and (eq spec t) 'picked))))
      (should (eq (familiar-ask--prefix-model '(16)) 'picked)))))

(ert-deftest familiar-ask/answer-tables-are-aligned ()
  (skip-unless test-familiar-available)
  (with-temp-buffer
    (org-mode)
    (insert "** q  [2026-11-06 Fri 09:00]\n")
    (insert (propertize "Here:\n| a | bb |\n|---|---|\n| ccc | d |\nDone.\n" 'gptel 'response))
    (insert "\n** ")
    (familiar-ask--align-tables)
    (should (string-search "| a   | bb |\n|-----+----|\n| ccc | d  |\n" (buffer-string)))
    ;; Still the answer: its rows keep gptel's property.
    (goto-char (point-min))
    (search-forward "| ccc")
    (should (eq (get-text-property (point) 'gptel) 'response))
    (should (equal (car (plist-get (familiar-ask--last-turn) :answer))
                   (save-excursion (goto-char (point-min)) (forward-line 1) (point))))))

(ert-deftest familiar-ask/raise-shows-the-conversation-in-a-window ()
  (skip-unless test-familiar-available)
  (test-familiar-ask--asking
   (let ((buf (familiar-ask "q @echo")) switched)
     (cl-letf (((symbol-function 'switch-to-buffer) (lambda (b &rest _) (setq switched b))))
       (familiar-ask-raise))
     (should (eq switched buf))
     (kill-buffer buf)
     (should-error (familiar-ask-raise) :type 'user-error))))

(provide 'familiar-ask-test)
;;; familiar-ask-test.el ends here
