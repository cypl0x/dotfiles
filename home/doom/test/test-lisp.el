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


;;; +tldr

(load (expand-file-name "+tldr" test-lisp-dir) nil t)

(defmacro test-lisp--with-tldr (&rest body)
  "BODY with a temp tldr cache (tar in linux and common, git in common)
and a temp exec-path where bin/tar links to store/tar."
  `(let* ((root (make-temp-file "tldr" t))
          (+tldr-pages-dir (file-name-as-directory (expand-file-name "pages" root)))
          (bin (expand-file-name "bin" root))
          (store (expand-file-name "store" root))
          (exec-path (list bin store)))
     (unwind-protect
         (progn
           (dolist (d '("linux" "common")) (make-directory (expand-file-name d +tldr-pages-dir) t))
           (with-temp-file (expand-file-name "linux/tar.md" +tldr-pages-dir)
             (insert "# tar\n\n> Linux tar.\n\n- Create:\n\n`tar cf {{a.tar}} {{file}}`\n"))
           (with-temp-file (expand-file-name "common/tar.md" +tldr-pages-dir) (insert "# tar\n"))
           (with-temp-file (expand-file-name "common/git.md" +tldr-pages-dir) (insert "# git\n"))
           (make-directory bin) (make-directory store)
           (with-temp-file (expand-file-name "tar" store) (insert "#!/bin/sh\n"))
           (set-file-modes (expand-file-name "tar" store) #o755)
           (make-symbolic-link (expand-file-name "tar" store) (expand-file-name "tar" bin))
           ,@body)
       (delete-directory root t))))

(ert-deftest tldr/linux-page-wins-and-names-are-unique ()
  (test-lisp--with-tldr
   (should (string-suffix-p "linux/tar.md" (+tldr-page-file "tar")))
   (should (string-suffix-p "common/git.md" (+tldr-page-file "git")))
   (should-not (+tldr-page-file "nope"))
   (should (equal (sort (+tldr-commands) #'string<) '("git" "tar")))))

(ert-deftest tldr/which-lists-every-match-with-its-target ()
  (test-lisp--with-tldr
   (let ((hits (+tldr-which "tar")))
     (should (= 2 (length hits)))
     (should (string-suffix-p "bin/tar" (car (car hits))))
     (should (string-suffix-p "store/tar" (cdr (car hits))))
     (should-not (+tldr-which "git")))))

(ert-deftest tldr/lookup-shows-which-and-copies-examples ()
  (test-lisp--with-tldr
   (cl-letf (((symbol-function 'pop-to-buffer) #'set-buffer))
     (+tldr/lookup "tar"))
   (unwind-protect
       (with-current-buffer "*tldr: tar*"
         (should (string-match-p "y/RET: copy example" (buffer-string)))
         (should (string-match-p "which: .*bin/tar\n    → .*store/tar" (buffer-string)))
         (should (string-match-p "Linux tar" (buffer-string)))
         ;; Point starts on the first example.
         (should (equal (+tldr-example-at-point) "tar cf {{a.tar}} {{file}}"))
         (let ((kill-ring nil)) (+tldr/copy-example) (should (equal (car kill-ring) "tar cf {{a.tar}} {{file}}"))))
     (kill-buffer "*tldr: tar*"))))

(ert-deftest tldr/missing-page-says-so-without-updating ()
  (test-lisp--with-tldr
   (cl-letf (((symbol-function 'pop-to-buffer) #'set-buffer))
     (+tldr/lookup "git"))
   (unwind-protect
       (with-current-buffer "*tldr: git*"
         (should (string-match-p "not on PATH" (buffer-string))))
     (kill-buffer "*tldr: git*"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'set-buffer))
     (+tldr/lookup "nope"))
   (unwind-protect
       (with-current-buffer "*tldr: nope*"
         (should (string-match-p "No tldr page for nope" (buffer-string))))
     (kill-buffer "*tldr: nope*"))))

;;; +proced

(load (expand-file-name "+proced" test-lisp-dir) nil t)
(require 'proced)

(ert-deftest proced/defaults-show-everyone-with-command-lines ()
  (should (eq (default-value 'proced-filter) 'all))
  (should (eq (default-value 'proced-format) 'medium))
  (should (eq (default-value 'proced-auto-update-flag) 'visible)))

(ert-deftest proced/grep-narrows-to-matching-command-lines ()
  (let ((proc (make-process :name "claude-proced-probe" :noquery t
                            :command '("sleep" "31.4159"))))
    (unwind-protect
        (with-temp-buffer
          (proced-mode)
          (proced-update t t)
          (let ((all (count-lines (point-min) (point-max))))
            (+proced/grep "31\\.4159")
            (should (string-match-p "sleep 31\\.4159" (buffer-string)))
            (should (< (count-lines (point-min) (point-max)) all))
            (+proced/grep "")
            (should (eq proced-filter 'all))))
      (delete-process proc))))
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


(ert-deftest perf/freeze-gap ()
  (let ((+perf-freeze-threshold 20))
    (should-not (+perf-freeze-gap 100.0 nil))         ; first tick
    (should-not (+perf-freeze-gap 102.1 100.0))       ; normal 2 s period
    (should-not (+perf-freeze-gap 121.0 100.0))       ; 19 s late: below threshold
    (should (= 28.0 (+perf-freeze-gap 130.0 100.0)))))


(ert-deftest perf/freeze-context-names-commands-processes-and-echo ()
  (let ((+perf--freeze-commands (make-ring 20))
        (proc (make-process :name "claude-freeze-probe" :command '("sleep" "5")
                            :noquery t)))
    (unwind-protect
        (progn
          (dolist (cmd '(find-file magit-status))
            (let ((this-command cmd)) (+perf--freeze-note-command-h)))
          (cl-letf (((symbol-function 'current-message) (lambda () "Contacting host…")))
            (let ((text (+perf-freeze-context 42.0)))
              (should (string-match-p "Frozen for 42 s" text))
              ;; Newest first.
              (should (string-match-p "magit-status\n.*find-file" text))
              (should (string-match-p "claude-freeze-probe \\[run\\] sleep 5" text))
              (should (string-match-p "Echo area: Contacting host…" text)))))
      (delete-process proc))))

(ert-deftest perf/freeze-recorder-ignores-suspend ()
  (let* ((dir (make-temp-file "freezes" t))
         (counter (make-temp-file "suspends" nil nil "3\n"))
         (+perf-freeze-dir (file-name-as-directory dir))
         (+perf-suspend-count-file counter)
         (+perf--suspend-count nil)
         (+perf--freeze-last nil)
         (+perf--freeze-ticks 1)
         (inhibit-message t))
    (cl-letf (((symbol-function 'executable-find) #'ignore)
              ((symbol-function 'profiler-cpu-running-p) (lambda () t))
              ((symbol-function 'profiler-cpu-log) #'ignore))
      (unwind-protect
          (progn
            (+perf--freeze-tick)                        ; first tick
            ;; 30 s later, the laptop slept in between.
            (setq +perf--freeze-last (- (float-time) 30))
            (with-temp-file counter (insert "4\n"))
            (+perf--freeze-tick)
            (should-not (directory-files dir nil "\\.txt\\'"))
            ;; 30 s later, no suspend: a real freeze.
            (setq +perf--freeze-last (- (float-time) 30))
            (+perf--freeze-tick)
            (should (= 1 (length (directory-files dir nil "\\.txt\\'")))))
        (delete-directory dir t)
        (delete-file counter)))))

(ert-deftest perf/freeze-recorder-turns-off-when-the-profile-cant-be-read ()
  ;; Emacs 32.0.50: once exporting the CPU log fails, it fails every time.
  (let ((+perf-freeze-recorder-mode t) stopped msg)
    (cl-letf (((symbol-function 'profiler-cpu-log) (lambda () (error "Stack overflow in equal")))
              ((symbol-function 'profiler-cpu-stop) (lambda () (setq stopped t)))
              ((symbol-function '+perf-freeze-recorder-mode)
               (lambda (arg) (setq +perf-freeze-recorder-mode (> arg 0))))
              ((symbol-function 'message) (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
      (should-not (+perf--cpu-log))
      (should-not +perf-freeze-recorder-mode)
      (should stopped)
      (should (string-match-p "Freeze recorder off.*Stack overflow in equal" msg)))))
(ert-deftest perf/freeze-recorder-off-in-batch ()
  (should-not +perf-freeze-recorder-mode))

(defvar pulsar-pulse-functions)
(defvar pulsar-pulse-region-functions)

(ert-deftest perf/pulsar-aliases-resolved-only-when-something-changed ()
  (let ((+perf--pulsar-resolved nil)
        (pulsar-pulse-functions (list 'a))
        (pulsar-pulse-region-functions (list 'b))
        (load-history (list '("x")))
        (runs 0))
    (cl-flet ((resolve () (+perf-pulsar-resolve-once-a (lambda () (cl-incf runs)))))
      (resolve) (resolve)
      (should (= runs 1))
      (push '("y") load-history)          ; new code loaded
      (resolve)
      (should (= runs 2))
      (setq pulsar-pulse-functions (list 'a 'c)) ; user replaced the list
      (resolve) (resolve)
      (should (= runs 3)))))


(ert-deftest perf/savehist-drops-huge-and-secret-kills ()
  (let* ((key (concat "sk-ant-" "api03-" (make-string 40 ?x)))
         (gh (concat "ghp_" (make-string 36 ?a)))
         (kills (list "normal text" (make-string 70000 ?y)
                      (concat "export KEY=" key) gh "sk-ant- mentioned in prose"
                      "-----BEGIN OPENSSH PRIVATE KEY-----\nabc")))
    (should (equal (+perf-persistable-kills kills)
                   '("normal text" "sk-ant- mentioned in prose")))))

(require 'savehist)

(ert-deftest perf/savehist-filter-leaves-live-kill-ring-alone ()
  (let ((kill-ring (list "keep" (make-string 70000 ?z)))
        seen)
    (+perf-savehist-filter-a (lambda () (setq seen (copy-sequence kill-ring))))
    (should (equal seen '("keep")))
    (should (= 2 (length kill-ring)))))


(ert-deftest perf/savehist-filters-secrets-in-every-history ()
  (defvar claude-test-history nil)
  (let* ((key (concat "sk-ant-" "usr-" (make-string 40 ?k)))
         (savehist-minibuffer-history-variables '(claude-test-history))
         (savehist-additional-variables '(register-alist))
         (claude-test-history (list "(setq x 1)" (format "(setq k %S)" key)))
         (register-alist (list (cons ?a "plain") (cons ?k key)))
         (kill-ring nil)
         seen)
    (+perf-savehist-filter-a
     (lambda () (setq seen (list claude-test-history register-alist))))
    (should (equal seen '(("(setq x 1)") ((?a . "plain")))))
    ;; Live values untouched.
    (should (= 2 (length claude-test-history)))
    (should (= 2 (length register-alist)))))

(ert-deftest perf/savehist-filter-keeps-variable-list-intact ()
  ;; delete-dups on (append ... savehist-additional-variables) once dropped
  ;; kill-ring from the live list, so savehist stopped writing it.
  (let* ((savehist-minibuffer-history-variables '(kill-ring))
         (savehist-additional-variables (list 'kill-ring '(search-ring . 10)))
         (kill-ring (list "keep"))
         (search-ring nil))
    (+perf-savehist-filter-a #'ignore)
    (should (equal savehist-additional-variables '(kill-ring (search-ring . 10))))))

(provide 'test-lisp)
;;; test-lisp.el ends here

;;; +screenshot

(load (expand-file-name "../lisp/+screenshot" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(ert-deftest screenshot/files-newest-first ()
  (let* ((+screenshot-dir (file-name-as-directory (make-temp-file "shots" t)))
         (old (expand-file-name "b-old.png" +screenshot-dir))
         (new (expand-file-name "a-new.png" +screenshot-dir)))
    (unwind-protect
        (progn
          (write-region "" nil old) (write-region "" nil new)
          (write-region "" nil (expand-file-name "notes.txt" +screenshot-dir))
          (set-file-times old (time-subtract nil 3600))
          ;; By time, not by name; images only.
          (should (equal (+screenshot-files) (list new old))))
      (delete-directory +screenshot-dir t))))

(ert-deftest screenshot/insert-file-per-mode ()
  (let ((file (expand-file-name "~/Pictures/Screenshots/x.png")))
    (with-temp-buffer
      (+screenshot-insert-file file)
      (should (equal (buffer-string) "~/Pictures/Screenshots/x.png")))
    (with-temp-buffer
      (org-mode)
      (+screenshot-insert-file file)
      (should (equal (buffer-string) "[[file:~/Pictures/Screenshots/x.png]]")))))

;;; +format

(load (expand-file-name "../lisp/+format" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(ert-deftest diagnostics/format-wraps-and-labels ()
  (load (expand-file-name "+diagnostics" test-lisp-dir) nil t)
  (cl-letf (((symbol-function 'flycheck-error-message) (lambda (e) (car e)))
            ((symbol-function 'flycheck-error-level) (lambda (e) (cadr e)))
            ((symbol-function 'flycheck-error-checker) (lambda (_) '+org-lint))
            ((symbol-function 'flycheck-error-id) (lambda (_) "blank-lines")))
    (let ((text (+diagnostics--format
                 (list (list (concat "No blank line before this heading, and the text goes on for "
                                     "quite a while so that it has to wrap somewhere sensible")
                             'warning)
                       (list "Second" 'error))
                 40)))
      (should (string-prefix-p "● No blank line" text))
      ;; Wrapped under the text, not under the mark.
      (should (string-match-p "\n  [a-z]" text))
      (should (cl-every (lambda (l) (<= (length l) 42)) (split-string text "\n")))
      (should (string-match-p "\\+org-lint · blank-lines" text))
      (should (string-match-p "\n● Second" text)))))

(ert-deftest transient/resume-reopens-what-closed-last ()
  (load (expand-file-name "+transient" test-lisp-dir) nil t)
  (let ((+transient--ring nil) (+minibuffer--ring '((:command x))) (+minibuffer--closed-at 100.0)
        (opened nil) (mini nil))
    (dlet ((transient--prefix 'stub))
      (cl-letf (((symbol-function 'eieio-oref) (lambda (_o _s) nil)))
        (+transient--record-a 'magit-log)
        (+transient--record-a 'well-formed-menu)
        (+transient--record-a 'magit-log)))
    (should (equal (mapcar (lambda (e) (plist-get e :prefix)) +transient--ring) '(magit-log well-formed-menu)))
    (cl-letf (((symbol-function 'call-interactively) (lambda (c &rest _) (setq opened c)))
              ((symbol-function '+minibuffer/resume) (lambda () (setq mini t))))
      ;; The menu opened after the minibuffer closed: the menu comes back.
      (+resume/last)
      (should (eq opened 'magit-log))
      ;; A minibuffer closed since: that comes back.
      (setq +minibuffer--closed-at (+ (float-time) 10))
      (+resume/last)
      (should mini))))

(ert-deftest completion/next-word-after-a-space ()
  (with-temp-buffer
    (text-mode)
    (insert "The parser reads tokens. The parser builds trees. The parser reads input. The parser ")
    (cl-letf (((symbol-function '+completion-context) (lambda () 'prose)))
      (let ((r (+completion-next-word-capf)))
        (should r)
        (should (= (nth 0 r) (nth 1 r) (point)))
        (should (equal (all-completions "" (nth 2 r)) '("reads" "builds")))
        (should (string-match-p "×2" (funcall (plist-get (nthcdr 3 r) :annotation-function) "reads"))))
      ;; Mid-word it leaves the job to the word completion.
      (insert "re")
      (should-not (+completion-next-word-capf)))))

(ert-deftest completion/paths-by-their-shape ()
  (let ((dir (make-temp-file "pathcomp" t)))
    (make-directory (expand-file-name "vault" dir))
    (dolist (case '("See =%s/va" "See ~/x %s/va" "[[file:%s/va" "Run %s/va"))
      (with-temp-buffer
        (insert (format case dir))
        (let ((r (+completion-path-capf)))
          (should r)
          (should (equal (all-completions (buffer-substring (nth 0 r) (nth 1 r)) (nth 2 r)) '("vault/"))))))
    (with-temp-buffer
      (insert "Plain words va")
      (should-not (+completion-path-capf)))
    (delete-directory dir t)))

(ert-deftest org-links/state-and-description ()
  (load (expand-file-name "+org-links" test-lisp-dir) nil t)
  (let ((dir (make-temp-file "links" t)))
    (clrhash +org-links--exists)
    (should (eq (+org-links--exists-p dir) 'dir))
    (should (eq (+org-links--exists-p (expand-file-name "x.org" dir)) nil))
    (should (string-match-p "doesn't exist" (+org-links--describe "file" "~/nope.pdf" 'missing)))
    (should (null (+org-links--local-file "/ssh:host:/etc/hosts")))
    (should (equal (+org-links--local-file "/tmp/a.org::*Heading") "/tmp/a.org"))
    (delete-directory dir t)))

(ert-deftest messages/times-and-colors-without-recursion ()
  (load (expand-file-name "+messages" test-lisp-dir) nil t)
  (with-current-buffer (messages-buffer) (+messages-setup-h))
  ;; *Messages* is read-only and stamping runs inside `message': this once
  ;; recursed forever (an error, reported by `message', stamped again).
  (message "[eglot] (warning) Use ‘find-file’ or C-x C-f")
  (message "plain")
  (message "plain")
  (with-current-buffer "*Messages*"
    (font-lock-ensure)
    (goto-char (point-max))
    (forward-line -2)
    (should (string-match-p "\\`[0-9:]+ \\'" (get-text-property (point) 'line-prefix)))
    (should (memq '+messages-tag (ensure-list (get-text-property (point) 'face))))
    (forward-line 1)
    (should (equal (buffer-substring-no-properties (line-beginning-position) (line-end-position)) "plain [2 times]"))
    (should (get-text-property (point) 'line-prefix))))

(ert-deftest org-subtree-edit/round-trip-at-its-level ()
  (load (expand-file-name "+org-subtree-edit" test-lisp-dir) nil t)
  (require 'org)
  (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b))))
    (with-temp-buffer
      (let ((org-mode-hook nil)) (org-mode))
      (insert "* Top\n** Middle\n*** Deep\ntext\n**** Deeper\n** Next\n")
      (let ((src (current-buffer)))
        (goto-char (point-min)) (search-forward "*** Deep")
        (+org-subtree-edit)
        ;; Promoted: level 3 reads as level 1.
        (should (equal (buffer-string) "* Deep\ntext\n** Deeper\n"))
        (goto-char (point-max)) (insert "** Added\n")
        (cl-letf (((symbol-function 'quit-window) #'ignore))
          (+org-subtree-edit-finish))
        (with-current-buffer src
          (should (equal (buffer-string) "* Top\n** Middle\n*** Deep\ntext\n**** Deeper\n**** Added\n** Next\n")))))
    ;; The original changed meanwhile: refuses.
    (with-temp-buffer
      (let ((org-mode-hook nil)) (org-mode))
      (insert "* A\nbody\n* B\n")
      (let ((src (current-buffer)))
        (goto-char (point-min))
        (+org-subtree-edit)
        (let ((edit (current-buffer)))
          (with-current-buffer src (goto-char (point-min)) (forward-line 1) (insert "changed\n"))
          (set-buffer edit)
          (should-error (+org-subtree-edit-finish) :type 'user-error))))))

(ert-deftest org-ai-capture/vault-files-everywhere-it-is-told ()
  (load (expand-file-name "+org-ai-capture" test-lisp-dir) nil t)
  (require 'org)
  (let* ((org-directory (file-name-as-directory (make-temp-file "vault" t)))
         (a (expand-file-name "a.org" org-directory))
         (b (expand-file-name "b.org" org-directory)))
    (with-temp-file a (insert "#+title: Alpha\n\n* Tasks\n** Emacs\n"))
    (with-temp-file b (insert "* Ideas\n"))
    (unwind-protect
        (let* ((outline (+vault-capture--outline))
               (num (lambda (title) (1+ (cl-position title outline :key (lambda (x) (nth 4 x)) :test #'equal))))
               (entries '("* Fix the popup" "* Top of b" "* Under a new heading" "* In a new file" "* Unplaced"))
               (answer (list :placements
                             (vector (list :entry 1 :under (funcall num "Emacs"))
                                     (list :entry 2 :under (funcall num "b"))
                                     (list :entry 3 :new "Later" :new_under (funcall num "Alpha"))
                                     (list :entry 4 :new_file "../escape/Reading List" :title "Reading")))))
          (setq answer (plist-put answer :placements (append (plist-get answer :placements) nil)))
          (should (equal (mapcar (lambda (x) (nth 4 x)) outline) '("Alpha" "Tasks" "Emacs" "b" "Ideas")))
          (let ((places (car (+vault-capture--file answer outline entries))))
            (should (equal places '("a.org › Emacs" "b.org" "a.org › Later" "Reading-List.org" "inbox.org"))))
          (should (string-match-p "\\*\\* Emacs\n\\*\\*\\* Fix the popup" (with-temp-buffer (insert-file-contents a) (buffer-string))))
          (should (string-match-p "^\\* Later\n\\*\\* Under a new heading" (with-temp-buffer (insert-file-contents a) (buffer-string))))
          (should (string-match-p "^\\* Top of b" (with-temp-buffer (insert-file-contents b) (buffer-string))))
          ;; A file name can't leave the vault.
          (should (file-exists-p (expand-file-name "Reading-List.org" org-directory)))
          (should (file-exists-p (expand-file-name "inbox.org" org-directory))))
      (dolist (buf (buffer-list))
        (when (and (buffer-file-name buf) (string-prefix-p org-directory (buffer-file-name buf)))
          (with-current-buffer buf (set-buffer-modified-p nil)) (kill-buffer buf)))
      (delete-directory org-directory t))))

(ert-deftest attention/lag-finds-the-slow-hook-and-cleans-up ()
  (load (expand-file-name "+attention" test-lisp-dir) nil t)
  (let* ((+attention-dir (make-temp-file "attention" t))
         (file (expand-file-name "lag.txt" +attention-dir)))
    (defun attention-test-slow-h () (sleep-for 0.02))
    (defun attention-test-quick-h () nil)
    (add-hook 'post-command-hook #'attention-test-slow-h)
    (add-hook 'post-command-hook #'attention-test-quick-h)
    (unwind-protect
        (progn
          (should (string-match-p "measuring until" (+attention-measure-lag 0.5 file)))
          (dotimes (_ 5) (run-hooks 'post-command-hook))
          (sit-for 0.8)
          (let ((report (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "^  attention-test-slow-h +[0-9.]+" report))
            ;; Slowest first.
            (should (< (string-search "attention-test-slow-h" report)
                       (or (string-search "attention-test-quick-h" report) most-positive-fixnum))))
          ;; No timing advice left behind.
          (should-not (advice-member-p '+attention 'attention-test-slow-h)))
      (remove-hook 'post-command-hook #'attention-test-slow-h)
      (remove-hook 'post-command-hook #'attention-test-quick-h)
      (delete-directory +attention-dir t))))

(ert-deftest attention/profile-text-ranks-functions ()
  (load (expand-file-name "+attention" test-lisp-dir) nil t)
  (let ((log (make-hash-table :test #'equal)))
    (puthash (vector 'leaf-a 'caller 'top) 30 log)
    (puthash (vector 'leaf-b 'caller 'top) 10 log)
    (let ((text (+attention--profile-text log)))
      (should (string-match-p "100\\.0%  caller" text))
      (should (string-match-p " 75\\.0%  leaf-a" text)))))

(ert-deftest info/highlights-resumes-and-counts ()
  (load (expand-file-name "+info" test-lisp-dir) nil t)
  (require 'info)
  (let* ((+info--progress nil)
         (+info-progress-file (make-temp-file "info-progress" nil ".eld")))
    (info "(elisp) Function Cells" "*info-test*")
    (unwind-protect
        (with-current-buffer "*info-test*"
          ;; Lisp examples get emacs-lisp-mode's colors.
          (goto-char (point-min))
          (re-search-forward "^ +(defun bar")
          (should (eq (get-text-property (+ (line-beginning-position) 11) 'font-lock-face) 'font-lock-keyword-face))
          ;; The header says how far, with a real percent sign.
          (should (string-match-p "· [0-9]+%% read (1 of [0-9]+ nodes)" header-line-format))
          ;; Opening the manual at Top again goes back where you were.
          (Info-goto-node "Symbol Components")
          (forward-line 6)
          (+info-moved-h)
          (let ((line (line-number-at-pos)))
            (setq +info--resumed nil)
            (Info-goto-node "Top")
            (sit-for 0.05)
            (should (equal Info-current-node "Symbol Components"))
            (should (= (line-number-at-pos) line))))
      (kill-buffer "*info-test*"))))

(ert-deftest format/c-ret-heading-gets-blank-lines ()
  ;; Doom's heading insertion, as +org--insert-item does it (stars by hand).
  (cl-letf (((symbol-function 'doom-insert-heading-stub)
             (lambda (direction)
               (let ((level (org-current-level)))
                 (pcase direction
                   ('below (goto-char (line-end-position)) (org-end-of-subtree)
                           (insert "\n" (make-string level ?*) " "))
                   ('above (org-back-to-heading) (insert (make-string level ?*) " ")
                           (save-excursion (insert "\n"))))))))
    (with-temp-buffer
      (let ((org-mode-hook nil)) (org-mode))
      (insert "* One\ntext\n\n* Two\n")
      (goto-char (point-min))
      (+format-org-heading-blank-a #'doom-insert-heading-stub 'below)
      (insert "New")
      (should (equal (buffer-string) "* One\ntext\n\n* New\n\n* Two\n"))
      (goto-char (point-max)) (forward-line -1)
      (+format-org-heading-blank-a #'doom-insert-heading-stub 'above)
      (insert "Above")
      (should (equal (buffer-string) "* One\ntext\n\n* New\n\n* Above\n\n* Two\n")))))

(ert-deftest format/org-tidies-tables-lists-cookies-blanks ()
  (with-temp-buffer
    (org-mode)
    (insert "* Tasks [/]   \n"
            "- [X] one\n- [ ] two\n\nSteps:\n"
            "1. a\n3. b\n7. c\n\n"
            "| x | longer |\n|-+-|\n| 1 | 2 |\n")
    (+format-org)
    (should (equal (buffer-string)
                   (concat "* Tasks [1/2]\n\n"
                           "- [X] one\n- [ ] two\n\nSteps:\n\n"
                           "1. a\n2. b\n3. c\n\n"
                           "| x | longer |\n|---+--------|\n| 1 |      2 |\n")))))

(ert-deftest format/org-region-only ()
  (with-temp-buffer
    (org-mode)
    (insert "| a | bb |\n|-|\n\ntext   \n")
    (+format-org (point-min) 12)
    (should (string-prefix-p "| a | bb |\n|---+----|\n" (buffer-string)))
    ;; Outside the region: untouched.
    (should (string-suffix-p "text   \n" (buffer-string)))))

(ert-deftest format/org-canonical-round-trip ()
  (with-temp-buffer
    (org-mode)
    (insert "* H\n#+BEGIN_SRC sh\necho\n#+END_SRC\n")
    (should (equal (+format-org-canonical) "* H\n#+begin_src sh\necho\n#+end_src\n"))))

;;; +vocab

(load (expand-file-name "../lisp/+vocab" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defconst test-vocab-results
  ;; The shape leo hands `leo--open-translation-buffer' (from a real lookup).
  '((("Verben"
      (((result . "to   hear  (sth.)   |heard, heard|")) ((result . "(etw. Akk. )  hören   |hörte, gehört|")))
      (((result . "to   listen")) ((result . "hören")))))
    (("Substantive"
      (((result . "hearing")) ((result . "das   Hören   kein Pl.")))))))

(ert-deftest vocab/translations-flatten-and-clean ()
  (let ((+vocab-max-translations 2))
    (should (equal (+vocab-translations test-vocab-results)
                   '("to hear (sth.) |heard, heard| — (etw. Akk. ) hören |hörte, gehört|  /Verben/"
                     "to listen — hören  /Verben/")))))

(ert-deftest vocab/record-creates-a-card-then-counts-lookups ()
  (let ((+vocab-file (make-temp-file "vocab" nil ".org")))
    (unwind-protect
        (progn
          (+vocab-record "hören" "en" (+vocab-translations test-vocab-results))
          (+vocab-record "hören" "en" (+vocab-translations test-vocab-results))
          (with-current-buffer (find-file-noselect +vocab-file)
            (revert-buffer t t)
            (goto-char (point-min))
            (should (= 1 (how-many "^\\* hören")))
            (should (search-forward "** Back\n- to hear (sth.)" nil t))
            (goto-char (point-min))
            (search-forward "* hören")
            (should (equal (org-entry-get nil "LEO_LOOKUPS") "2"))
            (should (equal (org-entry-get nil "LEO_LANG") "en"))
            (when (featurep 'org-fc)
              (should (equal (org-entry-get nil "FC_TYPE") "double"))
              (should (member "fc" (org-get-tags nil t))))
            (set-buffer-modified-p nil)
            (kill-buffer)))
      (delete-file +vocab-file))))

(ert-deftest usage/summary-ranks-and-describes ()
  (let ((+usage-file (make-temp-file "usage" nil ".eld"))
        (+usage--counts (make-hash-table :test #'eq)))
    (unwind-protect
        (progn
          (with-temp-file +usage-file
            (prin1 '((find-file ("SPC f f" . 3) ("M-x" . 1)) (magit-status ("M-x" . 9))) (current-buffer)))
          (let ((lines (split-string (+usage-summary) "\n")))
            (should (string-match-p "^ +9  magit-status  via M-x×9" (car lines)))
            (should (string-match-p "^ +4  find-file  via SPC f f×3, M-x×1" (cadr lines)))))
      (delete-file +usage-file))))

(ert-deftest usage/macros-are-not-counted ()
  (let ((+usage--counts (make-hash-table :test #'eq))
        (this-command 'forward-char) (real-this-command 'forward-char)
        (executing-kbd-macro "abc"))
    (+usage--record-h)
    (should (zerop (hash-table-count +usage--counts)))))

;;; +completion

(load (expand-file-name "../lisp/+completion" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(ert-deftest completion/context-in-org ()
  (with-temp-buffer
    (org-mode)
    (insert "* Heading :wo")
    (should (eq (+completion-context) 'org-tag))
    (insert "\n#+TIT")
    (should (eq (+completion-context) 'org-keyword))
    (insert "\nSee [[id:ab")
    (should (eq (+completion-context) 'org-link))
    (insert "\nplain words hö")
    (should (eq (+completion-context) 'prose))
    (insert "\n#+begin_src emacs-lisp\n(mess")
    (save-excursion (insert "\n#+end_src\n"))
    (should (eq (+completion-context) 'org-src))))

(ert-deftest completion/context-in-code ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun f () \"a docstring wo")
    (should (eq (+completion-context) 'prose))
    (insert "\")\n(mess")
    (should (eq (+completion-context) 'code))))

(ert-deftest completion/prose-looks-up-what-was-typed ()
  ;; orderless asks the table with "": looking that up collected every
  ;; word of every Org buffer and froze Emacs for minutes.
  (let (asked)
    (cl-letf (((symbol-function '+completion--words)
               (lambda (input) (push input asked) (list "Word" "World"))))
      (with-temp-buffer
        (text-mode)
        (insert "Some text. W")
        (should-not (+completion-prose-capf))   ; one letter: nothing yet
        (insert "or")
        (let ((table (nth 2 (+completion-prose-capf))))
          (should (equal (all-completions "" table) '("Word" "World")))
          (should (equal (all-completions "Worl" table) '("World")))
          (insert "l")
          (all-completions "" table)
          (should (equal (reverse asked) '("Wor" "Worl"))))))))

(defvar cape-dabbrev-buffer-function)
(ert-deftest completion/prose-words-only ()
  ;; cape isn't in CI (Doom's packages aren't installed there).
  (skip-unless (require 'cape nil t))
  (cl-letf (((symbol-function 'cape--dabbrev-list)
             (lambda (_) (cons nil '("Work*" "WordMap" "Word" "API"))))
            ((symbol-function 'cape--dict-list)
             (lambda (_) (cons nil '("Word" "Wort" "Word's")))))
    (let ((cape-dabbrev-buffer-function #'ignore))
      (should (equal (+completion--words "Wo")
                     '("Word" "API" "Wort" "Word's"))))))

(defmacro test-usage--with-fresh (&rest body)
  `(let* ((+usage-file (make-temp-file "usage" nil ".eld"))
          (+usage-sequence-file (make-temp-file "useq" nil ".eld"))
          (+usage--counts (make-hash-table :test #'eq))
          (+usage--pairs (make-hash-table :test #'equal))
          (+usage--modes (make-hash-table :test #'equal))
          (+usage--last nil) (+usage--recent nil))
     (unwind-protect (progn ,@body)
       (delete-file +usage-file) (delete-file +usage-sequence-file))))

(defun test-usage--run (&rest cmds)
  "Record CMDS as if run in a row in `emacs-lisp-mode'."
  (with-temp-buffer
    (emacs-lisp-mode)
    (dolist (c cmds)
      (let ((this-command c) (real-this-command c) (executing-kbd-macro nil))
        (+usage--record-h)))))

(ert-deftest usage/anticipates-what-follows-the-last-command ()
  (test-usage--with-fresh
   ;; save-buffer is usually followed by dired; find-file is common here.
   (test-usage--run 'save-buffer 'dired 'save-buffer 'dired
                    'find-file 'find-file 'find-file 'save-buffer)
   (+usage--save-sequences)               ; and it survives a save
   (let ((rows (+usage-anticipations 'save-buffer 'emacs-lisp-mode)))
     (should (eq (car (car rows)) 'dired))
     (should (equal (cdr (assq 'dired rows)) '(8 2 2)))
     (should-not (assq 'save-buffer rows)))
   (should (equal (car +usage--recent) '(save-buffer . emacs-lisp-mode)))))

(ert-deftest perf/modeline-worktree-icon-substituted ()
  (should (equal (+perf-modeline-icon-a '("nf-cod-worktree" "⑆" "WT" face codicon))
                 '("nf-cod-repo_forked" "⑆" "WT" face codicon)))
  (should (equal (+perf-modeline-icon-a '("nf-dev-git_branch" "" "@" face))
                 '("nf-dev-git_branch" "" "@" face))))

(ert-deftest format/sentences-know-abbreviations-and-ordinals ()
  (should (equal (+format-sentences "Das ist z.B. gut. Am 3. Mai kam J. Doe!  Next one, e.g. this? Yes.")
                 '("Das ist z.B. gut." "Am 3. Mai kam J. Doe!" "Next one, e.g. this?" "Yes.")))
  (should (equal (+format-sentences "A quote: \"Done.\" Then *bold.* End")
                 '("A quote: \"Done.\"" "Then *bold.*" "End"))))

(ert-deftest format/sentence-lines-in-a-list-item ()
  (with-temp-buffer
    (org-mode)
    (insert "- One sentence here. Another one\n  wrapped. Third.\n")
    (goto-char 5)
    (+format/sentence-lines)
    (should (equal (buffer-string)
                   "- One sentence here.\n  Another one wrapped.\n  Third.\n"))))

(ert-deftest format/fill-then-unfill ()
  (with-temp-buffer
    (text-mode)
    (setq fill-column 20)
    (insert "one two three four five six seven eight")
    (goto-char 1)
    (let ((this-command '+format/fill-dwim) (last-command nil))
      (+format/fill-dwim))
    (should (string-match-p "\n" (buffer-string)))
    (let ((this-command '+format/fill-dwim) (last-command '+format/fill-dwim))
      (+format/fill-dwim))
    (should (equal (buffer-string) "one two three four five six seven eight"))))

(ert-deftest format/join-paragraphs ()
  (with-temp-buffer
    (text-mode)
    (insert "first part\nof it.\n\nsecond part.")
    (+format/join-paragraphs (point-min) (point-max))
    (should (equal (buffer-string) "first part of it. second part."))))

(ert-deftest format/split-paragraphs-applies-only-unchanged-words ()
  (dolist (case '(("One topic. Still it. Another topic now." . "One topic. Still it.\n\nAnother topic now.")
                  ("One topic. Still it. Another topic now." . "One topic. Still it.\n\nA different topic now.")))
    (with-temp-buffer
      (text-mode)
      (insert (car case))
      (goto-char 1)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (_prompt &rest args) (funcall (plist-get args :callback) (cdr case) nil))))
        (+format/split-paragraphs))
      (should (equal (buffer-string)
                     (if (+format-same-words-p (car case) (cdr case))
                         "One topic. Still it.\n\nAnother topic now."
                       (car case)))))))

(ert-deftest usage/coach-names-bigger-steps-bound-here ()
  (with-temp-buffer
    (let ((map (make-sparse-keymap)))
      (define-key map "l" #'evil-forward-char)
      (define-key map "w" #'evil-forward-word-begin)
      (define-key map "s" #'evil-snipe-s)
      (use-local-map map)
      (let ((tip (substring-no-properties (+usage-coach-tip 'evil-forward-char 14))))
        (should (string-match-p "\\`l×14 → 14l counted · w word · s to 2 chars\\'" tip)))
      ;; Nothing bound: no tip rather than keys that don't work here.
      (use-local-map (make-sparse-keymap))
      (should-not (+usage-coach-tip 'vellumory-scroll-down 14)))))

(ert-deftest usage/coach-speaks-once-at-the-threshold-then-rests ()
  (test-usage--with-fresh
   (let ((+usage-coach t) (+usage-coach-after 3) (+usage--coached nil) (+usage--run 0) shown)
     (cl-letf (((symbol-function '+usage-coach-tip) (lambda (cmd n &rest _) (format "%s %d" cmd n)))
               ((symbol-function 'message) (lambda (_fmt s) (push s shown))))
       (apply #'test-usage--run (make-list 5 'next-line))
       (should (equal shown '("next-line 3")))
       (test-usage--run 'evil-undo 'next-line 'next-line 'next-line)
       (should (equal shown '("next-line 3")))))))

(ert-deftest perf/new-frames-collect-garbage-only-once-idle ()
  (let ((gc-cons-threshold 800000) (+perf--gc-restore nil) timers
        (gcmh-mode nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_ _ f) (push f timers))))
      (+perf-frame-without-gc-a (lambda () (should (= gc-cons-threshold most-positive-fixnum))))
      ;; A second frame before idle doesn't take the raised value for normal.
      (+perf-frame-without-gc-a #'ignore)
      (should (= 1 (length timers)))
      (funcall (car timers))
      (should (= gc-cons-threshold 800000))
      (should-not +perf--gc-restore))))

(ert-deftest completion/minibuffer-resume-puts-the-input-back ()
  (let ((+minibuffer--ring nil) (+minibuffer--leaving nil) got)
    (defalias 'test-minibuffer--cmd (lambda () (interactive) (setq got (read-string "x: "))))
    (defalias 'test-minibuffer--other (lambda () (interactive) (read-string "y: ")))
    (cl-flet ((close (cmd text)
                (with-temp-buffer
                  (insert text)
                  (let ((current-minibuffer-command cmd)) (+minibuffer-remember-h)))))
      ;; Closing a minibuffer remembers its command and input.
      (close 'test-minibuffer--cmd "half a question")
      (should (equal (plist-get (car +minibuffer--ring) :input) "half a question"))
      ;; The resume itself isn't remembered as the thing to resume.
      (close '+minibuffer/resume "")
      (should (= (length +minibuffer--ring) 1))
      ;; Newest first, each once.
      (close 'test-minibuffer--other "b")
      (close 'test-minibuffer--other "c")
      (close 'test-minibuffer--other "b")
      (should (equal (mapcar (lambda (e) (plist-get e :input)) +minibuffer--ring)
                     '("b" "c" "half a question"))))
    ;; Reopened: the same command, its input back in place.  (Batch
    ;; read-string reads stdin: a stand-in runs the minibuffer setup.)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _)
                 (with-temp-buffer (insert "old")
                   (run-hooks 'minibuffer-setup-hook)
                   (buffer-string)))))
      (+minibuffer--open 2))
    (should (equal got "half a question"))
    ;; Vertico sessions go to vertico-repeat, with their session.
    (let (repeated)
      (cl-letf (((symbol-function 'vertico-repeat--run) (lambda (s) (setq repeated s))))
        (setq +minibuffer--ring '((:command find-file :input "~/x" :session (find-file "~/x"))))
        (+minibuffer/resume))
      (should (equal repeated '(find-file "~/x"))))))


(ert-deftest completion/inline-code-completes-elisp-names-commands-first ()
  ;; cape isn't in CI (Doom's packages aren't installed there).
  (skip-unless (require 'cape nil t))
  (cl-flet ((start-in (text)
              (with-temp-buffer
                (org-mode)
                (insert text)
                (+completion--inline-code-start))))
    ;; Typing inside ~code~ or =verbatim=, not closed yet.
    (should (= (start-in "use ~consult-li") 6))
    (should (= (start-in "use =find-fi") 6))
    (should (= (start-in "~(setq fill") 2))
    ;; Prose: closed, a lone tilde, an equation.
    (should-not (start-in "use ~foo~ and bar"))
    (should-not (start-in "takes ~ 5 min"))
    (should-not (start-in "x = 1 and y")))
  (with-temp-buffer
    (org-mode)
    (insert "run ~(save-some-buf")
    (should (eq (+completion-context) 'inline-code))
    (pcase-let ((`(,beg ,end ,table . ,props) (+completion-code-capf)))
      ;; The symbol only, not the paren.
      (should (equal (buffer-substring beg end) "save-some-buf"))
      (should (member "save-some-buffers" (all-completions "save-some-buf" table)))
      ;; Choosing one closes the code.
      (goto-char (point-max))
      (insert "fers")
      (funcall (plist-get props :exit-function) "save-some-buffers" 'finished)
      (should (equal (buffer-string) "run ~(save-some-buffers~"))))
  (should (equal (+completion--code-sort (list "fill-column" "car" "forward-word"))
                 '("forward-word" "car" "fill-column"))))

(ert-deftest format/org-blank-lines-by-convention ()
  (cl-flet ((fmt (text)
              (with-temp-buffer
                (org-mode)
                (insert text)
                (+format-org-blank-lines)
                (buffer-string))))
    ;; One blank line between headings and before a heading's text; the
    ;; heading's planning and drawer stay right under it.
    (should (equal (fmt "#+TITLE: x\n* A\nSCHEDULED: <2026-11-04 Wed>\n:PROPERTIES:\n:ID: 1\n:END:\ntext\n** B\n\n\n\n* C")
                   "#+title: x\n\n* A\nSCHEDULED: <2026-11-04 Wed>\n:PROPERTIES:\n:ID: 1\n:END:\n\ntext\n\n** B\n\n* C\n"))
    ;; Tables, lists and blocks set apart; text around them is not.
    (should (equal (fmt "* A\n\nintro\n- one\n- two\nafter\n| a |\nmore\nand more\n")
                   "* A\n\nintro\n\n- one\n- two\n\nafter\n\n| a |\n\nmore\nand more\n"))
    ;; Blank lines inside a block are its content; its delimiters lower case,
    ;; not what it contains.
    (should (equal (fmt "* A\n\n#+NAME: s\n#+BEGIN_SRC sh\necho\n\n\n#+TITLE: kept\n#+END_SRC\n\n\n\ntext\n")
                   "* A\n\n#+name: s\n#+begin_src sh\necho\n\n\n#+TITLE: kept\n#+end_src\n\ntext\n"))
    ;; Runs of blank lines between paragraphs: one (a whole run, however long).
    (should (equal (fmt "a\n\n\n\nb\n") "a\n\nb\n"))
    ;; A list item's own paragraphs aren't top-level: left alone.
    (should (equal (fmt "* A\n\n- item\n  more of it\n- next\n")
                   "* A\n\n- item\n  more of it\n- next\n")))
  ;; In a region, the end isn't the buffer's: no newline forced there.
  (with-temp-buffer
    (org-mode)
    (insert "* A\ntext\n* B\nrest")
    (save-restriction
      (narrow-to-region 1 10)
      (+format-org-blank-lines))
    (should (equal (buffer-string) "* A\n\ntext\n* B\nrest"))))

(load (expand-file-name "+org-lint" test-lisp-dir) nil t)

(ert-deftest org-lint/style-rules-find-what-they-say ()
  (require 'org-lint)
  (cl-flet ((lint (rule text)
              (with-temp-buffer
                (org-mode)
                (insert text)
                (goto-char (point-min))
                (mapcar #'cadr (funcall rule (org-element-parse-buffer))))))
    ;; Code in =verbatim=; keys and file names stay verbatim.
    (should (equal (lint #'+org-lint-verbatim-code
                         "Use =forward-word= or =(setq x 1)=, keys =C-c C-c= =SPC c f=, file =README.org=, =fill-column=.\n")
                   '("=forward-word= is code: Org writes code as ~forward-word~"
                     "=(setq x 1)= is code: Org writes code as ~(setq x 1)~"
                     "=fill-column= is code: Org writes code as ~fill-column~")))
    (should (equal (lint #'+org-lint-empty-heading "* TODO\n* Fine\n") '("Heading without a title")))
    (should (equal (lint #'+org-lint-heading-increment "* A\n*** C\n** B\n")
                   '("Heading level 3 under level 1: skips a level")))
    (should (equal (lint #'+org-lint-duplicate-sibling "* A\n** X\n** X\n* B\n** X\n")
                   '("Same heading as a sibling above: X")))
    (should (equal (lint #'+org-lint-heading-punctuation "* Done.\n* Why?\n* Tasks: [1/2]\n* More ...\n")
                   '("Heading ends in \".\"" "Heading ends in \":\"")))
    (should (equal (lint #'+org-lint-blank-lines "a\n\n\nb\n#+begin_src sh\n1\n\n\n2\n#+end_src\n")
                   '("More than one blank line")))
    (should (equal (lint #'+org-lint-trailing-whitespace "a \nb\n") '("Trailing whitespace")))
    (should (equal (lint #'+org-lint-missing-blank-line "* A\ntext\n\n* B\n")
                   '("No blank line before this (SPC c f adds it)")))
    (should (equal (lint #'+org-lint-keyword-case "#+TITLE: x\n#+begin_src sh\n#+TITLE: in code\n#+end_src\n")
                   '("#+TITLE:: Org writes it lower case")))
    (should (equal (lint #'+org-lint-list-bullets "- a\n+ b\n\n1. x\n2) y\n")
                   '("Bullet + in a list of -"))))
  ;; Registered with org-lint, in the style category.
  (should (seq-find (lambda (c) (eq (org-lint-checker-name c) '+org-lint-list-bullets))
                    org-lint--checkers)))

(ert-deftest org-lint/markup-headings-languages-links ()
  (require 'org-lint)
  (cl-flet ((lint (rule text)
              (with-temp-buffer
                (org-mode)
                (insert text)
                (mapcar #'cadr (funcall rule (org-element-parse-buffer))))))
    (should (equal (lint #'+org-lint-mixed-markup "Run ~make~ and ~make~, then =make=; =other= stays.\n")
                   '("make is =make= here but ~make~ 2× elsewhere: pick one (~code~ for code, =verbatim= for literal text)")))
    (should (equal (lint #'+org-lint-emphasis-heading "*Setup*\n\nText with *bold* in it.\n\n- *item*\n")
                   '("Emphasis as a heading (MD036): make it a heading")))
    (should (equal (lint #'+org-lint-link-text "See [[https://a.b][here]] and [[https://c.d][the manual]].\n")
                   '("Link text \"here\" (MD059): say where it leads")))))

(ert-deftest org-lint/many-of-a-kind-shown-once-as-you-write ()
  (with-temp-buffer
    (org-mode)
    (insert "* A\n\none \n\n* B\n\ntwo \n\n* C\n\nthree \n\n* D\n\nfour \n\n#+begin_src\n#+end_src\n")
    (let ((found (+org-lint-findings)))
      ;; Style: one finding with a count; Org's own checks (here: a src
      ;; block without a language) as warnings.
      (should (equal (seq-filter (lambda (f) (eq (nth 1 f) 'info)) found)
                     '((9 info "Trailing whitespace, and 3 more like it (M-x org-lint lists them)"))))
      (should (seq-find (lambda (f) (eq (nth 1 f) 'warning)) found)))))


(ert-deftest completion/tex-names-complete-to-unicode-shown-in-the-popup ()
  ;; cape isn't in CI (Doom's packages aren't installed there).
  (skip-unless (require 'cape nil t))
  (cl-flet ((capf-in (mode text)
              (with-temp-buffer
                (funcall mode)
                (insert text)
                (+completion-tex-capf))))
    (pcase-let ((`(,beg ,end ,table . ,props) (capf-in #'org-mode "the angle \\omeg")))
      (should (= (- end beg) 5))           ; \\omeg
      (should (member "\\omega" (all-completions "\\omeg" table)))
      ;; The character itself shows beside the name.
      (should (string-match-p "ω" (funcall (plist-get props :annotation-function) "\\omega"))))
    ;; Where \omega means \omega: Org math, LaTeX; and _/^ aren't triggers.
    (should-not (capf-in #'org-mode "math \\(\\omeg"))
    (should-not (capf-in #'latex-mode "\\omeg"))
    (should-not (capf-in #'org-mode "an _underlin"))))

(ert-deftest completion/unicode-picker-shows-the-character-first ()
  (let ((cands (+unicode--candidates)))
    (should (member "ω  GREEK SMALL LETTER OMEGA  U+03C9" cands))
    ;; Combining marks get a base to sit on.
    (should (member "◌́  COMBINING ACUTE ACCENT  U+0301" cands))
    (should (= (+unicode--char "ω  GREEK SMALL LETTER OMEGA  U+03C9") ?ω))
    (with-temp-buffer
      (+unicode/insert ?ω 3)
      (should (equal (buffer-string) "ωωω")))))

(load (expand-file-name "+org-slash" test-lisp-dir) nil t)

(ert-deftest org-slash/commands-complete-and-become-org ()
  (cl-flet ((run (text cand)
              (with-temp-buffer
                (org-mode)
                (insert text)
                (pcase-let ((`(,beg ,end ,table . ,props) (+org-slash-capf)))
                  (should (member cand (all-completions (buffer-substring beg end) table)))
                  (delete-region beg end)
                  (insert cand)
                  (funcall (plist-get props :exit-function) cand 'finished))
                (buffer-string))))
    (should (equal (run "* A\n/ta" "/table") "* A\n|   |   |   |\n|---+---+---|\n|   |   |   |\n"))
    ;; COLUMNSxROWS, as org-table-create asks.
    (should (equal (run "/table2x1" "/table2x1") "|   |   |\n"))
    (should (equal (run "notes /che" "/check") "notes - [ ] "))
    (should (string-match-p "\\`#\\+begin_quote\n" (run "/qu" "/quote")))
    (should (equal (run "* A\n** B\n/to" "/todo") "* A\n** B\n*** TODO ")))
  ;; Not inside words, paths, code or src blocks.
  (with-temp-buffer
    (org-mode)
    (insert "and/or")
    (should-not (+org-slash-capf))
    (erase-buffer)
    (insert "~/ta")
    (should-not (+org-slash-capf))
    (erase-buffer)
    (insert "#+begin_src sh\n/ta\n#+end_src")
    (goto-char (point-min))
    (forward-line 1)
    (end-of-line)
    (should-not (+org-slash-capf))))

(load (expand-file-name "+org-cheatsheet" test-lisp-dir) nil t)

(ert-deftest org-cheatsheet/every-example-is-org-and-names-a-real-node ()
  (require 'info)
  (let ((nodes (ignore-errors (mapcar #'car (Info-toc-nodes "org")))))
    (dolist (e +org-cheatsheet)
      ;; The manual node exists (when the manual is installed here).
      (when nodes (should (member (nth 2 e) nodes)))
      ;; Each example parses as Org without errors.
      (with-temp-buffer
        (org-mode)
        (insert (nth 1 e))
        (should (org-element-parse-buffer)))))
  ;; Picking shows it; i puts it where you were.
  (with-temp-buffer
    (set-window-buffer (selected-window) (current-buffer))
    (insert "x ")
    (cl-letf (((symbol-function 'pop-to-buffer) #'set-buffer)
              ((symbol-function 'quit-window) #'ignore))
      (+org/cheatsheet "Horizontal rule")
      (with-current-buffer "*Org by example*"
        (should (string-match-p "\\`-----\n\n# Manual: (org) Horizontal Rules" (buffer-string)))
        (+org-cheatsheet-insert))
      (should (equal (buffer-string) "x -----")))
    (kill-buffer "*Org by example*")))


(load (expand-file-name "+org-ai-capture" test-lisp-dir) nil t)

(ert-deftest org-ai-capture/files-entries-where-the-model-says-checked ()
  (with-temp-buffer
    (org-mode)
    (buffer-enable-undo)
    (insert "* Work\n** Reports\n* Home\n")
    (undo-boundary)
    (let* ((before (buffer-string))
           (outline (+org-ai-capture--outline))
           (entries (+org-ai-capture--entries "TODO Write Q4 report\nBuy milk\nLearn Zig\nStray")))
      (should (equal entries '("* TODO Write Q4 report" "* Buy milk" "* Learn Zig" "* Stray")))
      ;; The request numbers headings and entries.
      (should (string-match-p "\\[2\\] Reports\n" (+org-ai-capture--request outline entries)))
      (should (string-match-p "{3} \\* Learn Zig" (+org-ai-capture--request outline entries)))
      (let ((plan (+org-ai-capture--plan
                   '(:placements ((:entry 1 :under 2)
                                  (:entry 2 :under 3)
                                  (:entry 3 :new "Learning" :new_under 0)
                                  (:entry 4 :under 99)))
                   outline entries)))
        (should (equal (+org-ai-capture--apply plan)
                       '("Reports" "Home" "Learning" "top level"))))
      (should (equal (buffer-string)
                     "* Work\n** Reports\n*** TODO Write Q4 report\n* Home\n** Buy milk\n* Learning\n** Learn Zig\n* Stray\n"))
      ;; One undo takes the capture back.
      (undo-boundary)
      (primitive-undo 1 (cdr buffer-undo-list))
      (should (equal (buffer-string) before))))
  ;; Starred text keeps its subtrees together.
  (should (equal (+org-ai-capture--entries "** A\nbody\n*** sub\n** B")
                 '("** A\nbody\n*** sub" "** B"))))

(require 'transient)
(load (expand-file-name "+nix" test-lisp-dir) nil t)

(ert-deftest nix/develop-env-from-print-dev-env ()
  (let* ((process-environment (cons "PATH=/usr/bin" process-environment))
         (pairs (+nix-develop--pairs
                 "{\"variables\": {
                    \"PATH\": {\"type\": \"exported\", \"value\": \"/nix/store/x-zig/bin\"},
                    \"CC\": {\"type\": \"exported\", \"value\": \"gcc\"},
                    \"HOME\": {\"type\": \"exported\", \"value\": \"/homeless-shelter\"},
                    \"TMPDIR\": {\"type\": \"exported\", \"value\": \"/build\"},
                    \"buildInputs\": {\"type\": \"var\", \"value\": \"a b\"},
                    \"phases\": {\"type\": \"array\", \"value\": [\"x\"]}}}")))
    ;; Exported only; the sandbox's HOME/TMPDIR left out; its PATH in front.
    (should (equal (sort (mapcar #'car pairs) #'string<) '("CC" "PATH")))
    (should (equal (cdr (assoc "PATH" pairs)) "/nix/store/x-zig/bin:/usr/bin")))
  ;; A buffer without .envrc in a project whose dev shell is loaded gets it;
  ;; others go to envrc as before.
  (let* ((root (file-name-as-directory (make-temp-file "flake" t)))
         (+nix-develop--envs (make-hash-table :test #'equal))
         applied original)
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "flake.nix" root) (insert "{}"))
          (puthash root '(("CC" . "gcc")) +nix-develop--envs)
          (cl-letf (((symbol-function 'envrc--find-env-dir) #'ignore)
                    ((symbol-function 'envrc--apply) (lambda (_buf env) (setq applied env))))
            (let ((default-directory root))
              (+nix-develop--envrc-a (lambda () (setq original t))))
            (should (equal applied '(("CC" . "gcc"))))
            (should-not original)
            (let ((default-directory temporary-file-directory))
              (+nix-develop--envrc-a (lambda () (setq original t))))
            (should original)))
      (delete-directory root t))))

(load (expand-file-name "+zoxide" test-lisp-dir) nil t)

(ert-deftest zoxide/ranking-in-emacs-and-visits-feed-it ()
  (let ((+zoxide-program "zoxide") (+zoxide--last-added nil) (noninteractive nil) started)
    (cl-letf (((symbol-function 'process-lines)
               (lambda (&rest _) '(" 274.0 /home/u/dotfiles" "   6.2 /home/u/dev/minaret")))
              ((symbol-function 'start-process)
               (lambda (&rest args) (push (last args) started))))
      ;; Best first, abbreviated, score shown.
      (let ((process-environment (cons "HOME=/home/u" process-environment)))
        (should (equal (mapcar #'cdr (+zoxide--candidates)) '("/home/u/dotfiles" "/home/u/dev/minaret"))))
      ;; Visits are added once each; remote ones not.
      (let ((default-directory "/tmp/"))
        (+zoxide-add-h) (+zoxide-add-h))
      (should (equal started '(("/tmp/"))))
      (let ((default-directory "/ssh:host:/srv/"))
        (+zoxide-add-h))
      (should (= (length started) 1))
      ;; Picking a directory opens find-file there.
      (let (dir)
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (car (car (+zoxide--candidates)))))
                  ((symbol-function 'call-interactively) (lambda (&rest _) (setq dir default-directory))))
          (+zoxide/find))
        (should (equal dir "/home/u/dotfiles/"))))))

(ert-deftest usage/time-per-kind-and-cancellations ()
  (let* ((+usage-events-file (make-temp-file "usage-events" nil ".eld"))
         (+usage--time (make-hash-table :test #'equal))
         (+usage--cancelled (make-hash-table :test #'equal))
         (+usage--last-time nil) (+usage--last-kind nil)
         (clock 1000.0))
    (unwind-protect
        (cl-letf (((symbol-function 'float-time) (lambda (&rest _) clock)))
          (with-temp-buffer
            (org-mode)
            (let ((this-command 'next-line))
              (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () [?j])))
                (+usage--events-h)          ; starts the clock in org-mode
                (setq clock 1030.0)
                (+usage--events-h)          ; 30 s in org-mode
                (setq clock 2000.0)
                (+usage--events-h))))       ; 970 s: away, not counted
          (should (equal (gethash "org-mode" +usage--time) 30.0))
          ;; C-g after SPC f: that prefix abandoned.
          (let ((this-command 'keyboard-quit))
            (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () (kbd "SPC f C-g"))))
              (+usage--events-h)))
          (should (= (gethash '(prefix . "SPC f") +usage--cancelled) 1))
          ;; A prompt left with C-g: its command cancelled.
          (let ((this-command 'abort-minibuffers) (current-minibuffer-command 'find-file))
            (+usage--minibuffer-exit-h))
          (should (= (gethash '(minibuffer . "find-file") +usage--cancelled) 1))
          ;; Saved and merged across saves.
          (+usage-save-events)
          (puthash "org-mode" 10.0 +usage--time)
          (+usage-save-events)
          (should (equal (alist-get "org-mode" (plist-get (+usage--events-read) :time) nil nil #'equal) 40.0)))
      (delete-file +usage-events-file))))

(defvar vertico-sort-function nil)
(defvar vertico-sort-override-function nil)

(ert-deftest usage/m-x-ranks-what-you-run-here-first ()
  (let ((scores (make-hash-table :test #'equal))
        (vertico-sort-function (lambda (cs) (sort (copy-sequence cs) #'string<))))
    (puthash "org-todo" 5 scores)
    (puthash "org-refile" 9 scores)
    ;; Ranked ones first, highest first; the rest in vertico's order.
    (should (equal (funcall (+usage--mx-sort scores)
                            (list "zap-to-char" "org-todo" "find-file" "org-refile"))
                   '("org-refile" "org-todo" "find-file" "zap-to-char"))))
  ;; Set up only in M-x's minibuffer, from this mode's evidence.
  (with-temp-buffer
    (cl-letf (((symbol-function 'minibuffer-selected-window) #'selected-window)
              ((symbol-function '+usage-anticipations)
               (lambda (_last _mode _n) '((next-line 500 0 500) (forward-word 3 0 3))))
              ((symbol-function '+usage--merged)
               (lambda () '((next-line ("j" . 4000)) (forward-word ("M-x" . 3))))))
      (let ((this-command 'find-file)) (+usage-mx-setup-h))
      (should-not (local-variable-p 'vertico-sort-override-function))
      (let ((this-command 'execute-extended-command)) (+usage-mx-setup-h))
      ;; next-line: run by keys only, so not ranked despite its count.
      (should (equal (funcall vertico-sort-override-function '("abc" "next-line" "forward-word"))
                     '("forward-word" "abc" "next-line"))))))

(load (expand-file-name "+tailscale" test-lisp-dir) nil t)

(ert-deftest tailscale/peers-online-first-with-how-they-are-reached ()
  (cl-letf (((symbol-function '+tailscale--json)
             (lambda (&rest _)
               '(:Peer (:a (:HostName "zeta" :TailscaleIPs ("100.1.1.1") :OS "linux" :Online t
                            :CurAddr "65.1.1.1:41641" :ExitNodeOption t :ExitNode t)
                        :b (:HostName "alpha" :TailscaleIPs ("100.2.2.2") :OS "iOS" :Online nil
                            :LastSeen "2020-01-01T00:00:00Z")
                        :c (:HostName "mid" :TailscaleIPs ("100.3.3.3") :OS "linux" :Online t
                            :CurAddr "" :Relay "fra"))))))
    (let ((rows (mapcar (lambda (r) (append (cadr r) nil)) (+tailscale--rows))))
      ;; Online first, then by name; offline ones say when they were seen.
      (should (equal (mapcar #'car rows) '("mid" "zeta" "alpha")))
      (should (equal (nth 4 (nth 0 rows)) "relay fra"))
      (should (equal (nth 4 (nth 1 rows)) "direct 65.1.1.1:41641"))
      (should (equal (nth 5 (nth 1 rows)) "← in use"))
      (should (string-match-p "days ago" (nth 3 (nth 2 rows)))))))

(load (expand-file-name "+prose" test-lisp-dir) nil t)

(ert-deftest prose/review-is-the-well-formed-report ()
  ;; SPC P v: well-formed's report (its own tests are in lisp/well-formed/test).
  (require 'well-formed-report)
  (should (eq (indirect-function '+prose/review) (indirect-function 'well-formed-report)))
  (with-temp-buffer
    (text-mode)
    (insert "Short one.  " (mapconcat #'identity (make-list 35 "word") " ") ".  It is a apple.")
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (+prose/review))
    (with-current-buffer "*well-formed report*"
      (should (string-match-p "long-sentence +1" (buffer-string)))
      (should (string-match-p "article +1" (buffer-string)))
      (should (string-match-p "Flesch reading ease" (buffer-string))))
    (kill-buffer "*well-formed report*")))

(ert-deftest prose/improve-shows-the-change-and-applies-it ()
  (with-temp-buffer
    (text-mode)
    ;; One space after a sentence, as this config sets it.
    (setq-local sentence-end-double-space nil)
    (insert "First one. This are a sentense with errors. Last one.")
    (goto-char 15)
    (let (asked)
      (cl-letf (((symbol-function 'familiar-request)
                 (lambda (prompt &rest args)
                   (setq asked prompt)
                   (funcall (plist-get args :callback) "This is a sentence with errors." nil)))
                ((symbol-function 'display-buffer) #'ignore))
        (+prose/improve "fix grammar and spelling only"))
      ;; The sentence at point only, with the goal.
      (should (string-match-p "Goal: fix grammar.*\n\nText:\nThis are a sentense with errors\\.\\'" asked))
      (with-current-buffer "*prose improve*"
        (should (string-match-p "Before\nThis are a sentense with errors\\.\n\nAfter\nThis is a sentence with errors\\." (buffer-string)))
        ;; Changed words marked.
        (should (seq-some (lambda (o) (overlay-get o 'face)) (overlays-in (point-min) (point-max))))
        (+prose-improve-apply)))
    (should (equal (buffer-string) "First one. This is a sentence with errors. Last one."))))

(load (expand-file-name "+pide" test-lisp-dir) nil t)

(ert-deftest pide/outline-follows-point-and-caches-the-index ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun alpha () 1)\n\n(defun beta () 2)\n\n(defvar gamma 3)\n")
    (goto-char (point-min))
    (search-forward "beta")
    (let ((+pide--index-cache nil) (calls 0))
      (cl-letf* ((real (symbol-function 'imenu--make-index-alist))
                 ((symbol-function 'imenu--make-index-alist)
                  (lambda (&rest a) (cl-incf calls) (apply real a))))
        (+pide--outline-refresh (current-buffer))
        (+pide--outline-refresh (current-buffer))
        ;; Built once while the text is the same.
        (should (= calls 1))
        (with-current-buffer "*pide outline*"
          (should (string-match-p "alpha" (buffer-string)))
          (should (string-match-p "gamma" (buffer-string)))
          ;; The entry point is in is highlighted.
          (goto-char (point-min))
          (search-forward "beta")
          (should (eq (get-text-property (1- (point)) 'face) 'highlight)))
        (goto-char (point-max))
        (insert "(defun delta () 4)\n")
        (+pide--outline-refresh (current-buffer))
        (should (= calls 2))
        (with-current-buffer "*pide outline*"
          (should (string-match-p "delta" (buffer-string))))))
    (kill-buffer "*pide outline*")))
(ert-deftest completion/minibuffer-cycles-like-popup-other ()
  (let ((+minibuffer--ring (list '(:command a :input "1") '(:command b :input "2")))
        (+minibuffer--leaving nil))
    (defalias 'test-minibuffer--cmd (lambda () (interactive)))
    (with-temp-buffer
      ;; A new minibuffer: remembered first, so C-' goes to the one before.
      (insert "typed")
      (let ((current-minibuffer-command 'test-minibuffer--cmd))
        (should (= (+minibuffer--swap-index 1) 1))
        (should (equal (plist-get (car +minibuffer--ring) :input) "typed"))
        (should-not (+minibuffer--swap-index -1))
        ;; Reopened from position 1: edits kept there, neighbours either side.
        (setq +minibuffer--index 1)
        (erase-buffer) (insert "edited")
        (should (= (+minibuffer--swap-index 1) 2))
        (should (equal (plist-get (nth 1 +minibuffer--ring) :input) "edited"))
        (should (= (+minibuffer--swap-index -1) 0))
        (setq +minibuffer--index 2)
        (should-not (+minibuffer--swap-index 1))))))

(ert-deftest perf/m-x-for-buffer-finds-bound-and-remapped-commands ()
  (let* ((map (make-sparse-keymap))
         (prefix (make-sparse-keymap)))
    (define-key map "a" #'forward-word)
    (define-key prefix "b" #'backward-word)
    (define-key map "c" prefix)
    (define-key map [remap kill-line] #'kill-whole-line)
    (define-key map "m" '(menu-item "x" upcase-word))
    (with-temp-buffer
      (use-local-map map)
      (let ((pred (+perf-command-for-buffer-a)) (buf (current-buffer)))
        (dolist (cmd '(forward-word backward-word kill-whole-line kill-line upcase-word))
          (should (funcall pred cmd buf)))
        (should-not (funcall pred 'downcase-region buf))))))

(ert-deftest persist/new-buffers-are-real ()
  ;; Doom's buffer cycling skipped them: *...* and no file read as unreal.
  (with-temp-buffer
    (rename-buffer "*new*<3>" t)
    (should (+persist-new-buffer-real-p (current-buffer))))
  (with-temp-buffer
    (rename-buffer "*Messages-like*" t)
    (should-not (+persist-new-buffer-real-p (current-buffer)))))

(ert-deftest gh-browse-parse-and-resolve ()
  "Targets parse as GitHub does; links in a file resolve within its repository."
  (load (expand-file-name "+gh-browse" test-lisp-dir) nil t)
  (let ((p (+gh-browse--parse "https://github.com/o/r/tree/v2/docs/#x")))
    (should (equal (list (+gh-place-owner p) (+gh-place-repo p) (+gh-place-ref p) (+gh-place-path p))
                   '("o" "r" "v2" "docs"))))
  (let ((p (+gh-browse--parse "o/r@dev:src/a.el")))
    (should (equal (list (+gh-place-ref p) (+gh-place-path p)) '("dev" "src/a.el"))))
  (should-not (+gh-browse--parse "../README.md" t))
  (let ((here (+gh-place-make :owner "o" :repo "r" :ref "main" :path "docs/guide.md")))
    (should (equal (+gh-place-path (+gh-browse--resolve here "../README.md")) "README.md"))
    (should (equal (+gh-place-path (+gh-browse--resolve here "img/x.png#y")) "docs/img/x.png"))
    (should (equal (+gh-place-path (+gh-browse--resolve here "/LICENSE")) "LICENSE"))
    (should (equal (+gh-place-repo (+gh-browse--resolve here "https://github.com/a/b")) "b"))
    (should (equal (+gh-browse--resolve here "https://github.com/a/b/issues/3") "https://github.com/a/b/issues/3"))
    (should-not (+gh-browse--resolve here "#top"))))

(defmacro test-merge--with-file (text &rest body)
  "Visit a temp file holding TEXT; BODY in its buffer, then clean up."
  (declare (indent 1))
  `(let* ((file (make-temp-file "merge-test" nil ".txt" ,text))
          (buf (find-file-noselect file)))
     (unwind-protect (with-current-buffer buf ,@body)
       (with-current-buffer buf (set-buffer-modified-p nil))
       (kill-buffer buf) (delete-file file))))

(defun test-merge--disk-write (file text)
  "Another program writes FILE (later modtime, so Emacs notices)."
  (let ((coding-system-for-write 'utf-8-unix)) (write-region text nil file nil 'silent))
  (set-file-times file (time-add nil 5)))

(ert-deftest merge/clean-three-way-keeps-both-sides ()
  "Your unsaved edit and the disk's change in other places both survive."
  (load (expand-file-name "+merge" test-lisp-dir) nil t)
  (test-merge--with-file "one\ntwo\nthree\nfour\nfive\n"
    (goto-char (point-min)) (insert "MINE ")
    (test-merge--disk-write file "one\ntwo\nthree\nfour\nfive THEIRS\n")
    (should (+merge--stale-p))
    (should (+merge/disk-into-buffer t))
    (should (equal (buffer-string) "MINE one\ntwo\nthree\nfour\nfive THEIRS\n"))
    (should (buffer-modified-p))
    (should-not (+merge--stale-p))
    ;; Saving no longer asks; the ancestor is now what got saved.
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "asked"))))
      (save-buffer))
    (should (equal (+merge--disk-text file) (buffer-string)))
    (should (equal +merge--ancestor (buffer-string)))))

(ert-deftest merge/save-of-stale-buffer-merges-first ()
  (load (expand-file-name "+merge" test-lisp-dir) nil t)
  (test-merge--with-file "a\nb\nc\nd\n"
    (goto-char (point-max)) (insert "e\n")
    (test-merge--disk-write file "A\nb\nc\nd\n")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "asked"))))
      (save-buffer))
    (should (equal (+merge--disk-text file) "A\nb\nc\nd\ne\n"))))

(ert-deftest merge/first-edit-of-stale-buffer-doesnt-ask ()
  (load (expand-file-name "+merge" test-lisp-dir) nil t)
  (test-merge--with-file "a\nb\nc\nd\n"
    (test-merge--disk-write file "a\nb\nc\nD\n")
    (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) (error "asked")))
              ((symbol-function 'run-at-time) (lambda (_ _ fn) (funcall fn))))
      (+merge-supersession-a #'ignore file)
      (goto-char (point-min)) (insert "X")
      (+merge/disk-into-buffer t))
    (should (equal (buffer-string) "Xa\nb\nc\nD\n"))))

(ert-deftest merge/overlap-goes-to-ediff ()
  (load (expand-file-name "+merge" test-lisp-dir) nil t)
  (test-merge--with-file "a\nb\n"
    (goto-char (point-min)) (delete-char 1) (insert "MINE")
    (test-merge--disk-write file "THEIRS\nb\n")
    (let (called)
      (cl-letf (((symbol-function '+merge--ediff) (lambda (m th anc) (setq called (list m th anc)))))
        (should-not (+merge/disk-into-buffer t)))
      (should (equal called '("MINE\nb\n" "THEIRS\nb\n" "a\nb\n"))))))

(ert-deftest merge/edit-file-goes-through-the-buffer ()
  (load (expand-file-name "+merge" test-lisp-dir) nil t)
  (test-merge--with-file "a\nb\n"
    (should (eq (+merge-edit-file file (lambda () (insert "agent\n"))) 'saved))
    (should (equal (+merge--disk-text file) "agent\na\nb\n"))
    (goto-char (point-max)) (insert "user\n")
    (should (eq (+merge-edit-file file (lambda () (goto-char (point-max)) (insert "agent2\n"))) 'in-buffer))
    (should (equal (buffer-string) "agent\na\nb\nuser\nagent2\n"))
    (should (equal (+merge--disk-text file) "agent\na\nb\n"))))

(ert-deftest suggest/drops-talking-and-stale-suggestions ()
  "Thinking aloud and marker echoes never show; nor replies to changed text."
  (load (expand-file-name "+suggest" test-lisp-dir) nil t)
  (with-temp-buffer
    (insert "Some prose here")
    (+suggest-ask-a)
    (should (equal (car (+suggest-sane-a
                         (list (list " and more." "Wait, the cursor sits right after \"here\"."
                                     "text <endCompletion>" "so the cursorPosition is"))))
                   '(" and more.")))
    ;; The buffer changed while point stayed (a revert, an agent's edit).
    (save-excursion (goto-char (point-min)) (insert "X") (delete-char -1))
    (should-not (car (+suggest-sane-a (list (list " and more.")))))))

(ert-deftest suggest/no-auto-suggestion-mid-line-in-prose ()
  (load (expand-file-name "+suggest" test-lisp-dir) nil t)
  (with-temp-buffer
    (insert "- [ ] If possible\n- [ ] If not")
    (goto-char (point-min)) (forward-line 1)
    (should (+suggest-prose-mid-line-p))          ; column 0 before text
    (goto-char (point-max))
    (should-not (+suggest-prose-mid-line-p))      ; end of line
    (insert ".)") (backward-char 2)
    (should-not (+suggest-prose-mid-line-p))))    ; only closing punctuation

(defmacro test-atuin--with-fake (calls &rest body)
  "BODY with `call-process'/`make-process' for atuin faked; CALLS gets each argv."
  (declare (indent 1))
  `(cl-letf* ((real-call (symbol-function 'call-process))
              ((symbol-function 'executable-find) (lambda (p &rest _) (and (equal p "atuin") "/bin/atuin")))
              ((symbol-function 'call-process)
               (lambda (prog &optional _in dest _disp &rest args)
                 (if (not (equal prog "atuin")) (apply real-call prog _in dest _disp args)
                   (push args ,calls)
                   (when dest
                     (with-current-buffer (if (bufferp dest) dest (current-buffer))
                       (insert (pcase (car args)
                                 ("search" (concat "2026-11-05 06:00:00\t0\t2s\t/tmp\tthinkpad\t1h\tmake test\0"
                                                   "2026-11-05 07:00:00\t2\t140ms\t/srv\tinari\t5m\tnrs\n--flag\0"))
                                 ("history" "01ID\n")
                                 ("uuid" "SESSION\n")
                                 (_ "")))))
                   0)))
              ((symbol-function 'make-process) (lambda (&rest plist) (push (plist-get plist :command) ,calls) nil)))
     ,@body))

(ert-deftest atuin/entries-newest-first-with-everything ()
  (load (expand-file-name "+atuin" test-lisp-dir) nil t)
  (let (calls)
    (test-atuin--with-fake calls
      (let ((entries (+atuin--entries)))
        (should (equal (mapcar (lambda (e) (plist-get e :command)) entries) '("nrs\n--flag" "make test")))
        (should (equal (plist-get (car entries) :exit) 2))
        (should (equal (plist-get (car entries) :host) "inari"))
        (let ((cand (+atuin--candidate (car entries))))
          (should (equal (substring-no-properties cand) "nrs ⏎ --flag"))
          (should (string-match-p "✘2.*140ms.*5m.*/srv.*@inari"
                                  (substring-no-properties (+atuin--annotate cand)))))))))

(ert-deftest atuin/emacs-runs-are-recorded ()
  "compile and M-! go into Atuin: start with the command, end with exit and duration."
  (load (expand-file-name "+atuin" test-lisp-dir) nil t)
  (let (calls (+atuin--session nil) (+atuin-record t) (default-directory "/tmp/"))
    (test-atuin--with-fake calls
      (let ((started (+atuin--start "make test")))
        (should (equal (car started) "01ID"))
        (+atuin--end started 3))
      (should (member '("history" "start" "--author" "emacs" "--" "make test") calls))
      (should (cl-find-if (lambda (c) (and (equal (seq-take c 5) '("atuin" "history" "end" "--exit" "3"))
                                           (equal (car (last c)) "01ID")))
                          calls))
      ;; Only what you typed: an internal shell-command isn't recorded.
      (setq calls nil)
      (let ((this-command 'some-command))
        (+atuin-shell-command-a #'ignore "true"))
      (should-not calls)
      (let ((this-command 'shell-command))
        (+atuin-shell-command-a (lambda (&rest _) 0) "true"))
      (should (member '("history" "start" "--author" "emacs" "--" "true") calls)))))

(ert-deftest atuin/delete-refuses-when-it-would-take-others ()
  (load (expand-file-name "+atuin" test-lisp-dir) nil t)
  (cl-letf (((symbol-function '+atuin--matches) (lambda (_) '("nrs" "nrs --fast")))
            ((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "asked"))))
    (should-error (+atuin-embark-delete (propertize "nrs" '+atuin '(:command "nrs"))) :type 'user-error)))

(ert-deftest atuin/narrows-to-this-project ()
  (load (expand-file-name "+atuin" test-lisp-dir) nil t)
  (dlet ((consult--narrow ?p) (+atuin--project "/home/u/dev/turm/"))
    (should (+atuin--narrow-p (propertize "x" '+atuin '(:dir "/home/u/dev/turm/src" :exit 0))))
    (should (+atuin--narrow-p (propertize "x" '+atuin '(:dir "/home/u/dev/turm" :exit 0))))
    (should-not (+atuin--narrow-p (propertize "x" '+atuin '(:dir "/home/u/dev/turm2" :exit 0))))))

(ert-deftest diagnostics/tint-instead-of-squiggle ()
  (load (expand-file-name "+diagnostics" test-lisp-dir) nil t)
  (should (equal (+diagnostics--blend "#ffffff" "#000000" 0.5) "#7f7f7f"))
  (let ((+diagnostics-style 'tint) (+diagnostics-tint 0.25))
    (unless (facep 'flycheck-error) (make-face 'flycheck-error))
    (cl-letf (((symbol-function '+diagnostics--color)
               (lambda (face _attr fallback) (pcase face ('default "#000000") ('error "#ff0000") (_ fallback)))))
      (+diagnostics-apply-look-h))
    (should (equal (face-attribute (quote flycheck-error) :background) "#3f0000"))
    (should-not (face-attribute 'flycheck-error :underline))))

(ert-deftest diagnostics/calm-shows-suggestions-only-near-point ()
  (load (expand-file-name "+diagnostics" test-lisp-dir) nil t)
  (with-temp-buffer
    (insert "First paragraph here.\n\nSecond paragraph there.\n")
    (let ((near (make-overlay 1 6)) (far (make-overlay 24 30)))
      (dolist (o (list near far)) (overlay-put o 'flycheck-overlay t) (overlay-put o 'category 'flycheck-info-overlay))
      (goto-char 3)
      (+diagnostics-calm-mode 1)
      (should-not (overlay-get near 'face))
      (should (eq (overlay-get far 'face) '+diagnostics-calm))
      (goto-char 30) (+diagnostics-calm-update)
      (should (eq (overlay-get near 'face) '+diagnostics-calm))
      (should-not (overlay-get far 'face))
      (+diagnostics-calm-mode -1)
      (should-not (overlay-get near 'face)))))

(defvar test-diag-fake-mode nil)
(defun test-diag-fake-mode (arg) (setq-local test-diag-fake-mode (> arg 0)))

(ert-deftest diagnostics/pause-in-read-only-buffers ()
  (load (expand-file-name "+diagnostics" test-lisp-dir) nil t)
  (with-temp-buffer
    (let ((+diagnostics-pausable '(test-diag-fake-mode)))
      (test-diag-fake-mode 1)
      (setq buffer-read-only t) (+diagnostics-read-only-h)
      (should-not test-diag-fake-mode)
      (should (equal +diagnostics--paused '(test-diag-fake-mode)))
      (setq buffer-read-only nil) (+diagnostics-read-only-h)
      (should test-diag-fake-mode)
      (should-not +diagnostics--paused))))

(defmacro test-ghfs--with-fake (&rest body)
  "BODY with GitHub faked: o/r on main holds README.md, src/a.el, src/b/."
  `(progn
     (load (expand-file-name "+gh-fs" test-lisp-dir) nil t)
     (let ((+gh-fs--memo (make-hash-table :test #'equal))
           (+gh-fs-cache-directory (make-temp-file "ghfs" t)))
       (cl-letf (((symbol-function '+gh-fs--api)
                  (lambda (path &optional raw-file)
                    (cond
                     (raw-file (make-directory (file-name-directory raw-file) t)
                               (with-temp-file raw-file (insert "(message \"hi\")\n")) raw-file)
                     ((equal path "repos/o/r") '(:default_branch "main" :size 10))
                     ((string-prefix-p "repos/o/r/git/trees/main" path)
                      '(:sha "t0" :tree ((:path "README.md" :type "blob" :size 5 :sha "s1" :mode "100644")
                                         (:path "src" :type "tree" :sha "t1" :mode "040000")
                                         (:path "src/a.el" :type "blob" :size 16 :sha "s2" :mode "100644")
                                         (:path "src/b" :type "tree" :sha "t2" :mode "040000"))))
                     ((string-prefix-p "repos/o/r/commits/" path) '(:commit (:committer (:date "2026-11-01T10:00:00Z"))))
                     (t nil)))))
         ,@body))))

(ert-deftest gh-fs/a-repository-is-a-read-only-directory ()
  (test-ghfs--with-fake
   (should (file-directory-p "/github/o/r"))
   (should (file-directory-p "/github/o/r/src/"))
   (should (file-regular-p "/github/o/r/src/a.el"))
   (should-not (file-exists-p "/github/o/r/nope"))
   (should-not (file-writable-p "/github/o/r/src/a.el"))
   (should (equal (directory-files "/github/o/r/src") '("." ".." "a.el" "b")))
   (should (equal (sort (file-name-all-completions "" "/github/o/r/") #'string<) '("README.md" "src/")))
   (should (= (file-attribute-size (file-attributes "/github/o/r/src/a.el")) 16))
   (should (equal (file-remote-p "/github/o/r/src/a.el" 'host) "o/r"))
   (should-error (write-region "x" nil "/github/o/r/new.txt") :type 'file-error)
   (with-temp-buffer
     (insert-file-contents "/github/o/r/src/a.el")
     (should (equal (buffer-string) "(message \"hi\")\n")))
   (let ((pr (project-current nil "/github/o/r/src/")))
     (should (equal (project-root pr) "/github/o/r/"))
     (should (equal (project-files pr) '("/github/o/r/README.md" "/github/o/r/src/a.el"))))
   ;; The same tree for a ref given explicitly.
   (should (file-regular-p "/github/o/r@main/README.md"))
   ;; TRAMP's spelling: /github:OWNER/REPO/…, the same file.
   (should (file-regular-p "/github:o/r/src/a.el"))
   (should (file-regular-p "/github:o/r@main/README.md"))
   (should (equal (directory-files "/github:o/r/src") '("." ".." "a.el" "b")))
   (should (equal (file-truename "/github:o/r/src/a.el") "/github/o/r/src/a.el"))
   (should (eq (find-file-name-handler "/github:o/r/x" 'file-exists-p) '+gh-fs-handler))))

(ert-deftest gh-browse/visits-and-report-counts ()
  (load (expand-file-name "+gh-browse" test-lisp-dir) nil t)
  (let ((+gh-browse-visits-file (make-temp-file "visits" nil ".eld")))
    (+gh-browse-note 'file :repo "o/r" :path "a.el")
    (+gh-browse-note 'file :repo "o/r" :path "b.el")
    (+gh-browse-note 'profile :user "u")
    (let ((v (+gh-browse--visits)))
      (should (= (length v) 3))
      (should (equal (car (+gh--count (lambda (x) (plist-get x :repo)) v)) '("o/r" . 2)))
      (should (equal (+gh--count (lambda (x) (file-name-extension (or (plist-get x :path) "")))  v) '(("el" . 2)))))
    (delete-file +gh-browse-visits-file)))

(ert-deftest org-babel/results-ending-in-a-blank-line-convert ()
  "Org's table conversion of output ending in a blank line (gh --help)."
  (require 'org)
  (load (expand-file-name "+org-babel" test-lisp-dir) nil t)
  (require 'org-table)
  (dolist (text '("A B\n\n" "A B\nC D\n\n" "Usage:  gh <command>\n\nCORE  auth\n\n\n" "A B\n" ""))
    (with-temp-buffer
      (insert text)
      (should-not (condition-case e (progn (org-table-convert-region (point-min) (point-max) 'babel-auto) nil)
                    (error e))))))

(ert-deftest gh-cli/commands-and-flags-come-from-gh-help ()
  (load (expand-file-name "+gh-browse" test-lisp-dir) nil t)
  (load (expand-file-name "+gh-cli" test-lisp-dir) nil t)
  (cl-letf (((symbol-function '+gh-cli--help-lines)
             (lambda (args)
               (split-string
                (pcase args
                  ('nil "CORE COMMANDS\n  issue:       Manage issues\n  pr:          Manage pull requests\n\nFLAGS\n  --help")
                  ('("issue") "GENERAL COMMANDS\n  create:     Create a new issue\n  list:       List issues\n\nFLAGS\n")
                  ('("pr") "AVAILABLE COMMANDS\n  merge:      Merge a pull request\n")
                  ('("issue" "create") "FLAGS\n  -t, --title string   Supply a title\n  -R, --repo [HOST/]OWNER/REPO   Select another repository\n      --web            Open the browser\n")
                  (_ ""))
                "\n"))))
    (should (equal (mapcar #'car (+gh-cli--commands-in nil)) '("issue" "pr")))
    (should (equal (+gh-cli--commands-in '("issue")) '(("create" . "Create a new issue") ("list" . "List issues"))))
    (should (equal (mapcar #'car (+gh-cli--flags "issue create")) '("--title" "--repo" "--web")))))

(ert-deftest gh-cli/compose-sends-title-and-body ()
  (load (expand-file-name "+gh-cli" test-lisp-dir) nil t)
  (let (sent)
    (save-window-excursion
      (with-current-buffer (+gh-compose "*test compose*" "Test" (lambda (title body) (setq sent (list title body))) t)
        (insert "The title\n\nFirst paragraph.\n")
        (+gh-compose-send)))
    (should (equal sent '("The title" "First paragraph.")))
    (should-not (get-buffer "*test compose*"))))

(ert-deftest hunks/unstage-only-the-hunk-at-point ()
  "Two staged changes; unstaging at the second leaves the first staged."
  (load (expand-file-name "+hunks" test-lisp-dir) nil t)
  (let* ((root (make-temp-file "hunks" t)) (default-directory root)
         (file (expand-file-name "f.txt" root)))
    (call-process "git" nil nil nil "init" "-q")
    (with-temp-file file (dotimes (i 20) (insert (format "line %d\n" i))))
    (call-process "git" nil nil nil "add" ".")
    (call-process "git" nil nil nil "-c" "user.email=x@y" "-c" "user.name=x" "commit" "-qm" "init")
    (with-temp-file file (dotimes (i 20) (insert (format "line %d%s\n" i (if (memq i '(2 15)) " CHANGED" "")))))
    (call-process "git" nil nil nil "add" ".")
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min)) (forward-line 15)
      (+hunks/unstage)
      (kill-buffer))
    (let ((staged (shell-command-to-string "git diff --cached -U0 | grep '^+line'"))
          (unstaged (shell-command-to-string "git diff -U0 | grep '^+line'")))
      (should (equal (string-trim staged) "+line 2 CHANGED"))
      (should (equal (string-trim unstaged) "+line 15 CHANGED")))
    (delete-directory root t)))

(ert-deftest gh-fs/completion-never-waits ()
  "In the minibuffer, owners and repositories come from the cache or arrive
in the background; nothing synchronous."
  (load (expand-file-name "+gh-fs" test-lisp-dir) nil t)
  (let ((+gh-fs--memo (make-hash-table :test #'equal))
        (+gh-fs--owners (make-hash-table :test #'equal))
        (+gh-fs--loading (make-hash-table :test #'equal))
        (+gh-fs-cache-directory (make-temp-file "ghfs" t))
        (pending nil))
    (puthash "cypl0x" 'you +gh-fs--owners)
    (puthash "sindresorhus" 'starred +gh-fs--owners)
    (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t))
              ((symbol-function '+gh-fs--api) (lambda (&rest _) (error "Synchronous call in the minibuffer")))
              ((symbol-function '+gh-fs--async-api) (lambda (path cb) (push (cons path cb) pending))))
      (should (equal (+gh-fs--children "/github:") '("cypl0x" "sindresorhus")))
      (should (equal (file-name-all-completions "si" "/github:") '("sindresorhus/")))
      ;; Repositories: nothing yet, a request in flight …
      (should-not (+gh-fs--children "/github:sindresorhus/"))
      (should (string-match-p "users/sindresorhus/repos" (caar pending)))
      ;; … then they arrive.
      (funcall (cdar pending) '((:name "awesome") (:name "ky")))
      (should (equal (+gh-fs--children "/github:sindresorhus/") '("awesome" "ky")))
      (should (equal (file-name-all-completions "aw" "/github:sindresorhus/") '("awesome/"))))))

(ert-deftest gh-fs/github-completes-like-a-tramp-method ()
  "\"/gi\" offers \"/github:\" next to TRAMP's methods."
  (require 'tramp)
  (load (expand-file-name "+gh-fs" test-lisp-dir) nil t)
  (should (member "/github:" (tramp-get-completion-methods "gi")))
  (should-not (member "/github:" (tramp-get-completion-methods "ss")))
  (should (member "/ssh:" (tramp-get-completion-methods "ss"))))

(ert-deftest perf/old-kills-are-archived-not-lost ()
  (load (expand-file-name "+perf" test-lisp-dir) nil t)
  (let ((+perf-kill-keep 2)
        (+perf-kill-archive-file (make-temp-file "kills" nil ".eld"))
        (+perf--kill-archived nil))
    (should (equal (+perf-kills-to-persist '("e" "d" "c" "b" "a")) '("e" "d")))
    (should (equal (+perf--kill-archive-read) '("a" "b" "c")))
    ;; Saving again: nothing archived twice; newer overflow appended.
    (+perf-kills-to-persist '("f" "e" "d" "c" "b" "a"))
    (should (equal (+perf--kill-archive-read) '("a" "b" "c" "d")))
    (delete-file +perf-kill-archive-file)))

(ert-deftest dired/ages-read-like-speech ()
  (load (expand-file-name "+dired" test-lisp-dir) nil t)
  (let ((now (encode-time '(0 0 12 5 11 2026 nil nil 0))))
    (cl-flet ((ago (secs) (+dired-age-string (time-subtract now secs) now)))
      (should (equal (ago 30) "just now"))
      (should (equal (ago 600) "10min ago"))
      (should (equal (ago (+ 7200 780)) "2h 13min ago"))
      (should (equal (ago 7200) "2h ago"))
      (should (equal (ago (+ (* 3 86400) (* 4 3600))) "3d 4h ago"))
      (should (equal (ago (* 400 86400)) "1y 1mo ago"))
      (should (equal (ago -300) "in 5min")))))

(ert-deftest attention/reuses-an-idle-agent-or-asks ()
  (load (expand-file-name "+attention" test-lisp-dir) nil t)
  (let ((a (generate-new-buffer "agent a")) (b (generate-new-buffer "agent b")))
    (unwind-protect
        (progn
          (with-current-buffer a (setq-local shell-maker--busy nil))
          (with-current-buffer b (setq-local shell-maker--busy nil))
          ;; The last attention agent, idle: used without asking.
          (let ((+attention--agent a))
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) (error "asked"))))
              (should (eq (+attention--agent-for-job) a))))
          ;; Busy: another idle agent in ~/dotfiles, only if you say so.
          (with-current-buffer a (setq-local shell-maker--busy t))
          (let ((+attention--agent a))
            (cl-letf (((symbol-function 'agent-shell-project-buffers) (lambda (&rest _) (list a b)))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
              (should (eq (+attention--agent-for-job) b)))
            (cl-letf (((symbol-function 'agent-shell-project-buffers) (lambda (&rest _) (list a b)))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
              (should-not (+attention--agent-for-job)))))
      (kill-buffer a) (kill-buffer b))))

(ert-deftest attention/last-freeze-goes-to-the-agent-with-its-profile ()
  (require 'profiler)
  (load (expand-file-name "+attention" test-lisp-dir) nil t)
  (let* ((+perf-freeze-dir (make-temp-file "freezes" t))
         (+attention-dir (make-temp-file "attention" t))
         (txt (expand-file-name "freeze-20261105-085231.txt" +perf-freeze-dir))
         handed)
    (with-temp-file txt (insert "Frozen for 85 s, recovered 2026-11-05 08:52:31\n\nLive processes:\n  gh api …\n"))
    (with-temp-file (concat (file-name-sans-extension txt) ".prof") (insert "profile"))
    (cl-letf (((symbol-function '+attention-profile-file-text) (lambda (_) "  41.8%  redisplay_internal\n"))
              ((symbol-function '+attention--hand-off) (lambda (complaint file) (setq handed (list complaint file)))))
      (+attention/last-freeze))
    (should (string-match-p "Frozen for 85 s" (car handed)))
    (with-temp-buffer
      (insert-file-contents (cadr handed))
      (should (search-forward "Live processes" nil t))
      (should (search-forward "CPU profile during the freeze" nil t)))))

(ert-deftest echo/ping-and-rule-explanations-fit-the-echo-area ()
  (load (expand-file-name "+tailscale" test-lisp-dir) nil t)
  (should (equal (+tailscale--ping-summary
                  "inari" "pong from inari (100.64.0.2) via DERP(fra) in 31ms\npong from inari (100.64.0.2) via 65.1.2.3:41641 in 9ms\npong from inari (100.64.0.2) via 65.1.2.3:41641 in 11ms\n")
                 "inari: direct (65.1.2.3:41641), 3 pongs, 9 / 17 / 31 ms (min/avg/max)"))
  (should (string-prefix-p "inari: no pong" (+tailscale--ping-summary "inari" "timeout\n")))
  (require 'well-formed)
  (let* ((rule (car well-formed--rules))
         (gist (substring-no-properties (well-formed--rule-gist rule))))
    (should (string-prefix-p (symbol-name (well-formed-rule-id rule)) gist))
    (should (<= (length (split-string gist "\n")) 5))))

(ert-deftest usage/records-the-command-that-ran-not-what-it-set ()
  "kill-region rewrites this-command; M-DEL must count as backward-kill-word."
  (load (expand-file-name "+usage" test-lisp-dir) nil t)
  (let ((+usage--counts (make-hash-table :test #'eq))
        (+usage--pairs (make-hash-table :test #'equal))
        (+usage--modes (make-hash-table :test #'equal))
        (+usage--last nil) (+usage--recent nil) (+usage-coach nil))
    (let ((real-this-command 'backward-kill-word) (this-command 'kill-region))
      (cl-letf (((symbol-function 'this-command-keys-vector) (lambda () (kbd "M-DEL"))))
        (+usage--record-h)))
    (should (gethash 'backward-kill-word +usage--counts))
    (should-not (gethash 'kill-region +usage--counts))
    ;; Old data is moved over.
    (puthash 'kill-region (let ((h (make-hash-table :test #'equal))) (puthash "M-DEL" 1226 h) (puthash "C-w" 1 h) h)
             +usage--counts)
    (+usage-fix-kill-region-counts)
    (should (= (gethash "M-DEL" (gethash 'backward-kill-word +usage--counts)) 1227))
    (should (equal (gethash "C-w" (gethash 'kill-region +usage--counts)) 1))))

(ert-deftest org-lint/nine-more-rules-fire-and-stay-quiet ()
  (require 'org-lint)
  (load (expand-file-name "+org-lint" test-lisp-dir) nil t)
  (cl-flet ((n (rule text)
              (with-temp-buffer
                (org-mode) (insert text) (goto-char (point-min))
                (length (funcall rule (org-element-parse-buffer))))))
    (should (= 1 (n #'+org-lint-hard-tabs "a\tb\n")))
    (should (= 0 (n #'+org-lint-hard-tabs "#+begin_src makefile\nall:\n\tmake\n#+end_src\n")))
    (should (= 1 (n #'+org-lint-table-alignment "| a | b |\n| long cell | c |\n")))
    (should (= 0 (n #'+org-lint-table-alignment "| a         | b |\n| long cell | c |\n")))
    (should (= 1 (n #'+org-lint-ordered-delimiters "1. one\n2) two\n")))
    (should (= 0 (n #'+org-lint-ordered-delimiters "1. one\n2. two\n")))
    (should (= 1 (n #'+org-lint-bare-url "See https://example.org now.\n")))
    (should (= 0 (n #'+org-lint-bare-url "See [[https://example.org][the example]].\n")))
    (should (= 2 (n #'+org-lint-empty-link "[[]] and [[https://x.org][ ]]\n")))
    (should (= 0 (n #'+org-lint-empty-link "[[https://x.org][x]]\n")))
    (should (= 1 (n #'+org-lint-image-alt "[[file:a.png]]\n")))
    (should (= 0 (n #'+org-lint-image-alt "#+caption: A chart\n[[file:a.png]]\n")))
    (should (= 2 (n #'+org-lint-emphasis-spaces "Use = foo= and ~bar ~ here.\n")))
    (should (= 0 (n #'+org-lint-emphasis-spaces "Use =foo= and ~bar~; a = b and c ~ d.\n")))
    (should (= 1 (n #'+org-lint-final-newline "text")))
    (should (= 0 (n #'+org-lint-final-newline "text\n")))
    (should (= 1 (n #'+org-lint-several-titles "#+title: A\n#+title: B\n")))
    (should (= 0 (n #'+org-lint-several-titles "#+title: A\n")))))

(ert-deftest neomacs/zoom-by-face-height ()
  (load (expand-file-name "+neomacs" test-lisp-dir) nil t)
  (let ((+neomacs--initial-height nil)
        (orig (face-attribute 'default :height)))
    (unwind-protect
        (progn
          (set-face-attribute 'default nil :height 140)
          (+neomacs-adjust-font-size-a #'ignore 2)
          (should (= (face-attribute 'default :height) 160))
          (+neomacs-adjust-font-size-a #'ignore 3)
          (should (= (face-attribute 'default :height) 190))
          (+neomacs-adjust-font-size-a #'ignore nil)
          (should (= (face-attribute 'default :height) 140))
          (+neomacs-adjust-font-size-a #'ignore 12 t)
          (should (= (face-attribute 'default :height) 120)))
      (set-face-attribute 'default nil :height orig))))

(ert-deftest system/views-read-this-machine ()
  "Each view's rows come from this machine (skipped where a tool is absent)."
  (load (expand-file-name "+system" test-lisp-dir) nil t)
  (when (file-directory-p "/sys/bus/usb/devices")
    (should (listp (+system--usb-rows))))
  (when (file-directory-p "/sys/class/hwmon")
    (dolist (row (+system--sensor-rows))
      (should (string-match-p "°C\\|rpm" (substring-no-properties (aref (cadr row) 2))))))
  (when (executable-find "lsmod")
    (should (cl-every (lambda (r) (stringp (car r))) (+system--module-rows))))
  (when (executable-find "getent")
    (should (assoc "root" (+system--user-rows))))
  (when (executable-find "ss")
    (should (listp (+system--port-rows)))))

(ert-deftest neomacs/one-gesture-one-scroll ()
  "Queued scroll events of one direction fold into the first; others wait."
  (load (expand-file-name "+neomacs" test-lisp-dir) nil t)
  (let* ((pos (list (selected-window) 1 '(0 . 0) 0))
         (ev (lambda (dir dy) (list dir pos 1 1 (cons 0.0 dy))))
         (unread-command-events (list (funcall ev 'wheel-down 12.0) (funcall ev 'wheel-down 8.0)
                                      ?x (funcall ev 'wheel-down 5.0))))
    (let ((merged (car (+neomacs-coalesce-wheel-a (list (funcall ev 'wheel-down 10.0))))))
      (should (equal (nth 4 merged) '(0.0 . 30.0)))
      (should (= (nth 3 merged) 3))
      ;; The key press and what follows it are left for later.
      (should (equal (car unread-command-events) ?x))
      (should (= (length unread-command-events) 2)))))
