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




(ert-deftest vellumory/latest-release-resolves-annotated-tags ()
  (should (equal (+vellumory-latest-release
                  (concat "a573338\trefs/tags/v0.1.0\n"
                          "7cdddc3\trefs/tags/v0.1.0^{}\n"))
                 '("v0.1.0" . "7cdddc3"))))

(ert-deftest vellumory/latest-release-orders-by-version-not-string ()
  (should (equal (car (+vellumory-latest-release
                       (concat "aaa\trefs/tags/v0.9.0\n"
                               "bbb\trefs/tags/v0.10.0\n"
                               "ccc\trefs/tags/v0.2.1\n"
                               "ddd\trefs/tags/nightly\n")))
                 "v0.10.0")))

(ert-deftest vellumory/latest-release-none ()
  (should-not (+vellumory-latest-release ""))
  (should-not (+vellumory-latest-release "abc\trefs/heads/main\n")))

;;; +workflow

(load (expand-file-name "+workflow" test-lisp-dir) nil t)

(ert-deftest workflow/history-ranks-by-frequency-and-drops-noise ()
  (cl-letf (((symbol-function 'executable-find) (lambda (p) (when (equal p "atuin") "/bin/atuin")))
            ((symbol-function 'process-lines)
             (lambda (&rest _)
               '("0\tnix develop -c just gpui" "0\tcd .." "0\tgit push" "0\tclear"
                 "1\tnix develop -c just broken"
                 "0\tnix develop -c just run-gpui-release ~/vault"
                 "0\tnix develop -c just run-gpui-release ~/vault" "0\t  " "0\tls -la"))))
    (should (equal (+workflow-history "/x")
                   '(("nix develop -c just run-gpui-release ~/vault" . 2)
                     ("nix develop -c just gpui" . 1))))))

(ert-deftest workflow/history-without-atuin-is-empty ()
  (cl-letf (((symbol-function 'executable-find) #'ignore))
    (should-not (+workflow-history "/x"))))

(ert-deftest workflow/ignore-matches-whole-words-only ()
  (should (string-match-p +workflow-history-ignore "git pull x"))
  (should-not (string-match-p +workflow-history-ignore "gitk"))
  (should-not (string-match-p +workflow-history-ignore "just run")))

(ert-deftest workflow/closure-snapshot-replaces-and-copies-path ()
  (let* ((root (file-name-as-directory (make-temp-file "proj" t)))
         (fake (expand-file-name "fake-closure" root))
         (out (expand-file-name (concat (file-name-nondirectory (directory-file-name root))
                                        ".gcl.txt")
                                root))
         (kill-ring nil))
    (unwind-protect
        (progn
          ;; Fake git-closure: writes its --output argument.
          (write-region "#!/bin/sh\necho snapshot > \"$4\"\n" nil fake)
          (set-file-modes fake #o755)
          (write-region "stale" nil out)
          (write-region "stale" nil (string-remove-suffix ".txt" out))
          (cl-letf (((symbol-function '+workflow--root) (lambda () root))
                    (+workflow-closure-program fake))
            (+workflow/closure-snapshot)
            (let ((p (get-process "git-closure")))
              (while (process-live-p p) (accept-process-output p 0.05))
              (accept-process-output nil 0.05)))
          (should (equal (with-temp-buffer (insert-file-contents out) (buffer-string))
                         "snapshot\n"))
          (should-not (file-exists-p (string-remove-suffix ".txt" out)))
          (should (equal (car kill-ring) out)))
      (delete-directory root t))))


(ert-deftest workflow/peer-url-prefers-remote-on-peer-host ()
  (test-lisp--with-repo
   (process-file "git" nil nil nil "remote" "add" "origin"
                 "cypl0x@wolfhard.net:/home/cypl0x/dev/emacs-pdf")
   (should (equal (+workflow--peer-url repo)
                  "cypl0x@wolfhard.net:/home/cypl0x/dev/emacs-pdf"))))

(ert-deftest workflow/peer-url-falls-back-to-pattern ()
  (test-lisp--with-repo
   (process-file "git" nil nil nil "remote" "add" "origin" "git@github.com:x/y")
   (should (equal (+workflow--peer-url repo)
                  (format +workflow-peer-format
                          (file-name-nondirectory (directory-file-name repo)))))))



;;; +perf

(defun test-lisp--generic-seq-union (s1 s2 &optional testfn)
  "The stock algorithm, copied from seq.el, as the oracle."
  (let* ((accum (lambda (acc elt)
                  (if (seq-contains-p acc elt testfn) acc (cons elt acc))))
         (result (seq-reduce accum s2 (seq-reduce accum s1 '()))))
    (nreverse result)))

(load (expand-file-name "+perf" test-lisp-dir) nil t)

(ert-deftest perf/seq-union-matches-stock-results-and-order ()
  (random "perf")
  (dotimes (_ 200)
    (let ((a (cl-loop repeat (random 150) collect (number-to-string (random 60))))
          (b (cl-loop repeat (random 150) collect (number-to-string (random 60)))))
      (should (equal (seq-union a b) (test-lisp--generic-seq-union a b))))))

(ert-deftest perf/seq-union-respects-custom-testfn ()
  (let ((a (number-sequence 1 100)) (b '(1.0 2.0 500.0)))
    (should (equal (seq-union a b #'=) (test-lisp--generic-seq-union a b #'=)))))

(ert-deftest perf/seq-union-is-linear ()
  "The case that froze Emacs: ~80k store entries merged with two dirs."
  (let ((l (mapcar #'number-to-string (number-sequence 1 80000)))
        (t0 (float-time)))
    (should (= (length (seq-union l '("./" "../"))) 80002))
    (should (< (- (float-time) t0) 1.0))))

(ert-deftest perf/nix-store-p ()
  (should (+perf-nix-store-p "/nix/store/abc-etc/hosts"))
  (should (+perf-nix-store-p "/ssh:cypl0x@inari:/nix/store/"))
  (should (+perf-nix-store-p "/ssh:a|sudo:root@a:/nix/store/x"))
  (should-not (+perf-nix-store-p "/ssh:inari:/home/nix/store/"))
  (should-not (+perf-nix-store-p "/etc/hosts"))
  (should-not (+perf-nix-store-p nil)))

(ert-deftest perf/projectile-root-skipped-in-store ()
  (let ((called nil))
    (should-not (+perf-projectile-skip-store-a
                 (lambda (&rest _) (setq called t) "/root/") "/ssh:h:/nix/store/x/"))
    (should-not called)
    (should (equal (+perf-projectile-skip-store-a (lambda (&rest _) "/p/") "/home/u/p/")
                   "/p/"))))



;;; +usage

(load (expand-file-name "+usage" test-lisp-dir) nil t)

(defmacro test-lisp--with-usage (&rest body)
  `(let ((+usage-file (make-temp-file "usage" nil ".eld"))
         (+usage--counts (make-hash-table :test #'eq)))
     (delete-file +usage-file)
     (unwind-protect (progn ,@body)
       (when (file-exists-p +usage-file) (delete-file +usage-file)))))

(defun test-lisp--run-command (cmd keys &optional via-mx)
  (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () keys)))
    (let ((this-command cmd)
          (real-this-command (if via-mx 'execute-extended-command cmd)))
      (+usage--record-h))))

(ert-deftest usage/off-by-default ()
  (should-not +usage-mode))

(ert-deftest usage/counts-commands-by-invocation ()
  (test-lisp--with-usage
   (test-lisp--run-command 'magit-status [32 103 103])
   (test-lisp--run-command 'magit-status [32 103 103])
   (test-lisp--run-command 'magit-status [?\M-x] t)
   (test-lisp--run-command 'self-insert-command [?a])
   (let ((m (+usage--merged)))
     (should (equal (sort (copy-sequence (alist-get 'magit-status m))
                          (lambda (a b) (string< (car a) (car b))))
                    '(("M-x" . 1) ("SPC g g" . 2))))
     (should-not (assq 'self-insert-command m)))))

(ert-deftest usage/save-merges-across-sessions ()
  (test-lisp--with-usage
   (test-lisp--run-command 'find-file [?\C-x ?\C-f])
   (+usage-save)
   (should (zerop (hash-table-count +usage--counts)))
   (test-lisp--run-command 'find-file [?\C-x ?\C-f])
   (test-lisp--run-command 'find-file [32 46])
   (+usage-save)
   (let ((m (+usage--read)))
     (should (equal (alist-get "C-x C-f" (alist-get 'find-file m) nil nil #'equal) 2))
     (should (equal (alist-get "SPC ." (alist-get 'find-file m) nil nil #'equal) 1)))))



;;; +lsp-fallback

(load (expand-file-name "+lsp-fallback" test-lisp-dir) nil t)

(defun test-lisp--connect (contact &optional command)
  "Run the advice with CONTACT; return (CALLED . MESSAGES)."
  (let (called msgs (+lsp-fallback--noticed nil) (this-command command))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
      (+lsp-fallback-connect-a (lambda (&rest _) (setq called t) 'server)
                               '(haskell-ts-mode) 'project 'class contact '("haskell"))
      (+lsp-fallback-connect-a (lambda (&rest _) (setq called t) 'server)
                               '(haskell-ts-mode) 'project 'class contact '("haskell")))
    (cons called msgs)))

(ert-deftest lsp-fallback/missing-server-is-skipped-with-one-notice ()
  (let ((r (test-lisp--connect '("no-such-language-server-xyz" "--lsp"))))
    (should-not (car r))
    (should (= 1 (length (cdr r))))
    (should (string-match-p "no-such-language-server-xyz" (cadr r)))))

(ert-deftest lsp-fallback/installed-server-connects ()
  (should (car (test-lisp--connect (list (executable-find "sh"))))))

(ert-deftest lsp-fallback/explicit-eglot-is-never-intercepted ()
  (should (car (test-lisp--connect '("no-such-language-server-xyz") 'eglot))))

(ert-deftest lsp-fallback/tcp-and-odd-contacts-pass-through ()
  (should-not (+lsp-fallback-missing-program '("localhost" 6008)))
  (should-not (+lsp-fallback-missing-program '(eglot-lsp-server)))
  (should-not (+lsp-fallback-missing-program nil)))

(ert-deftest lsp-fallback/remote-directories-are-left-to-eglot ()
  (let ((default-directory "/ssh:inari:/home/"))
    (cl-letf (((symbol-function 'file-remote-p) (lambda (&rest _) "/ssh:inari:")))
      (should-not (+lsp-fallback-missing-program '("no-such-language-server-xyz"))))))



;;; +monet

(load (expand-file-name "+monet" test-lisp-dir) nil t)

(defvar monet-mode nil)        ; special, as when monet is loaded
(defvar monet--sessions nil)
(cl-defstruct test-lisp--session directory)

(defmacro test-lisp--with-monet (&rest body)
  "BODY with a fake monet: `started' collects (KEY DIR)."
  `(let ((monet--sessions (make-hash-table :test #'equal))
         (monet-mode t)
         (started nil))
     (cl-letf (((symbol-function 'monet--session-directory) #'test-lisp--session-directory)
               ((symbol-function 'monet-start-server-in-directory)
                (lambda (key dir)
                  (push (list key dir) started)
                  (puthash key (make-test-lisp--session :directory dir) monet--sessions))))
       ,@body)))

(ert-deftest monet/one-session-per-project ()
  (test-lisp--with-monet
   (cl-letf (((symbol-function '+monet--root) (lambda () "/home/u/dev/Turm/")))
     (+monet-ensure-session-h)
     (+monet-ensure-session-h))
   (should (equal started '(("Turm" "/home/u/dev/Turm/"))))))

(ert-deftest monet/unique-keys-for-same-named-projects ()
  (test-lisp--with-monet
   (dolist (root '("/a/Turm/" "/b/Turm/"))
     (cl-letf (((symbol-function '+monet--root) (lambda () root)))
       (+monet-ensure-session-h)))
   (should (equal (sort (mapcar #'car started) #'string<) '("Turm" "Turm<2>")))))

(ert-deftest monet/skips-store-home-and-non-projects ()
  (test-lisp--with-monet
   (dolist (root (list "/nix/store/abc-x/" (expand-file-name "~") nil))
     (cl-letf (((symbol-function '+monet--root) (lambda () root)))
       (+monet-ensure-session-h)))
   (should-not started)))

(ert-deftest monet/nothing-without-monet-mode ()
  (test-lisp--with-monet
   (let ((monet-mode nil))
     (cl-letf (((symbol-function '+monet--root) (lambda () "/home/u/dev/x/")))
       (+monet-ensure-session-h)))
   (should-not started)))


(ert-deftest monet/token-check ()
  (let ((h "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Claude-Code-Ide-Authorization: abc-123\r\nUpgrade: websocket\r\n\r\n"))
    (should (+monet-token-ok-p h "abc-123"))
    (should (+monet-token-ok-p (downcase h) "abc-123"))
    (should-not (+monet-token-ok-p h "abc-12"))   ; no prefix match
    (should-not (+monet-token-ok-p h "wrong"))
    (should-not (+monet-token-ok-p "GET / HTTP/1.1\r\n\r\n" "abc-123"))
    (should-not (+monet-token-ok-p nil "abc-123"))))

(cl-defstruct test-lisp--msession directory auth-token)

(ert-deftest monet/refused-connection-keeps-session ()
  (let ((+monet--refused (make-hash-table :test #'eq :weakness 'key))
        (+monet-auto-start-mode nil)
        (opened nil) (closed nil) (ws (list 'ws)))
    (cl-letf (((symbol-function 'monet--session-auth-token) #'test-lisp--msession-auth-token)
              ((symbol-function 'monet--session-directory) #'test-lisp--msession-directory)
              ((symbol-function 'websocket-close) #'ignore))
      (let ((s (make-test-lisp--msession :directory "/p/" :auth-token "tok")))
        (let ((+monet--handshake "x-claude-code-ide-authorization: nope\r\n"))
          (+monet--check-token-a (lambda (&rest _) (setq opened t)) s ws))
        (should-not opened)
        (+monet--on-close-a (lambda (&rest _) (setq closed t)) s ws)
        (should-not closed)                 ; session survives the impostor
        (let ((+monet--handshake "x-claude-code-ide-authorization: tok\r\n"))
          (+monet--check-token-a (lambda (&rest _) (setq opened t)) s ws))
        (should opened)
        (+monet--on-close-a (lambda (&rest _) (setq closed t)) s ws)
        (should closed)))))                  ; a real close goes through

(ert-deftest monet/remote-buffers-have-no-root ()
  (with-temp-buffer
    (setq buffer-file-name "/ssh:inari:/home/x/f.el"
          default-directory "/ssh:inari:/home/x/")
    (cl-letf (((symbol-function 'file-remote-p) (lambda (&rest _) "/ssh:inari:"))
              ((symbol-function 'doom-project-root) (lambda (&rest _) "/never/")))
      (should-not (+monet--root)))
    (setq buffer-file-name nil)))



;;; +persist (booted against a temporary cache dir, never the real one)

(defvar doom-cache-dir)
(let ((doom-cache-dir (file-name-as-directory (make-temp-file "persist-cache" t))))
  (load (expand-file-name "+persist" test-lisp-dir) nil t))

(defmacro test-lisp--persist-buffer (name mode content &rest body)
  "Run BODY with `buf', a buffer NAME in MODE holding CONTENT."
  `(let ((buf (generate-new-buffer ,name)))
     (unwind-protect
         (progn (with-current-buffer buf (funcall ,mode)
                  (let ((inhibit-read-only t)) (insert ,content)))
                ,@body)
       (let ((kill-buffer-hook nil)) (kill-buffer buf)))))

(ert-deftest persist/keeps-the-users-own-text ()
  (dolist (case '(("*new*" fundamental-mode) ("*new*<3>" text-mode)
                  ("*scratch*" lisp-interaction-mode) ("my notes" org-mode)))
    (test-lisp--persist-buffer (car case) (cadr case) "x"
      (should (+persist/--should-persist-p buf)))))

(ert-deftest persist/skips-generated-buffers ()
  (dolist (case '(("*Brave: doom*" org-mode) ("*tramp/ssh localhost*" fundamental-mode)
                  ("*vellumory-update*" fundamental-mode) ("CAPTURE-todo.org" org-mode)
                  ("acp-client-stderr(x)" fundamental-mode) ("dev" dired-mode)
                  ("*new*" special-mode)))
    (test-lisp--persist-buffer (car case) (cadr case) "x"
      (should-not (+persist/--should-persist-p buf)))))

(ert-deftest persist/skips-read-only-and-empty ()
  (test-lisp--persist-buffer "notes" 'text-mode "x"
    (with-current-buffer buf (setq buffer-read-only t))
    (should-not (+persist/--should-persist-p buf)))
  (test-lisp--persist-buffer "notes" 'text-mode ""
    (should-not (+persist/--should-persist-p buf))))

(ert-deftest persist/killing-a-buffer-forgets-it ()
  (add-hook 'kill-buffer-hook #'+persist/--forget-killed-h)
  (let ((buf (generate-new-buffer "*new*")))
    (with-current-buffer buf (insert "keep me"))
    (+persist/save-buffer buf)
    (let ((file (+persist/--file-for-buffer (buffer-name buf))))
      (should (file-exists-p file))
      (kill-buffer buf)
      (should-not (file-exists-p file)))))


(defun test-lisp--write-persisted (name mode content)
  (let ((buf (generate-new-buffer name)))
    (with-current-buffer buf (funcall mode) (let ((inhibit-read-only t)) (insert content)))
    ;; Write the file the way save does, but for any buffer (incl. junk).
    (with-temp-file (+persist/--file-for-buffer name)
      (insert (format "(setq +persist/--name %S)\n(setq +persist/--mode '%s)\n(setq +persist/--content %S)\n"
                      name mode content)))
    (let ((kill-buffer-hook nil)) (kill-buffer buf))))

(ert-deftest persist/restore-restores-own-text-and-skips-junk ()
  (let ((+persist/directory (file-name-as-directory (make-temp-file "persist" t))))
    (test-lisp--write-persisted "*new*<7>" 'text-mode "my thoughts")
    (test-lisp--write-persisted "*Brave: x*" 'org-mode "results")
    (unwind-protect
        (progn
          (+persist/restore-all)
          (should (equal (with-current-buffer "*new*<7>" (buffer-string)) "my thoughts"))
          (should-not (get-buffer "*Brave: x*"))
          ;; The loaded values stay dynamic, not leaked into globals.
          (should-not +persist/--name))
      (when (get-buffer "*new*<7>") (let ((kill-buffer-hook nil)) (kill-buffer "*new*<7>")))
      (delete-directory +persist/directory t))))

(ert-deftest persist/prune-moves-junk-keeps-own-text ()
  (let ((+persist/directory (file-name-as-directory (make-temp-file "persist" t))))
    (test-lisp--write-persisted "*new*" 'fundamental-mode "keep")
    (test-lisp--write-persisted "*tramp/ssh localhost*" 'fundamental-mode "log")
    (test-lisp--write-persisted "dev" 'dired-mode "listing")
    (unwind-protect
        (progn
          (should (= 2 (+persist/prune)))
          (should (equal (mapcar #'file-name-nondirectory
                                 (directory-files +persist/directory nil "\\.el\\'"))
                         '("_new_.el")))
          (should (= 2 (length (directory-files
                                (car (file-expand-wildcards
                                      (concat (directory-file-name +persist/directory) ".pruned-*")))
                                nil "\\.el\\'")))))
      (delete-directory +persist/directory t)
      (dolist (d (file-expand-wildcards (concat (directory-file-name +persist/directory) ".pruned-*")))
        (delete-directory d t)))))


(ert-deftest perf/eldoc-command-completions-same-set-as-stock ()
  "The one-pass version registers exactly what the stock function does."
  (require 'eldoc)
  (let ((names '("forward-" "backward-" "next-" "scroll-" "newline" "delete-char"
                 "move-" "goto-" "self-insert-command"))
        (collect (lambda () (let (r) (mapatoms (lambda (s) (push (symbol-name s) r))
                                               eldoc-message-commands)
                              (sort r #'string<)))))
    (let* ((eldoc-message-commands (obarray-make))
           (stock (progn (advice-remove 'eldoc-add-command-completions
                                        #'+perf-eldoc-add-command-completions-a)
                         (apply #'eldoc-add-command-completions names)
                         (funcall collect)))
           (eldoc-message-commands (obarray-make))
           (fast (progn (advice-add 'eldoc-add-command-completions :around
                                    #'+perf-eldoc-add-command-completions-a)
                        (apply #'eldoc-add-command-completions names)
                        (funcall collect))))
      (should (> (length stock) 50))
      (should (equal stock fast)))))

(provide 'test-lisp)
;;; test-lisp.el ends here
