;;; test/test-lisp.el --- Batch tests for private lisp/ modules -*- lexical-binding: t; -*-
;;
;; Run: home/doom/test/run.sh   (emacs -Q --batch, Doom not required)
;;
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'server)
(load (expand-file-name "shims" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defconst test-lisp-dir
  (expand-file-name "../lisp/" (file-name-directory (or load-file-name buffer-file-name))))

(load (expand-file-name "+daemon" test-lisp-dir) nil t)
(load (expand-file-name "+vellumory" test-lisp-dir) nil t)


;;; +daemon

(ert-deftest daemon/relaunch-script-waits-restarts-and-restores ()
  (let* ((server-name "my server")
         (script (+daemon--relaunch-script "/tmp/a session/restart")))
    (should (string-match-p (format "kill -0 %d" (emacs-pid)) script))
    (should (string-match-p "--daemon='my server'\\|--daemon=my\\\\ server" script))
    (should (string-match-p " -c -n -e " script))
    (should (string-match-p "doom-load-session" script))
    (should (string-match-p "a\\\\ session/restart" script))))

(defun test-lisp--run-sync (doom-bin)
  "Run `+daemon/sync-and-restart' with DOOM-BIN; return the restart calls."
  (let (calls)
    (cl-letf (((symbol-function 'daemonp) #'always)
              ((symbol-function 'save-some-buffers) #'ignore)
              ((symbol-function 'pop-to-buffer) #'ignore)
              ((symbol-function '+daemon--doom-bin) (lambda () doom-bin))
              ((symbol-function '+daemon--restart) (lambda (s) (push s calls))))
      (+daemon/sync-and-restart)
      (let ((proc (get-process "doom-sync")))
        (while (and proc (process-live-p proc))
          (accept-process-output proc 0.1))
        ;; Let the sentinel run.
        (accept-process-output nil 0.1)))
    calls))

(ert-deftest daemon/failed-sync-does-not-restart ()
  (should-not (test-lisp--run-sync (executable-find "false")))
  (should (get-buffer "*doom sync*")))

(ert-deftest daemon/successful-sync-restarts-with-session ()
  (should (equal (test-lisp--run-sync (executable-find "true"))
                 (list (doom-session-file +daemon-session-name)))))

(ert-deftest daemon/prefix-arg-skips-sync ()
  (let (calls)
    (cl-letf (((symbol-function 'daemonp) #'always)
              ((symbol-function 'save-some-buffers) #'ignore)
              ((symbol-function 'make-process) (lambda (&rest _) (error "Synced")))
              ((symbol-function '+daemon--restart) (lambda (s) (push s calls))))
      (+daemon/sync-and-restart '(4)))
    (should (= 1 (length calls)))))

(ert-deftest daemon/refuses-outside-a-daemon ()
  (cl-letf (((symbol-function 'daemonp) #'ignore))
    (should-error (+daemon/sync-and-restart) :type 'user-error)))


;;; +vellumory

(defmacro test-lisp--with-repo (&rest body)
  "Run BODY with `+vellumory-checkout' bound to a fresh one-commit git repo."
  `(let* ((repo (make-temp-file "vellumory-test" t))
          (+vellumory-checkout repo)
          (default-directory repo))
     (unwind-protect
         (progn
           (dolist (args '(("init" "-q" "-b" "main")
                           ("-c" "user.name=t" "-c" "user.email=t@t"
                            "commit" "-q" "--allow-empty" "-m" "x")))
             (apply #'process-file "git" nil nil nil args))
           ,@body)
       (delete-directory repo t))))

(ert-deftest vellumory/build-info-names-branch-commit-worker ()
  (test-lisp--with-repo
   (should (string-match-p "\\`main@[0-9a-f]\\{7,\\}, worker .+\\'"
                           (+vellumory-build-info)))))

(ert-deftest vellumory/build-info-flags-dirty-checkout ()
  (test-lisp--with-repo
   (write-region "" nil (expand-file-name "new" repo))
   (should (string-match-p "@[0-9a-f]+ (dirty), worker" (+vellumory-build-info)))))

(ert-deftest vellumory/build-info-survives-missing-checkout ()
  (let ((+vellumory-checkout "/nonexistent/vellumory"))
    (should (string-prefix-p "?@?" (+vellumory-build-info)))))

(ert-deftest vellumory/selection-quotes-active-region ()
  (with-temp-buffer
    (insert "alpha beta gamma")
    (transient-mark-mode 1)
    (set-mark 7) (goto-char 11) (activate-mark)
    (let ((buf (current-buffer)))
      (cl-letf (((symbol-function 'org-capture-get)
                 (lambda (key &rest _) (when (eq key :original-buffer) buf))))
        (should (equal (+vellumory-feedback-selection)
                       "#+begin_quote\nbeta\n#+end_quote\n"))))))

(ert-deftest vellumory/no-selection-no-quote ()
  (with-temp-buffer
    (let ((buf (current-buffer)))
      (cl-letf (((symbol-function 'org-capture-get) (lambda (&rest _) buf)))
        (should-not (+vellumory-feedback-selection))))))

(ert-deftest vellumory/capture-template-registered ()
  (require 'org-capture)
  (let ((tpl (assoc "V" org-capture-templates)))
    (should tpl)
    (should (eq (car (nth 3 tpl)) 'file+headline))
    (should (string-match-p "%a" (nth 4 tpl)))))

(provide 'test-lisp)
;;; test-lisp.el ends here
