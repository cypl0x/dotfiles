;;; lisp/+gh-browse.el --- GitHub repositories in Emacs, fetched as you open them -*- lexical-binding: t; -*-
;;
;; SPC o G   browse a repository: owner/repo, a github.com URL (with
;;           /tree/REF/PATH or /blob/REF/PATH), or nothing for the awesome
;;           list (sindresorhus/awesome)
;;
;; Nothing is cloned: a directory is one API call (its listing), a file one
;; call when you open it, through `gh' (your login, 5000 calls an hour).
;; What you've opened is kept for the session.
;;
;; In a directory:
;;   RET open (a file in its own mode, a directory)   ^ up   R the README
;;   b   another branch, tag or commit                l   the history here
;;   c   clone it (shallow, the ref you're on) and open it locally
;;   y   copy the github.com URL      o   open in a browser (optional)
;;   g   refresh                      ?   menu
;; In a file (read-only, in its own mode; Markdown rendered):
;;   RET on a link follows it as GitHub would: another repository (its
;;   README, as its page shows; `+gh-browse-readme-first'),
;;   a file or directory in this one (relative links too), else the web.
;;   ^ the directory   C-c ? the rest (C-c C-b ref, C-c C-l history, C-c C-y URL);
;;   other keys stay Evil's, so you can move, search and yank as usual.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)

(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))
(declare-function markdown-link-url "ext:markdown-mode" ())

(defvar +gh-browse-clone-dir (expand-file-name "~/dev/gh/")
  "Where `c' clones repositories (OWNER/REPO below it).")

(defvar +gh-browse-readme-first t
  "Non-nil: a repository (or directory) you go to shows its README, as\ngithub.com does; ^ then shows the listing.")

(defvar +gh-browse--cache (make-hash-table :test #'equal)
  "API path → parsed answer or raw text, for this session.")

;;;; The API

(defun +gh-browse--api (path &optional raw)
  "GET PATH from the GitHub API with gh; parsed JSON, or the text if RAW."
  (let ((key (cons path raw)))
    (or (gethash key +gh-browse--cache)
        (puthash key
                 (with-temp-buffer
                   (set-buffer-multibyte t)
                   (let* ((coding-system-for-read 'utf-8)
                          (status (apply #'call-process "gh" nil t nil "api"
                                         (append (and raw '("-H" "Accept: application/vnd.github.raw"))
                                                 (list path)))))
                     (unless (zerop status)
                       (user-error "GitHub: %s" (string-trim (buffer-string))))
                     (if raw (buffer-string)
                       (goto-char (point-min))
                       (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil))))
                 +gh-browse--cache))))

(defun +gh-browse--url-path (s)
  (mapconcat (lambda (part) (url-hexify-string part)) (split-string s "/") "/"))

(defun +gh-browse--default-ref (owner repo)
  (plist-get (+gh-browse--api (format "repos/%s/%s" owner repo)) :default_branch))

;;;; Where we are

(cl-defstruct (+gh-place (:constructor +gh-place-make)) owner repo ref path)
(defvar-local +gh-browse--place nil)

(defun +gh-browse--parse (target &optional url-only)
  "TARGET (owner/repo, a github.com URL) as a place; nil if it isn't one.
With URL-ONLY, only a github.com URL counts (links in files)."
  (cond
   ((string-match "\\`\\(?:https?://\\)?\\(?:www\\.\\)?github\\.com/\\([^/#?]+\\)/\\([^/#?]+\\)\\(?:/\\(?:tree\\|blob\\)/\\([^/#?]+\\)\\(?:/\\([^#?]*\\)\\)?\\)?/?\\(?:[#?].*\\)?\\'" target)
    (+gh-place-make :owner (match-string 1 target)
                    :repo (string-remove-suffix ".git" (match-string 2 target))
                    :ref (match-string 3 target)
                    :path (string-remove-suffix "/" (or (match-string 4 target) ""))))
   ((and (not url-only) (string-match "\\`\\([[:alnum:]_.-]+\\)/\\([[:alnum:]_.-]+\\)\\(?:@\\([^:]+\\)\\)?\\(?::\\(.*\\)\\)?\\'" target))
    (+gh-place-make :owner (match-string 1 target) :repo (match-string 2 target)
                    :ref (match-string 3 target) :path (or (match-string 4 target) "")))))

(defun +gh-browse--name (place)
  (format "gh:%s/%s@%s:%s" (+gh-place-owner place) (+gh-place-repo place)
          (+gh-place-ref place) (+gh-place-path place)))

(defun +gh-browse--web-url (place &optional file)
  (format "https://github.com/%s/%s/%s/%s/%s" (+gh-place-owner place) (+gh-place-repo place)
          (if file "blob" "tree") (+gh-place-ref place) (+gh-place-path place)))

(defun +gh-browse--contents-path (place)
  (format "repos/%s/%s/contents/%s?ref=%s" (+gh-place-owner place) (+gh-place-repo place)
          (+gh-browse--url-path (+gh-place-path place)) (url-hexify-string (+gh-place-ref place))))

;;;; Opening

;;;###autoload
(defun +gh/browse (target)
  "Browse a GitHub repository at TARGET (see the file)."
  (interactive (list (read-string "Repository (owner/repo or URL; empty: the awesome list): ")))
  (let* ((place (or (+gh-browse--parse (if (string-empty-p target) "sindresorhus/awesome" target))
                    (user-error "Not a repository: %s" target))))
    (unless (+gh-place-ref place)
      (setf (+gh-place-ref place) (+gh-browse--default-ref (+gh-place-owner place) (+gh-place-repo place))))
    (+gh-browse--front place)))

(defun +gh-browse--open (place)
  "Show PLACE: a directory listing or a file."
  (let ((answer (+gh-browse--api (+gh-browse--contents-path place))))
    (if (keywordp (car-safe answer))
        (+gh-browse--show-file place answer)
      (+gh-browse--show-dir place answer))))


(defun +gh-browse--front (place)
  "Go to PLACE as github.com would: a directory's README if it has one
\(and `+gh-browse-readme-first'), else the directory or the file."
  (let* ((answer (+gh-browse--api (+gh-browse--contents-path place)))
         (readme (and +gh-browse-readme-first (not (keywordp (car-safe answer)))
                      (cl-find-if (lambda (e) (and (equal (plist-get e :type) "file")
                                                   (string-match-p "\\`readme\\(?:\\.\\|\\'\\)" (downcase (plist-get e :name)))))
                                  answer))))
    (+gh-browse--open (if readme (+gh-browse--sub place (plist-get readme :path)) place))))
(defun +gh-browse--show-dir (place entries)
  (with-current-buffer (get-buffer-create (+gh-browse--name place))
    (+gh-browse-dir-mode)
    (setq +gh-browse--place place
          tabulated-list-entries
          (mapcar (lambda (e)
                    (list (plist-get e :name)
                          (vector (propertize (concat (plist-get e :name) (if (equal (plist-get e :type) "dir") "/" ""))
                                              'face (if (equal (plist-get e :type) "dir") 'dired-directory 'default))
                                  (or (plist-get e :type) "")
                                  (if (equal (plist-get e :type) "file")
                                      (file-size-human-readable (or (plist-get e :size) 0)) ""))))
                  (sort (copy-sequence entries) (lambda (a b)
                                  (let ((da (equal (plist-get a :type) "dir")) (db (equal (plist-get b :type) "dir")))
                                    (if (eq da db) (string< (plist-get a :name) (plist-get b :name)) da))))))
    (setq header-line-format
          (format " %s/%s @ %s : /%s    RET open · ^ up · R readme · b ref · l history · c clone · ? menu"
                  (+gh-place-owner place) (+gh-place-repo place) (+gh-place-ref place) (+gh-place-path place)))
    (tabulated-list-print)
    (pop-to-buffer-same-window (current-buffer))))

(defun +gh-browse--show-file (place answer)
  ;; The contents call already carries files up to 1 MB (base64); bigger
  ;; ones come raw, in a second call.
  (let* ((content (plist-get answer :content))
         (text (if (and content (not (string-empty-p content)) (equal (plist-get answer :encoding) "base64"))
                   (decode-coding-string (base64-decode-string (string-replace "\n" "" content)) 'utf-8)
                 (+gh-browse--api (+gh-browse--contents-path place) t)))
         (name (file-name-nondirectory (+gh-place-path place))))
    (with-current-buffer (get-buffer-create (+gh-browse--name place))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min)))
      ;; Its own mode, as if it were a local file of that name.
      (let ((buffer-file-name name)) (ignore-errors (set-auto-mode)))
      (when (and (derived-mode-p 'markdown-mode) (fboundp 'gfm-view-mode)) (gfm-view-mode))
      (setq +gh-browse--place place
            buffer-read-only t
            header-line-format
            (format " %s/%s @ %s : /%s    RET on a link follows it · ^ directory · C-c ? more"
                    (+gh-place-owner place) (+gh-place-repo place) (+gh-place-ref place) (+gh-place-path place)))
      (+gh-browse-file-mode 1)
      (pop-to-buffer-same-window (current-buffer)))))

(defun +gh-browse--sub (place path)
  (+gh-place-make :owner (+gh-place-owner place) :repo (+gh-place-repo place)
                  :ref (+gh-place-ref place) :path path))

(defun +gh-browse-visit ()
  "Open the entry at point."
  (interactive)
  (let ((name (or (tabulated-list-get-id) (user-error "Nothing here")))
        (place +gh-browse--place))
    (+gh-browse--open (+gh-browse--sub place (string-remove-prefix "/" (concat (+gh-place-path place) "/" name))))))

(defun +gh-browse-up ()
  "The directory above (a file's own directory)."
  (interactive)
  (let* ((place +gh-browse--place)
         (path (+gh-place-path place))
         (up (if (string-match "/[^/]*\\'" path) (substring path 0 (match-beginning 0)) "")))
    (when (and (string-empty-p path) (not (bound-and-true-p +gh-browse-file-mode)))
      (user-error "At the top of %s/%s" (+gh-place-owner place) (+gh-place-repo place)))
    (+gh-browse--open (+gh-browse--sub place up))))

(defun +gh-browse-readme ()
  "The README of this directory (or the repository's)."
  (interactive)
  (let* ((place +gh-browse--place)
         (readme (cl-find-if (lambda (n) (string-match-p "\\`readme\\(?:\\.\\|\\'\\)" (downcase n)))
                             (mapcar #'car tabulated-list-entries))))
    (if readme
        (+gh-browse--open (+gh-browse--sub place (string-remove-prefix "/" (concat (+gh-place-path place) "/" readme))))
      (user-error "No README here"))))

(defun +gh-browse-ref (ref)
  "Browse the same path at REF: a branch, a tag or a commit."
  (interactive
   (let* ((p +gh-browse--place)
          (base (format "repos/%s/%s" (+gh-place-owner p) (+gh-place-repo p)))
          (names (append (mapcar (lambda (b) (plist-get b :name)) (+gh-browse--api (concat base "/branches?per_page=100")))
                         (mapcar (lambda (b) (concat (plist-get b :name))) (+gh-browse--api (concat base "/tags?per_page=100"))))))
     (list (completing-read (format "Ref (now %s; a branch, tag or commit SHA): " (+gh-place-ref p)) names))))
  (let ((place (copy-+gh-place +gh-browse--place)))
    (setf (+gh-place-ref place) ref)
    (+gh-browse--open place)))

(defun +gh-browse-log ()
  "The commits that touched this path, at this ref."
  (interactive)
  (let* ((p +gh-browse--place)
         (commits (+gh-browse--api (format "repos/%s/%s/commits?sha=%s&path=%s&per_page=40"
                                           (+gh-place-owner p) (+gh-place-repo p)
                                           (url-hexify-string (+gh-place-ref p))
                                           (url-hexify-string (+gh-place-path p))))))
    (with-current-buffer (get-buffer-create (format "*gh log: %s*" (+gh-browse--name p)))
      (+gh-browse-log-mode)
      (setq +gh-browse--place p
            tabulated-list-entries
            (mapcar (lambda (c)
                      (let ((commit (plist-get c :commit)))
                        (list (plist-get c :sha)
                              (vector (propertize (substring (plist-get c :sha) 0 8) 'face 'font-lock-constant-face)
                                      (substring (or (plist-get (plist-get commit :author) :date) "") 0 10)
                                      (or (plist-get (plist-get commit :author) :name) "")
                                      (car (split-string (or (plist-get commit :message) "") "\n"))))))
                    commits))
      (tabulated-list-print)
      (pop-to-buffer (current-buffer)))))

(defun +gh-browse-log-visit ()
  "Browse the repository as it was at this commit."
  (interactive)
  (let ((place (copy-+gh-place +gh-browse--place)))
    (setf (+gh-place-ref place) (or (tabulated-list-get-id) (user-error "No commit here")))
    (+gh-browse--open place)))

(defun +gh-browse-copy-url ()
  "Copy the github.com URL of what you're looking at."
  (interactive)
  (let ((url (+gh-browse--web-url +gh-browse--place (bound-and-true-p +gh-browse-file-mode))))
    (kill-new url) (message "Copied %s" url)))

(defun +gh-browse-web ()
  "Open what you're looking at in a browser."
  (interactive)
  (browse-url (+gh-browse--web-url +gh-browse--place (bound-and-true-p +gh-browse-file-mode))))

(defun +gh-browse-clone ()
  "Clone the repository (shallow, at this ref) and open it locally."
  (interactive)
  (let* ((p +gh-browse--place)
         (meta (+gh-browse--api (format "repos/%s/%s" (+gh-place-owner p) (+gh-place-repo p))))
         (dir (expand-file-name (format "%s/%s" (+gh-place-owner p) (+gh-place-repo p)) +gh-browse-clone-dir)))
    (if (file-directory-p dir)
        (dired (expand-file-name (+gh-place-path p) dir))
      (when (y-or-n-p (format "Clone %s/%s at %s (repository ~%s, shallow: less) into %s? "
                              (+gh-place-owner p) (+gh-place-repo p) (+gh-place-ref p)
                              (file-size-human-readable (* 1024 (or (plist-get meta :size) 0)))
                              (abbreviate-file-name dir)))
        (make-directory (file-name-directory dir) t)
        (let ((buf (get-buffer-create "*gh clone*")))
          (message "Cloning…")
          (set-process-sentinel
           (start-process "gh-clone" buf "git" "clone" "--depth" "1" "--branch" (+gh-place-ref p)
                          (format "https://github.com/%s/%s.git" (+gh-place-owner p) (+gh-place-repo p)) dir)
           (lambda (proc _)
             (when (memq (process-status proc) '(exit signal))
               (if (zerop (process-exit-status proc))
                   (dired (expand-file-name (+gh-place-path p) dir))
                 (pop-to-buffer buf))))))))))

;;;; Links in files

(defun +gh-browse--link-at-point ()
  "The link target at point: Markdown, HTML href, Org or a bare URL."
  (or (and (derived-mode-p 'markdown-mode) (fboundp 'markdown-link-url) (ignore-errors (markdown-link-url)))
      (save-excursion
        (let ((eol (line-end-position)))
          (beginning-of-line)
          (cl-loop while (re-search-forward "href=\"\\([^\"]+\\)\"\\|\\[\\[\\([^]]+\\)\\]" eol t)
                   when (<= (match-beginning 0) (point) (match-end 0))
                   return (or (match-string 1) (match-string 2)))))
      (thing-at-point 'url t)))

(defun +gh-browse--resolve (place target)
  "TARGET from a file at PLACE: a place to browse, or a URL string."
  (or (+gh-browse--parse target t)
      (cond
       ((string-match-p "\\`[a-z]+:" target) target)          ; another site
       ((string-prefix-p "#" target) nil)                     ; an anchor here
       (t (let* ((target (car (split-string target "[#?]")))
                 (dir (file-name-directory (+gh-place-path place)))
                 (path (if (string-prefix-p "/" target) (substring target 1)
                         (file-relative-name (expand-file-name target (concat "/" (or dir "")))
                                             "/"))))
            (+gh-browse--sub place (if (member path (quote ("." "./"))) "" (string-remove-suffix "/" path))))))))

(defun +gh-browse-follow ()
  "Follow the link at point as GitHub would."
  (interactive)
  (let* ((target (or (+gh-browse--link-at-point) (user-error "No link here")))
         (where (+gh-browse--resolve +gh-browse--place target)))
    (cond ((null where) (message "An anchor in this file: %s" target))
          ((stringp where) (browse-url where))
          ((+gh-place-ref where) (+gh-browse--front where))
          (t (setf (+gh-place-ref where) (+gh-browse--default-ref (+gh-place-owner where) (+gh-place-repo where)))
             (+gh-browse--front where)))))

;;;; Modes

(defvar-keymap +gh-browse-dir-mode-map
  "RET" #'+gh-browse-visit  "^" #'+gh-browse-up  "R" #'+gh-browse-readme  "b" #'+gh-browse-ref
  "l" #'+gh-browse-log  "c" #'+gh-browse-clone  "y" #'+gh-browse-copy-url  "o" #'+gh-browse-web
  "g" #'+gh-browse-refresh  "?" #'+gh-browse-menu)

(define-derived-mode +gh-browse-dir-mode tabulated-list-mode "GitHub"
  "A directory of a GitHub repository."
  (setq tabulated-list-format [("Name" 48 t) ("Type" 6 t) ("Size" 0 nil)])
  (tabulated-list-init-header))

(defun +gh-browse-refresh ()
  "Fetch this directory or file again."
  (interactive)
  (remhash (cons (+gh-browse--contents-path +gh-browse--place) nil) +gh-browse--cache)
  (remhash (cons (+gh-browse--contents-path +gh-browse--place) t) +gh-browse--cache)
  (+gh-browse--open +gh-browse--place))

(defvar-keymap +gh-browse-file-mode-map
  "RET" #'+gh-browse-follow  "^" #'+gh-browse-up  "C-c ?" #'+gh-browse-menu
  "C-c C-b" #'+gh-browse-ref  "C-c C-l" #'+gh-browse-log
  "C-c C-y" #'+gh-browse-copy-url  "C-c C-o" #'+gh-browse-web)

(define-minor-mode +gh-browse-file-mode
  "A file of a GitHub repository: RET follows links (see `+gh/browse')."
  :lighter " GitHub")

(define-derived-mode +gh-browse-log-mode tabulated-list-mode "GitHub log"
  "Commits of a GitHub repository."
  (setq tabulated-list-format [("Commit" 10 nil) ("Date" 11 t) ("Author" 22 t) ("Message" 0 nil)])
  (tabulated-list-init-header))
(define-key +gh-browse-log-mode-map (kbd "RET") #'+gh-browse-log-visit)

(transient-define-prefix +gh-browse-menu ()
  "Browsing a GitHub repository."
  [["Here"
    ("RET" "open" +gh-browse-visit) ("^" "up" +gh-browse-up) ("R" "README" +gh-browse-readme)
    ("g" "fetch again" +gh-browse-refresh)]
   ["Repository"
    ("b" "branch, tag, commit" +gh-browse-ref) ("l" "history" +gh-browse-log)
    ("c" "clone and open locally" +gh-browse-clone)]
   ["Out"
    ("y" "copy URL" +gh-browse-copy-url) ("o" "browser" +gh-browse-web) ("n" "another repository" +gh/browse)]])

(with-eval-after-load 'evil
  (evil-make-overriding-map +gh-browse-dir-mode-map 'normal)
  (evil-make-overriding-map +gh-browse-log-mode-map 'normal)
  (evil-make-overriding-map +gh-browse-file-mode-map 'normal))

(map! :leader :desc "Browse a GitHub repository" "o G" #'+gh/browse)

(provide '+gh-browse)
;;; +gh-browse.el ends here
