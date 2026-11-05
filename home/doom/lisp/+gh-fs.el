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

(defvar +gh-fs--memo (make-hash-table :test #'equal)
  "API answers for this session: repositories, trees, listings.")

;;;; The API

(defun +gh-fs--api (path &optional raw-file)
  "GET PATH with gh; parsed JSON (cached for the session).
With RAW-FILE, write the raw body to that file and return it."
  (if raw-file
      (let ((coding-system-for-read 'binary)
            (default-directory temporary-file-directory))
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (unless (zerop (call-process "gh" nil t nil "api" "-H" "Accept: application/vnd.github.raw" path))
            (error "GitHub: %s" (string-trim (buffer-string))))
          (make-directory (file-name-directory raw-file) t)
          (let ((coding-system-for-write 'binary)) (write-region nil nil raw-file nil 'silent))
          raw-file))
    (let ((hit (gethash path +gh-fs--memo :none)))
      (if (not (eq hit :none)) hit
        (puthash path
                 (with-temp-buffer
                   (let ((coding-system-for-read 'utf-8)
                         (default-directory temporary-file-directory))
                     (if (zerop (call-process "gh" nil '(t nil) nil "api" path))
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
  (let* ((rel (string-remove-prefix +gh-fs-root (directory-file-name (expand-file-name file))))
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
            (puthash :mtime (+gh-fs--commit-time p ref) table)
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

(defun +gh-fs--entry (file)
  "What FILE is: (TYPE SIZE SHA MODE MTIME), or nil if it doesn't exist."
  (let ((p (+gh-fs--parse file)))
    (cond
     ((null (+gh-fs-path-owner p)) (list 'dir 0 nil "040000" nil))
     ((null (+gh-fs-path-repo p))
      (when (+gh-fs--api (format "users/%s" (+gh-fs-path-owner p))) (list 'dir 0 nil "040000" nil)))
     (t (when-let* ((tree (+gh-fs--tree p))
                    (e (gethash (+gh-fs-path-path p) tree)))
          (append e (list (gethash :mtime tree))))))))

(defun +gh-fs--children (dir)
  "Names in DIR (directories without a slash), or nil."
  (let ((p (+gh-fs--parse dir)))
    (cond
     ((null (+gh-fs-path-owner p))
      (delete-dups (cons (+gh-fs--me) (mapcar (lambda (o) (plist-get o :login)) (+gh-fs--api "user/orgs")))))
     ((null (+gh-fs-path-repo p))
      (mapcar (lambda (r) (plist-get r :name))
              (let ((owner (+gh-fs-path-owner p)))
                (if (equal owner (+gh-fs--me))
                    (+gh-fs--paginate "user/repos?affiliation=owner&sort=pushed")
                  (+gh-fs--paginate (format "users/%s/repos?sort=pushed" owner))))))
     (t (when-let* ((tree (+gh-fs--tree p)))
          (reverse (gethash (cons :children (+gh-fs-path-path p)) tree)))))))

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
    ('file-attributes (when-let* ((e (+gh-fs--entry (car args)))) (+gh-fs--attributes e (car args) (cadr args))))
    ('file-modes (let ((e (+gh-fs--entry (car args)))) (and e (if (eq (car e) 'dir) #o555 #o444))))
    ('file-newer-than-file-p nil)
    ('file-remote-p
     (pcase (cadr args)
       ('method "github")
       ('host (let ((p (+gh-fs--parse (car args)))) (and (+gh-fs-path-repo p) (concat (+gh-fs-path-owner p) "/" (+gh-fs-path-repo p)))))
       ('localname (concat "/" (+gh-fs-path-path (+gh-fs--parse (car args)))))
       (_ (concat +gh-fs-root "/"))))
    ((or 'file-truename 'file-name-case-insensitive-p)
     (if (eq operation 'file-truename) (car args) nil))
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
         (cl-loop for n in (+gh-fs--children dir)
                  when (string-prefix-p prefix n completion-ignore-case)
                  collect (if (eq (car (+gh-fs--entry (concat (file-name-as-directory dir) n))) 'dir)
                              (concat n "/") n)))))
    ('file-name-completion
     (pcase-let ((`(,prefix ,dir ,pred) args))
       (try-completion prefix (+gh-fs-handler 'file-name-all-completions prefix dir)
                       (and pred (lambda (n) (funcall pred (concat (file-name-as-directory dir) n)))))))
    ('insert-directory
     (pcase-let ((`(,file ,switches ,wildcard ,full) args))
       (require 'ls-lisp)
       (ls-lisp--insert-directory file switches wildcard full)))
    ;; Contents
    ('insert-file-contents
     (pcase-let ((`(,file ,visit ,beg ,end ,replace) args))
       (let* ((blob (+gh-fs--blob file))
              (result (let ((inhibit-file-name-handlers (cons #'+gh-fs-handler inhibit-file-name-handlers)))
                        (insert-file-contents blob nil beg end replace))))
         (when visit
           (setq buffer-file-name (expand-file-name file)
                 buffer-file-truename buffer-file-name
                 buffer-read-only t)
           (set-buffer-modified-p nil)
           (+gh-fs-handler 'set-visited-file-modtime))
         (cons (expand-file-name file) (cdr result)))))
    ('file-local-copy
     (let ((tmp (make-temp-file "gh-fs-" nil (concat "-" (file-name-nondirectory (car args))))))
       (copy-file (+gh-fs--blob (car args)) tmp t) tmp))
    ('copy-file                         ; out of GitHub: allowed
     (pcase-let ((`(,from ,to ,ok-if-exists . ,_) args))
       (if (string-prefix-p +gh-fs-root (expand-file-name to)) (+gh-fs--read-only to)
         (copy-file (+gh-fs--blob from) to ok-if-exists))))
    ('set-visited-file-modtime
     (let ((inhibit-file-name-handlers (cons #'+gh-fs-handler inhibit-file-name-handlers)))
       (set-visited-file-modtime (or (car args) (nth 4 (+gh-fs--entry buffer-file-name)) (current-time)))))
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

(defconst +gh-fs--regexp (concat "\\`" (regexp-quote +gh-fs-root) "\\(?:/\\|\\'\\)"))
(add-to-list 'file-name-handler-alist (cons +gh-fs--regexp #'+gh-fs-handler))

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
(with-eval-after-load 'dirvish
  (when (fboundp 'dirvish-tramp-noselect)
    (advice-add 'dirvish-tramp-noselect :around #'+gh-fs-dirvish-a)))

;; A language server can't read /github/ files: don't start one there.
(defun +gh-fs-no-lsp-a (&rest _)
  "Non-nil (skip) in a buffer of /github/."
  (and buffer-file-name (string-match-p +gh-fs--regexp buffer-file-name)))
(dolist (fn '(eglot-ensure lsp-deferred lsp))
  (advice-add fn :before-until #'+gh-fs-no-lsp-a))
(provide '+gh-fs)
;;; +gh-fs.el ends here
