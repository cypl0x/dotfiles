;;; lisp/+gh-fs.el --- GitHub as a read-only file system: /github/OWNER/REPO/... -*- lexical-binding: t; -*-
;;
;; Every repository on GitHub is a directory under /github/, so everything
;; that works on files works on them: SPC f f, SPC . , dired and dirvish,
;; consult-line, imenu, project commands (SPC p f lists the whole repository),
;; copying a file out (dired C), the major modes, images, ...
;;
;;   /github/                       you and your organizations
;;   /github/OWNER/                 OWNER's repositories, recently pushed first
;;   /github/OWNER/REPO/            the default branch
;;   /github/OWNER/REPO@REF/        any branch, tag or commit
;;   /github/OWNER/REPO@REF/a/b.el  a file, fetched when you open it
;;
;; As little as possible goes over the wire: one call lists a repository's
;; whole tree (every directory below it, sizes included); a file's content
;; is fetched by its blob hash when opened and kept on disk under
;; `+gh-fs-cache-directory', so the same content is never fetched twice and
;; never goes stale.  All through `gh' (your login, 5000 calls an hour).
;;
;; Read-only: buffers come up with the lock (diagnostics pause there).
;; Processes started from such a directory run locally, in a temp dir.
;; No colon in the path, so TRAMP never claims it.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'project)
(require 'files-x)                      ; dired asks remote files for connection-local values
(declare-function ls-lisp--insert-directory "ls-lisp" (file switches wildcard full-directory-p))

(defvar +gh-fs-root "/github"
  "Where GitHub appears in the file system (no trailing slash).")

(defvar +gh-fs-cache-directory (expand-file-name "gh-fs/" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Content-addressed cache of file contents (blob hashes).")

(defvar +gh-fs--regexp)
(defvar +gh-fs--memo (make-hash-table :test #'equal)
  "API answers for this session: repositories, trees, listings.")

;;;; The API

(defun +gh-fs--run (&rest args)
  "Run gh with ARGS, its output into the current buffer: (EXIT . STDERR).
Like `call-process', but waiting with `accept-process-output': timers
run meanwhile, so the echo area can say what Emacs waits for
\(lisp/+wait.el); C-g stops it and the process."
  (let* ((default-directory temporary-file-directory)
         (err (generate-new-buffer " *gh-fs-err*"))
         (stderr (make-pipe-process :name "gh-fs-err" :buffer err :noquery t :sentinel #'ignore))
         (proc (make-process :name "gh-fs-sync" :buffer (current-buffer) :command (cons "gh" args)
                             :connection-type 'pipe :noquery t :stderr stderr :sentinel #'ignore)))
    (unwind-protect
        (progn
          ;; Short timeouts, not a bare wait: that sometimes ran no timers
          ;; until the process ended (seen in the test suite).
          (while (process-live-p proc) (accept-process-output proc 0.1))
          (while (accept-process-output proc 0))
          (while (accept-process-output stderr 0))
          (cons (process-exit-status proc)
                (with-current-buffer err (buffer-string))))
      (delete-process proc)
      (delete-process stderr)
      (kill-buffer err))))

(defun +gh-fs--api (path &optional raw-file)
  "GET PATH with gh; parsed JSON (cached for the session).
With RAW-FILE, write the raw body to that file and return it."
  (if raw-file
      (let ((coding-system-for-read 'binary))
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (pcase-let ((`(,exit . ,stderr) (+gh-fs--run "api" "-H" "Accept: application/vnd.github.raw" path)))
            (unless (zerop exit)
              (error "GitHub: %s" (string-trim (concat (buffer-string) stderr)))))
          (make-directory (file-name-directory raw-file) t)
          (let ((coding-system-for-write 'binary)) (write-region nil nil raw-file nil 'silent))
          raw-file))
    (let ((hit (gethash path +gh-fs--memo :none)))
      (if (not (eq hit :none)) hit
        (puthash path
                 (with-temp-buffer
                   (let ((coding-system-for-read 'utf-8))
                     (if (zerop (car (+gh-fs--run "api" path)))
                         (progn (goto-char (point-min))
                                (json-parse-buffer :object-type 'plist :array-type 'list
                                                   :null-object nil :false-object nil))
                       nil)))
                 +gh-fs--memo)))))

(defun +gh-fs--paginate (path)
  "All pages of a list endpoint PATH (100 at a time, at most 300)."
  (cl-loop for page from 1 to 3
           for items = (+gh-fs--api (format "%s%sper_page=100&page=%d" path (if (string-search "?" path) "&" "?") page))
           append items
           while (= (length items) 100)))

(defun +gh-fs--me () (plist-get (+gh-fs--api "user") :login))

;;;; Paths

(cl-defstruct (+gh-fs-path (:constructor +gh-fs-path-make) (:copier nil)) owner repo ref path)

(defun +gh-fs--parse (file)
  "FILE under `+gh-fs-root' as a `+gh-fs-path' (nil parts where absent)."
  (let* ((rel (replace-regexp-in-string (concat "\\`" (regexp-quote +gh-fs-root) "[:/]?") ""
                                   (directory-file-name (expand-file-name file))))
         (parts (split-string rel "/" t))
         (repo-ref (nth 1 parts)))
    (+gh-fs-path-make :owner (nth 0 parts)
                      :repo (and repo-ref (car (split-string repo-ref "@")))
                      :ref (and repo-ref (string-search "@" repo-ref)
                                (substring repo-ref (1+ (string-search "@" repo-ref))))
                      :path (string-join (nthcdr 2 parts) "/"))))

(defun +gh-fs-file (owner repo &optional ref path)
  "The file name of PATH in OWNER/REPO at REF (nil: the default branch)."
  (concat +gh-fs-root "/" owner "/" repo (if ref (concat "@" ref) "")
          (if (and path (not (string-empty-p path))) (concat "/" path) "")))

(defun +gh-fs--ref (p)
  "P's ref, or its repository's default branch."
  (or (+gh-fs-path-ref p)
      (plist-get (+gh-fs--api (format "repos/%s/%s" (+gh-fs-path-owner p) (+gh-fs-path-repo p))) :default_branch)))

;;;; Trees

(defun +gh-fs--tree (p)
  "P's repository tree at its ref: a hash table PATH → (TYPE SIZE SHA MODE),
with \"\" the root; plus children lists under (:children . DIR).  nil if none."
  (let* ((ref (+gh-fs--ref p))
         (key (list :tree (+gh-fs-path-owner p) (+gh-fs-path-repo p) ref)))
    (or (gethash key +gh-fs--memo)
        (when-let* ((ref)
                    (answer (+gh-fs--api (format "repos/%s/%s/git/trees/%s?recursive=1"
                                                 (+gh-fs-path-owner p) (+gh-fs-path-repo p)
                                                 (url-hexify-string ref)))))
          (let ((table (make-hash-table :test #'equal)))
            (puthash "" (list 'dir 0 (plist-get answer :sha) "040000") table)
            (dolist (e (plist-get answer :tree))
              (let* ((path (plist-get e :path))
                     (dir (or (file-name-directory path) "")))
                (puthash path (list (pcase (plist-get e :type) ("tree" 'dir) ("commit" 'dir) (_ 'file))
                                    (or (plist-get e :size) 0) (plist-get e :sha) (plist-get e :mode))
                         table)
                (push (file-name-nondirectory path)
                      (gethash (cons :children (directory-file-name dir)) table))))
            (puthash key table +gh-fs--memo))))))

(defun +gh-fs--commit-time (p ref)
  (or (ignore-errors
        (time-convert (date-to-time (plist-get (plist-get (plist-get (+gh-fs--api (format "repos/%s/%s/commits/%s" (+gh-fs-path-owner p)
                                                                            (+gh-fs-path-repo p) (url-hexify-string ref)))
                                                       :commit)
                                            :committer)
                                 :date)) 'list))
      (current-time)))

;;;; What a path is

;;;; Completion that never waits: owners and repositories

;; SPC f f /github:… completes owners and repositories without freezing:
;; owners you know (you, your organizations, people you follow, owners of
;; repositories you starred or visited) come from a cache on disk, refreshed
;; in the background; a name not among them is searched on GitHub in the
;; background as you type; an owner's repositories and a repository's tree
;; arrive in the background too, and the candidates fill in as they come.

(defvar +gh-fs--owners (make-hash-table :test #'equal) "Login → why it is known.")
(defvar +gh-fs--searched (make-hash-table :test #'equal) "Prefixes already searched.")
(defvar +gh-fs--loading (make-hash-table :test #'equal) "Keys being fetched in the background.")
(defvar +gh-fs--search-timer nil)
(defvar vertico--input)
(declare-function vertico--exhibit "ext:vertico" ())

(defun +gh-fs--owners-file () (expand-file-name "owners.eld" +gh-fs-cache-directory))

(defun +gh-fs--owners-load ()
  (when (file-readable-p (+gh-fs--owners-file))
    (dolist (o (with-temp-buffer (insert-file-contents (+gh-fs--owners-file)) (ignore-errors (read (current-buffer)))))
      (puthash (car o) (cdr o) +gh-fs--owners))))

(defun +gh-fs--owners-save ()
  (make-directory +gh-fs-cache-directory t)
  (let (all) (maphash (lambda (k v) (push (cons k v) all)) +gh-fs--owners)
       (with-temp-file (+gh-fs--owners-file) (prin1 all (current-buffer)))))

(defun +gh-fs--note-owners (logins why)
  (let ((new nil))
    (dolist (l logins) (when (and l (not (gethash l +gh-fs--owners))) (puthash l why +gh-fs--owners) (setq new t)))
    (when new (+gh-fs--owners-save) (+gh-fs--refresh-completion))))

(defun +gh-fs--async-api (path callback)
  "GET PATH with gh in the background; CALLBACK gets the parsed JSON."
  (let ((buf (generate-new-buffer " *gh-fs*"))
        (default-directory temporary-file-directory))
    (make-process :name "gh-fs" :buffer buf :command (list "gh" "api" path) :noquery t
                  :connection-type 'pipe
                  :stderr (make-pipe-process :name "gh-fs-stderr" :buffer nil :noquery t :sentinel #'ignore)
                  :sentinel (lambda (proc _)
                              (unless (process-live-p proc)
                                (let ((json (and (zerop (process-exit-status proc))
                                                 (with-current-buffer buf
                                                   (goto-char (point-min))
                                                   (ignore-errors
                                                     (json-parse-buffer :object-type 'plist :array-type 'list
                                                                        :null-object nil :false-object nil))))))
                                  (kill-buffer buf)
                                  (when json (funcall callback json))))))))

(defun +gh-fs--refresh-completion ()
  "Show new candidates in the minibuffer if it is completing a /github name."
  (when-let* ((win (active-minibuffer-window)))
    (with-current-buffer (window-buffer win)
      (when (and (string-match-p +gh-fs--regexp (minibuffer-contents-no-properties))
                 (boundp 'vertico--input) (fboundp 'vertico--exhibit))
        (setq vertico--input t)
        (with-selected-window win (vertico--exhibit))))))

(defun +gh-fs-refresh-owners ()
  "Learn owners in the background: you, your organizations, people you
follow, owners of repositories you starred."
  (interactive)
  (+gh-fs--async-api "user" (lambda (u) (puthash "user" u +gh-fs--memo) (+gh-fs--note-owners (list (plist-get u :login)) 'you)))
  (+gh-fs--async-api "user/orgs" (lambda (os) (+gh-fs--note-owners (mapcar (lambda (o) (plist-get o :login)) os) 'org)))
  (+gh-fs--async-api "user/following?per_page=100"
                     (lambda (us) (+gh-fs--note-owners (mapcar (lambda (u) (plist-get u :login)) us) 'following)))
  (+gh-fs--async-api "user/starred?per_page=100"
                     (lambda (rs) (+gh-fs--note-owners (mapcar (lambda (r) (plist-get (plist-get r :owner) :login)) rs) 'starred)))
  (when (fboundp '+gh-browse--visits)
    (+gh-fs--note-owners (mapcar (lambda (v) (or (plist-get v :user) (car (split-string (or (plist-get v :repo) "") "/" t))))
                                 (funcall '+gh-browse--visits))
                         'visited)))

(defun +gh-fs--search-owners (prefix)
  "Search GitHub for logins starting with PREFIX, in the background."
  (unless (gethash prefix +gh-fs--searched)
    (puthash prefix t +gh-fs--searched)
    (when (timerp +gh-fs--search-timer) (cancel-timer +gh-fs--search-timer))
    (setq +gh-fs--search-timer
          (run-with-idle-timer
           0.3 nil
           (lambda ()
             (+gh-fs--async-api (format "search/users?q=%s+in:login&per_page=20" (url-hexify-string prefix))
                                (lambda (r) (+gh-fs--note-owners (mapcar (lambda (u) (plist-get u :login)) (plist-get r :items))
                                                                 'found))))))))

(defun +gh-fs--note-repo (owner r)
  "Keep what OWNER's repository listing says about R (push date, size,
default branch), so its directory needs no request of its own; its name."
  (let ((name (plist-get r :name)))
    (puthash (list :repo-meta owner name)
             (list (ignore-errors (time-convert (date-to-time (plist-get r :pushed_at)) 'list))
                   (* 1024 (or (plist-get r :size) 0)))
             +gh-fs--memo)
    (when-let* ((branch (plist-get r :default_branch)))
      (unless (gethash (format "repos/%s/%s" owner name) +gh-fs--memo)
        (puthash (format "repos/%s/%s" owner name) (list :default_branch branch) +gh-fs--memo)))
    name))

(defun +gh-fs--owner-repos (owner)
  "OWNER's repository names, or what has arrived of them so far (a fetch
starts in the background; in the minibuffer it never waits)."
  (let ((key (list :repos owner)))
    (or (gethash key +gh-fs--memo)
        (if (not (minibufferp))
            (puthash key (mapcar (lambda (r) (+gh-fs--note-repo owner r))
                                 (+gh-fs--paginate (if (equal owner (plist-get (gethash "user" +gh-fs--memo) :login))
                                                       "user/repos?affiliation=owner&sort=pushed"
                                                     (format "users/%s/repos?sort=pushed" owner))))
                     +gh-fs--memo)
          (unless (gethash key +gh-fs--loading)
            (puthash key t +gh-fs--loading)
            (let ((acc nil))
              (cl-labels ((page (n)
                            (+gh-fs--async-api
                             (format "users/%s/repos?sort=pushed&per_page=100&page=%d" owner n)
                             (lambda (rs)
                               (setq acc (append acc (mapcar (lambda (r) (+gh-fs--note-repo owner r)) rs)))
                               (puthash (list :partial owner) acc +gh-fs--memo)
                               (+gh-fs--refresh-completion)
                               (if (and (= (length rs) 100) (< n 10)) (page (1+ n))
                                 (puthash key acc +gh-fs--memo)
                                 (remhash key +gh-fs--loading))))))
                (page 1))))
          (gethash (list :partial owner) +gh-fs--memo)))))

(defun +gh-fs--tree-soon (p)
  "P's tree if known; else nil now and fetched in the background (in the
minibuffer), or right away (elsewhere)."
  (let* ((owner (+gh-fs-path-owner p)) (repo (+gh-fs-path-repo p))
         (info-path (format "repos/%s/%s" owner repo)))
    (if (or (not (minibufferp))
            (and (or (+gh-fs-path-ref p) (gethash info-path +gh-fs--memo))
                 (gethash (format "repos/%s/%s/git/trees/%s?recursive=1" owner repo
                                  (url-hexify-string (+gh-fs--ref p)))
                          +gh-fs--memo)))
        (+gh-fs--tree p)
      (let ((key (list :tree-soon owner repo (+gh-fs-path-ref p))))
        (unless (gethash key +gh-fs--loading)
          (puthash key t +gh-fs--loading)
          (cl-labels ((tree (ref)
                        (let ((path (format "repos/%s/%s/git/trees/%s?recursive=1" owner repo (url-hexify-string ref))))
                          (+gh-fs--async-api path (lambda (answer)
                                                    (puthash path answer +gh-fs--memo)
                                                    (remhash key +gh-fs--loading)
                                                    (+gh-fs--refresh-completion))))))
            (if (+gh-fs-path-ref p) (tree (+gh-fs-path-ref p))
              (+gh-fs--async-api info-path (lambda (info) (puthash info-path info +gh-fs--memo)
                                             (tree (plist-get info :default_branch)))))))
        nil))))

(defun +gh-fs--known-owner-p (owner)
  (or (gethash owner +gh-fs--owners) (gethash (list :repos owner) +gh-fs--memo)))

(defun +gh-fs--entry (file &optional with-mtime)
  "What FILE is: (TYPE SIZE SHA MODE MTIME), or nil if it doesn't exist.
Owners and repositories already listed answer without a request; MTIME
\(the commit date, one more request) only WITH-MTIME."
  (let ((p (+gh-fs--parse file)))
    (cond
     ((null (+gh-fs-path-owner p)) (list 'dir 0 nil "040000" nil))
     ((string-prefix-p "." (+gh-fs-path-owner p)) nil)   ; no login starts with "." (VC probes: .git, .svn)
     ((null (+gh-fs-path-repo p))
      (when (or (+gh-fs--known-owner-p (+gh-fs-path-owner p))
                (and (not (minibufferp)) (+gh-fs--api (format "users/%s" (+gh-fs-path-owner p)))))
        (list 'dir 0 nil "040000" nil)))
     ;; The owner's whole list is known and this name isn't in it: no such repository.
     ((let ((all (gethash (list :repos (+gh-fs-path-owner p)) +gh-fs--memo)))
        (and all (not (member (+gh-fs-path-repo p) all))))
      nil)
     ((and (string-empty-p (+gh-fs-path-path p))
           (gethash (list :repo-meta (+gh-fs-path-owner p) (+gh-fs-path-repo p)) +gh-fs--memo))
      ;; A repository its owner's listing told us about: no request.
      (pcase-let ((`(,pushed ,size) (gethash (list :repo-meta (+gh-fs-path-owner p) (+gh-fs-path-repo p)) +gh-fs--memo)))
        (list 'dir size nil "040000" pushed)))
     (t (when-let* ((tree (if with-mtime (+gh-fs--tree p) (+gh-fs--tree-soon p)))
                    (e (gethash (+gh-fs-path-path p) tree)))
          (append e (list (and with-mtime
                               (or (gethash :mtime tree)
                                   (puthash :mtime (+gh-fs--commit-time p (+gh-fs--ref p)) tree))))))))))

(defun +gh-fs--children (dir)
  "Names in DIR (directories without a slash), or nil (or what has arrived)."
  (let ((p (+gh-fs--parse dir)))
    (cond
     ((null (+gh-fs-path-owner p))
      (let (all) (maphash (lambda (k _) (push k all)) +gh-fs--owners) (sort all #'string<)))
     ((null (+gh-fs-path-repo p)) (+gh-fs--owner-repos (+gh-fs-path-owner p)))
     (t (when-let* ((tree (+gh-fs--tree-soon p)))
          (reverse (gethash (cons :children (+gh-fs-path-path p)) tree)))))))

(defun +gh-fs--child-dir-p (dir name)
  "Whether NAME in DIR is a directory, without a request when avoidable."
  (let ((p (+gh-fs--parse dir)))
    (or (null (+gh-fs-path-repo p))   ; owners and repositories
        (eq (car (+gh-fs--entry (concat (file-name-as-directory dir) name))) 'dir))))

(+gh-fs--owners-load)
(run-with-idle-timer 20 nil #'+gh-fs-refresh-owners)
(defvar +gh-fs--daily nil "The daily owner refresh (one, even after reloading this file).")
(when (timerp +gh-fs--daily) (cancel-timer +gh-fs--daily))
(setq +gh-fs--daily (run-at-time "24 hours" (* 24 3600) #'+gh-fs-refresh-owners))

(defun +gh-fs--blob (file)
  "A local file with FILE's content (fetched once, kept by hash)."
  (pcase-let* ((p (+gh-fs--parse file))
               (`(,type ,_size ,sha . ,_) (or (+gh-fs--entry file) (signal 'file-missing (list "Opening" "No such file" file)))))
    (when (eq type 'dir) (signal 'file-error (list "Is a directory" file)))
    (let ((cached (expand-file-name (concat "blobs/" sha) +gh-fs-cache-directory)))
      (if (file-exists-p cached) cached
        (+gh-fs--api (format "repos/%s/%s/git/blobs/%s" (+gh-fs-path-owner p) (+gh-fs-path-repo p) sha) cached)))))

(defun +gh-fs--attributes (entry name id-format)
  (pcase-let ((`(,type ,size ,sha ,mode ,mtime) entry))
    (let ((time (or mtime 0)) (exec (equal mode "100755")))
      (list (eq type 'dir) 1
            (if (eq id-format 'string) "github" 0) (if (eq id-format 'string) "github" 0)
            time time time size
            (if (eq type 'dir) "dr-xr-xr-x" (if exec "-r-xr-xr-x" "-r--r--r--"))
            t (abs (sxhash-equal (or sha name))) -1))))

;;;; The handler

(defun +gh-fs--read-only (file)
  (signal 'file-error (list "GitHub is read-only here (clone it to change it)" file)))

(defun +gh-fs--default (operation args)
  "OPERATION on ARGS without this handler."
  (let ((inhibit-file-name-handlers (cons #'+gh-fs-handler
                                          (and (eq inhibit-file-name-operation operation)
                                               inhibit-file-name-handlers)))
        (inhibit-file-name-operation operation))
    (apply operation args)))

(defun +gh-fs--local (operation args)
  "OPERATION on ARGS with `default-directory' somewhere local (processes)."
  (let ((default-directory temporary-file-directory))
    (apply operation args)))

(defun +gh-fs--without-t (switches)
  "SWITCHES (ls options) without -t in their short-option clusters."
  (if (listp switches) (mapcar #'+gh-fs--without-t switches)
    (mapconcat (lambda (w) (if (string-match-p "\\`-[^-]" w)
                               (let ((s (replace-regexp-in-string "t" "" w))) (if (equal s "-") "" s))
                             w))
               (split-string switches " " t) " ")))

(defun +gh-fs-handler (operation &rest args)
  "File name handler for `+gh-fs-root'."
  (pcase operation
    ;; What is it?
    ((or 'file-exists-p 'file-readable-p)
     (and (+gh-fs--entry (car args)) t))
    ('file-directory-p (eq (car (+gh-fs--entry (car args))) 'dir))
    ('file-accessible-directory-p (eq (car (+gh-fs--entry (car args))) 'dir))
    ('file-regular-p (eq (car (+gh-fs--entry (car args))) 'file))
    ('file-executable-p (let ((e (+gh-fs--entry (car args)))) (or (eq (car e) 'dir) (equal (nth 3 e) "100755"))))
    ('file-writable-p nil)
    ('file-symlink-p nil)
    ('file-attributes (when-let* ((e (+gh-fs--entry (car args) t))) (+gh-fs--attributes e (car args) (cadr args))))
    ('file-modes (let ((e (+gh-fs--entry (car args)))) (and e (if (eq (car e) 'dir) #o555 #o444))))
    ('file-newer-than-file-p nil)
    ('file-remote-p
     (pcase (cadr args)
       ('method "github")
       ('host (let ((p (+gh-fs--parse (car args)))) (and (+gh-fs-path-repo p) (concat (+gh-fs-path-owner p) "/" (+gh-fs-path-repo p)))))
       ('localname (concat "/" (+gh-fs-path-path (+gh-fs--parse (car args)))))
       (_ (concat +gh-fs-root "/"))))
    ('file-truename (+gh-fs-canonical (car args)))
    ('file-name-case-insensitive-p nil)
    ;; Listings
    ('directory-files
     (pcase-let ((`(,dir ,full ,match ,nosort ,count) args))
       (let* ((names (append '("." "..") (+gh-fs--children dir)))
              (names (if match (seq-filter (lambda (n) (string-match-p match n)) names) names))
              (names (if full (mapcar (lambda (n) (concat (file-name-as-directory dir) n)) names) names))
              (names (if nosort names (sort names #'string<))))
         (if count (seq-take names count) names))))
    ('directory-files-and-attributes
     (pcase-let ((`(,dir ,full ,match ,nosort ,id-format ,count) args))
       (mapcar (lambda (n)
                 (let ((f (if full n (concat (file-name-as-directory dir) n))))
                   (cons n (if (member (file-name-nondirectory n) '("." ".."))
                               (+gh-fs--attributes (or (+gh-fs--entry dir) (list 'dir 0 nil "040000" nil)) n id-format)
                             (+gh-fs-handler 'file-attributes f id-format)))))
               (+gh-fs-handler 'directory-files dir full match nosort count))))
    ('file-name-all-completions
     (pcase-let ((`(,prefix ,dir) args))
       (let ((case-fold-search completion-ignore-case))
         (when (and (null (+gh-fs-path-owner (+gh-fs--parse dir))) (>= (length prefix) 2)
                    (< (cl-count-if (lambda (o) (string-prefix-p prefix o t)) (+gh-fs--children dir)) 3))
           (+gh-fs--search-owners (downcase prefix)))
         (cl-loop for n in (+gh-fs--children dir)
                  when (string-prefix-p prefix n completion-ignore-case)
                  collect (if (+gh-fs--child-dir-p dir n) (concat n "/") n)))))
    ('file-name-completion
     (pcase-let ((`(,prefix ,dir ,pred) args))
       (try-completion prefix (+gh-fs-handler 'file-name-all-completions prefix dir)
                       (and pred (lambda (n) (funcall pred (concat (file-name-as-directory dir) n)))))))
    ('insert-directory
     (pcase-let ((`(,file ,switches ,wildcard ,full) args))
       (require 'ls-lisp)
       ;; Not by time (-t, lisp/+dired.el): each entry's time is a call.
       (ls-lisp--insert-directory file (+gh-fs--without-t switches) wildcard full)))
    ;; Contents
    ('insert-file-contents
     (pcase-let ((`(,file ,visit ,beg ,end ,replace) args))
       (let* ((blob (+gh-fs--blob file))
              (result (let ((inhibit-file-name-handlers (cons #'+gh-fs-handler inhibit-file-name-handlers)))
                        (insert-file-contents blob nil beg end replace))))
         (when visit
           (setq buffer-file-name (expand-file-name file)
                 buffer-file-truename (+gh-fs-canonical buffer-file-name)
                 buffer-read-only t)
           (set-buffer-modified-p nil)
           (+gh-fs-handler 'set-visited-file-modtime))
         (cons (expand-file-name file) (cdr result)))))
    ('file-local-copy
     (let ((tmp (make-temp-file "gh-fs-" nil (concat "-" (file-name-nondirectory (car args))))))
       (copy-file (+gh-fs--blob (car args)) tmp t) tmp))
    ('copy-file                         ; out of GitHub: allowed
     (pcase-let ((`(,from ,to ,ok-if-exists . ,_) args))
       (if (string-match-p +gh-fs--regexp (expand-file-name to)) (+gh-fs--read-only to)
         (copy-file (+gh-fs--blob from) to ok-if-exists))))
    ('set-visited-file-modtime
     (let ((inhibit-file-name-handlers (cons #'+gh-fs-handler inhibit-file-name-handlers)))
       (set-visited-file-modtime (or (car args) (nth 4 (+gh-fs--entry buffer-file-name t)) (current-time)))))
    ('verify-visited-file-modtime t)
    ((or 'vc-registered 'file-notify-add-watch 'file-system-info 'get-free-disk-space
         'file-selinux-context 'file-acl 'file-locked-p 'lock-file 'unlock-file 'make-lock-file-name
         'file-ownership-preserved-p 'set-file-times)
     nil)
    ;; Writing: no.
    ((or 'write-region 'delete-file 'delete-directory 'rename-file 'make-directory
         'make-directory-internal 'make-symbolic-link 'add-name-to-file 'set-file-modes
         'set-file-acl 'set-file-selinux-context 'copy-directory)
     (+gh-fs--read-only (if (memq operation '(write-region)) (nth 2 args) (car args))))
    ;; Programs run locally.
    ((or 'process-file 'start-file-process 'make-process 'shell-command)
     (+gh-fs--local operation args))
    ('unhandled-file-name-directory temporary-file-directory)
    ('make-auto-save-file-name
     (expand-file-name (format "#gh-%s#" (md5 buffer-file-name)) temporary-file-directory))
    ('exec-path exec-path)
    ;; Name-only operations, and everything else.
    (_ (+gh-fs--default operation args))))

(defconst +gh-fs--regexp (concat "\\`" (regexp-quote +gh-fs-root) "\\(?:[:/]\\|\\'\\)")
  "GitHub file names: /github/OWNER/REPO/… or, as TRAMP spells remote
files, /github:OWNER/REPO/…")

(defun +gh-fs-canonical (file)
  "FILE spelled /github/…: the one name both spellings share (so the
same file is one buffer)."
  (replace-regexp-in-string (concat "\\`" (regexp-quote +gh-fs-root) ":/?") (concat +gh-fs-root "/") file))

(defun +gh-fs--register ()
  "Put the handler first, ahead of TRAMP (which claims /METHOD: names)."
  (let ((entry (cons +gh-fs--regexp #'+gh-fs-handler)))
    (setq file-name-handler-alist (cons entry (delete entry file-name-handler-alist)))))
(+gh-fs--register)
(with-eval-after-load 'tramp (+gh-fs--register))

;; Offered with TRAMP's methods: "/gi" completes to "/github:" as "/ss" to
;; "/ssh:".  Only the completion list; TRAMP itself never sees these names.
(declare-function tramp-completion-make-tramp-file-name "tramp" (method user host localname))
(defun +gh-fs-tramp-methods-a (fn partial-method &optional multi-hop)
  "Around `tramp-get-completion-methods' (FN): github among the methods
completing PARTIAL-METHOD (not MULTI-HOP)."
  (let ((methods (funcall fn partial-method multi-hop)))
    (if (and (not multi-hop) (string-prefix-p (or partial-method "") "github"))
        (cons (tramp-completion-make-tramp-file-name "github" nil nil nil) methods)
      methods)))
(with-eval-after-load 'tramp
  (advice-add 'tramp-get-completion-methods :around #'+gh-fs-tramp-methods-a))

;;;; Projects: SPC p f lists the whole repository (one call)

(defun +gh-fs-project (dir)
  "A project for DIR inside a GitHub repository: (gh . ROOT)."
  (let ((p (and (string-match-p +gh-fs--regexp (expand-file-name dir)) (+gh-fs--parse dir))))
    (when (and p (+gh-fs-path-repo p))
      (cons 'gh (file-name-as-directory
                 (+gh-fs-file (+gh-fs-path-owner p) (+gh-fs-path-repo p) (+gh-fs-path-ref p)))))))

(cl-defmethod project-root ((project (head gh))) (cdr project))
(cl-defmethod project-name ((project (head gh)))
  (let ((p (+gh-fs--parse (cdr project)))) (format "%s/%s" (+gh-fs-path-owner p) (+gh-fs-path-repo p))))
(cl-defmethod project-files ((project (head gh)) &optional _dirs)
  (let* ((root (cdr project)) (tree (+gh-fs--tree (+gh-fs--parse root))) files)
    (when tree
      (maphash (lambda (k v) (when (and (stringp k) (eq (car v) 'file)) (push (concat root k) files))) tree))
    (sort files #'string<)))
(cl-defmethod project-external-roots ((_project (head gh))) nil)

(with-eval-after-load 'project
  (add-hook 'project-find-functions #'+gh-fs-project -50))

;; Doom's SPC p f and friends are projectile's: give it the same root and
;; file list, without shelling out.
(defvar projectile-project-root-functions)
(defun +gh-fs-projectile-root (dir)
  (when-let* ((pr (+gh-fs-project dir))) (cdr pr)))
(defun +gh-fs-projectile-files-a (fn &rest args)
  (if-let* ((pr (+gh-fs-project (or (car args) default-directory))))
      (mapcar (lambda (f) (string-remove-prefix (cdr pr) f)) (project-files pr))
    (apply fn args)))
(with-eval-after-load 'projectile
  (add-to-list 'projectile-project-root-functions #'+gh-fs-projectile-root)
  (advice-add 'projectile-project-files :around #'+gh-fs-projectile-files-a))


;;;; Living with dirvish and LSP

;; dirvish sends every remote directory through TRAMP's parser (which
;; rejects /github/); ours list themselves, so plain dired with its switches.
(defun +gh-fs-dirvish-a (orig fn dir flags remote dps)
  (if (string-match-p +gh-fs--regexp (expand-file-name dir))
      (funcall fn dir flags)
    (funcall orig fn dir flags remote dps)))
;; It lives in dirvish-tramp.el, loaded after dirvish: advising it once
;; dirvish had loaded (if defined by then) left it unadvised, and
;; /github:OWNER/REPO failed with "Not a Tramp file name".
(with-eval-after-load 'dirvish-tramp
  (advice-add 'dirvish-tramp-noselect :around #'+gh-fs-dirvish-a))

;; A language server can't read /github/ files: don't start one there.
(defun +gh-fs-no-lsp-a (&rest _)
  "Non-nil (skip) in a buffer of /github/."
  (and buffer-file-name (string-match-p +gh-fs--regexp buffer-file-name)))
(dolist (fn '(eglot-ensure lsp-deferred lsp))
  (advice-add fn :before-until #'+gh-fs-no-lsp-a))
(provide '+gh-fs)
;;; +gh-fs.el ends here
