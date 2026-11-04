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
                ;; The same conversation takes the next question.
                (setq familiar-ask--origin (familiar-ask--capture))
                (should (eq (familiar-ask "And this?") buf))
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
              (with-current-buffer (familiar-ask "next")
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

;;; test-familiar-ask.el ends here
