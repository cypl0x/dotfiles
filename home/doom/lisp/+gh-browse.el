;;; lisp/+gh-browse.el --- GitHub in Emacs: browse, search, dashboard, profiles -*- lexical-binding: t; -*-
;;
;; SPC o G   the GitHub menu (a transient, like magit's): everything below
;;
;; Repositories are directories (+gh-fs.el): /github/OWNER/REPO[@REF]/PATH,
;; so SPC f f, dired/dirvish, SPC p f (the whole tree in one call),
;; consult-line, imenu, bookmarks, major modes and images all work on them,
;; fetched on demand and read-only.  On top of that:
;;
;; Browse      a repository (owner/repo, a github.com URL, or the awesome
;;             list): it opens on its README, as github.com does; links in it
;;             follow as on the web (RET or a click): other repositories,
;;             relative files and directories, else the browser.
;; Here        (in a /github buffer) another branch, tag or commit at the
;;             same path; the history of this path (RET browses at a commit,
;;             d its diff); issues and pull requests (with their diffs);
;;             releases; contributors; copy the URL (#L42 with the line);
;;             open in the browser; star.
;; Clone       the least that does the job: partial (history, file contents
;;             only as checked out; the default), treeless, shallow, sparse
;;             (only the directory you are in), or full; then the same file
;;             at the same line, locally, magit, and forge if you like.  From
;;             a local repository (or magit's dispatch: G) back to the same
;;             file on GitHub, any branch, without fetching.
;; Discover    a dashboard (review requests, your pull requests, assigned
;;             issues, notifications, activity of people you follow, your
;;             recent repositories) as foldable magit sections; search and
;;             trending with language, stars, topic and period filters; stars;
;;             anyone's profile (avatar, pinned, top repositories, activity,
;;             organizations).
;; Remember    every repository, file, ref, commit, profile and search you
;;             open is noted (`+gh-browse-visits-file'); SPC o G a reports
;;             on them: per day, weekday × hour, top repositories, owners and
;;             file types.  Bookmarks (SPC RET) work on every page.
;;
;; Lists sort by clicking a column header (or S), filter with /, load more
;; with +; rows open with RET or a click; right-click has the actions.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'iso8601)
(require 'tabulated-list)
(require 'transient)
(require 'bookmark)
(unless (featurep '+gh-fs)
  (load (expand-file-name "+gh-fs" (file-name-directory (or load-file-name buffer-file-name))) nil t))

(declare-function evil-make-overriding-map "ext:evil" (keymap &optional state copy))
(defvar +gh-fs-root)
(defvar +gh-fs-cache-directory)
(defvar +gh-fs--regexp)
(declare-function +gh/profile "+gh-pages" (login))
(declare-function +gh/dashboard "+gh-pages" ())
(declare-function +gh/notifications "+gh-pages" ())
(declare-function +gh/report "+gh-pages" ())
(declare-function +gh-fs-file "+gh-fs" (owner repo &optional ref path))
(declare-function +gh-fs--parse "+gh-fs" (file))
(declare-function +gh-fs--ref "+gh-fs" (p))
(declare-function +gh-fs--api "+gh-fs" (path &optional raw-file))
(declare-function +gh-fs--me "+gh-fs" ())
(declare-function +gh-fs--entry "+gh-fs" (file))
(declare-function +gh-fs-path-owner "+gh-fs" (p))
(declare-function +gh-fs-path-repo "+gh-fs" (p))
(declare-function +gh-fs-path-ref "+gh-fs" (p))
(declare-function +gh-fs-path-path "+gh-fs" (p))
(declare-function markdown-link-url "ext:markdown-mode" ())
(declare-function magit-status-setup-buffer "ext:magit-status" (&optional directory))
(declare-function magit-insert-section "ext:magit-section")
(declare-function magit-insert-heading "ext:magit-section" (&rest args))
(declare-function gfm-view-mode "ext:markdown-mode" ())
(declare-function +gh-page-mode "+gh-browse" ())
(declare-function magit-section-mode "ext:magit-section" ())
(declare-function magit-insert-section--create "ext:magit-section")
(declare-function magit-insert-section--finish "ext:magit-section")
(declare-function forge-add-repository "ext:forge-commands" (url &optional remote limit))
(declare-function forge-get-repository "ext:forge-repo" (&rest args))
(declare-function forge-visit-topic "ext:forge-commands" (topic))
(declare-function forge-get-topic "ext:forge-topic" (topic))
(defvar markdown-follow-link-functions)
(defvar magit-section-mode-map)

(defgroup +gh-browse nil "GitHub in Emacs." :group 'tools)

(defcustom +gh-browse-clone-dir (expand-file-name "~/dev/gh/")
  "Where clones go (OWNER/REPO below it)."
  :type 'directory)

(defcustom +gh-browse-readme-first t
  "Non-nil: a repository or directory you go to shows its README, as
github.com does; dired-jump (^ or SPC o G ^) then shows the listing."
  :type 'boolean)

(defcustom +gh-browse-default "sindresorhus/awesome"
  "Where SPC o G b goes on empty input."
  :type 'string)

(defcustom +gh-browse-visits-file
  (expand-file-name "gh-browse/visits.eld" (or (getenv "XDG_DATA_HOME") "~/.local/share"))
  "Where visits are noted, one Lisp list per line."
  :type 'file)

;;;; Targets: owner/repo[@ref][:path] and github.com URLs

(cl-defstruct (+gh-place (:constructor +gh-place-make)) owner repo ref path)

(defun +gh-browse--parse (target &optional url-only)
  "TARGET (owner/repo[@ref][:path], a github.com URL) as a place; nil if it
isn't one.  With URL-ONLY, only a github.com URL counts (links in files)."
  (cond
   ((string-match "\\`\\(?:https?://\\)?\\(?:www\\.\\)?github\\.com/\\([^/#?]+\\)/\\([^/#?]+\\)\\(?:/\\(?:tree\\|blob\\)/\\([^/#?]+\\)\\(?:/\\([^#?]*\\)\\)?\\)?/?\\(?:[#?].*\\)?\\'" target)
    (+gh-place-make :owner (match-string 1 target)
                    :repo (string-remove-suffix ".git" (match-string 2 target))
                    :ref (match-string 3 target)
                    :path (string-remove-suffix "/" (or (match-string 4 target) ""))))
   ((and (not url-only)
         (string-match "\\`\\([[:alnum:]_.-]+\\)/\\([[:alnum:]_.-]+\\)\\(?:@\\([^:]+\\)\\)?\\(?::\\(.*\\)\\)?\\'" target))
    (+gh-place-make :owner (match-string 1 target) :repo (match-string 2 target)
                    :ref (match-string 3 target) :path (or (match-string 4 target) "")))))

(defun +gh-browse--file (place)
  "PLACE as a file name under /github/."
  (+gh-fs-file (+gh-place-owner place) (+gh-place-repo place) (+gh-place-ref place) (+gh-place-path place)))

(defun +gh-browse--place-at (&optional file)
  "The place of FILE (default: this buffer's file or directory), or nil."
  (let ((file (or file buffer-file-name default-directory)))
    (when (and file (string-match-p +gh-fs--regexp (expand-file-name file)))
      (let ((p (+gh-fs--parse file)))
        (when (+gh-fs-path-repo p)
          (+gh-place-make :owner (+gh-fs-path-owner p) :repo (+gh-fs-path-repo p)
                          :ref (+gh-fs-path-ref p) :path (+gh-fs-path-path p)))))))

(defvar-local +gh-browse--list-place nil "The repository a list or page belongs to.")
(defvar +gh-render-readmes)

(defun +gh-browse--here (&optional prompt)
  "The place of this buffer, or one read with PROMPT."
  (or (+gh-browse--place-at) +gh-browse--list-place
      (+gh-browse--read-place (or prompt "Repository "))))

(defun +gh-browse--read-place (prompt)
  (let ((target (read-string (format "%s(owner/repo, URL; empty: %s): " prompt +gh-browse-default))))
    (or (+gh-browse--parse (if (string-empty-p target) +gh-browse-default target))
        (user-error "Not a repository: %s" target))))

(defun +gh-browse--ref (place)
  (or (+gh-place-ref place) (+gh-fs--ref (+gh-fs--parse (+gh-browse--file place)))))

(defun +gh--repo-arg (p) (format "%s/%s" (+gh-place-owner p) (+gh-place-repo p)))

(defun +gh-browse--web-url (place &optional line)
  (format "https://github.com/%s/%s/%s/%s%s" (+gh--repo-arg place)
          (if (file-regular-p (+gh-browse--file place)) "blob" "tree")
          (+gh-browse--ref place) (+gh-place-path place)
          (if line (format "#L%d" line) "")))

;;;; Visits, for the report

(defun +gh-browse-note (kind &rest props)
  "Note a visit of KIND (repo, file, dir, ref, commit, profile, search, …)."
  (ignore-errors
    (make-directory (file-name-directory +gh-browse-visits-file) t)
    (let ((coding-system-for-write 'utf-8))
      (write-region (concat (prin1-to-string (append (list (format-time-string "%FT%T%z") kind) props)) "\n")
                    nil +gh-browse-visits-file 'append 'silent))))

(defun +gh-browse--note-place (place &optional kind)
  (+gh-browse-note (or kind (if (string-empty-p (+gh-place-path place)) 'repo 'file))
                   :repo (+gh--repo-arg place) :ref (+gh-place-ref place) :path (+gh-place-path place)))

;;;; Opening

(defun +gh-browse--readme-in (dir)
  (cl-find-if (lambda (n) (string-match-p "\\`readme\\(?:\\.\\|\\'\\)" (downcase n)))
              (ignore-errors (directory-files dir nil "\\`[^.]"))))

(defun +gh-browse-open (place &optional line)
  "Go to PLACE: a file (at LINE), or a directory (its README first)."
  (let ((file (+gh-browse--file place)))
    (unless (file-exists-p file)
      (user-error "Not on GitHub: %s (not pushed yet, or another ref?)" (abbreviate-file-name file)))
    (+gh-browse--note-place place)
    (if (file-directory-p file)
        (let ((readme (and +gh-browse-readme-first (+gh-browse--readme-in file))))
          (cond ((and readme +gh-render-readmes (string-match-p "\\.\\(md\\|markdown\\)\\'" (downcase readme)))
                 (+gh/render (expand-file-name readme file)))
                (readme (find-file (expand-file-name readme file)))
                (t (dired file))))
      (find-file file)
      (when line (goto-char (point-min)) (forward-line (1- line))))))

;;;###autoload
(defun +gh/browse (place)
  "Browse a GitHub repository (owner/repo[@ref][:path] or a URL)."
  (interactive (list (+gh-browse--read-place "Browse ")))
  (+gh-browse-open place))

(defun +gh/browse-root ()
  "This repository's top directory (the listing)."
  (interactive)
  (let ((p (copy-+gh-place (+gh-browse--here))))
    (setf (+gh-place-path p) "")
    (dired (+gh-browse--file p))))

(defun +gh/browse-readme ()
  "This directory's README."
  (interactive)
  (let* ((dir (if buffer-file-name (file-name-directory buffer-file-name) default-directory))
         (readme (or (+gh-browse--readme-in dir) (user-error "No README in %s" dir))))
    (find-file (expand-file-name readme dir))))

;;;; Links, as GitHub follows them

(defun +gh-browse--link-at-point ()
  "The link target at point: Markdown, HTML href/src, Org or a bare URL."
  (or (and (derived-mode-p 'markdown-mode) (fboundp 'markdown-link-url) (ignore-errors (markdown-link-url)))
      (save-excursion
        (let ((pos (point)) (eol (line-end-position)))
          (beginning-of-line)
          (cl-loop while (re-search-forward "href=\"\\([^\"]+\\)\"\\|src=\"\\([^\"]+\\)\"\\|\\[\\[\\([^]]+\\)\\]" eol t)
                   when (<= (match-beginning 0) pos (match-end 0))
                   return (or (match-string 1) (match-string 2) (match-string 3)))))
      (thing-at-point 'url t)))

(defun +gh-browse--resolve (place target)
  "TARGET from a file at PLACE: a place, a URL string, or nil (an anchor)."
  (or (+gh-browse--parse target t)
      (cond
       ((string-match-p "\\`[a-z]+:" target) target)
       ((string-prefix-p "#" target) nil)
       (t (let* ((target (car (split-string target "[#?]")))
                 (dir (file-name-directory (+gh-place-path place)))
                 (path (if (string-prefix-p "/" target) (substring target 1)
                         (file-relative-name (expand-file-name target (concat "/" (or dir ""))) "/"))))
            (+gh-place-make :owner (+gh-place-owner place) :repo (+gh-place-repo place)
                            :ref (+gh-place-ref place)
                            :path (if (member path '("." "./")) "" (string-remove-suffix "/" path))))))))

(defun +gh-browse--follow (target)
  "Follow TARGET (a link in this /github buffer) as GitHub would; t if done."
  (when-let* ((place (+gh-browse--place-at)))
    (let ((where (+gh-browse--resolve place target)))
      (cond ((null where) (message "An anchor in this file: %s" target))
            ((stringp where) (browse-url where))
            (t (+gh-browse-open where)))
      t)))

(defun +gh-browse-follow ()
  "Follow the link at point as GitHub would."
  (interactive)
  (+gh-browse--follow (or (+gh-browse--link-at-point) (user-error "No link here"))))

(defun +gh-browse-mouse-follow (event)
  "Follow the link clicked."
  (interactive "e")
  (mouse-set-point event)
  (+gh-browse-follow))

(defun +gh-browse--link-filter (cmd)
  "CMD when point is on a link, so RET elsewhere keeps its usual meaning."
  (and (not (derived-mode-p 'dired-mode)) (+gh-browse--link-at-point) cmd))

(defvar-keymap +gh-browse-mode-map
  "RET" '(menu-item "" +gh-browse-follow :filter +gh-browse--link-filter)
  "C-c C-o" #'+gh-browse-follow
  "C-c C-v" #'+gh/render
  "C-c ?" #'+gh-menu)

(define-minor-mode +gh-browse-mode
  "A buffer of a GitHub repository: links follow as on GitHub, SPC o G menu."
  :lighter " GitHub"
  (when +gh-browse-mode
    (when (derived-mode-p 'markdown-mode)
      (add-hook 'markdown-follow-link-functions #'+gh-browse--follow nil t))
    (let ((p (+gh-browse--place-at)))
      (setq-local header-line-format
                  (list " " (propertize (+gh--repo-arg p) 'face 'bold)
                        (propertize (format " @ %s" (or (+gh-place-ref p) "default branch")) 'face 'font-lock-keyword-face)
                        (propertize (format "  /%s" (+gh-place-path p)) 'face 'font-lock-string-face)
                        (propertize "    SPC o G: menu · RET or click on a link follows it" 'face 'shadow))))))

(defun +gh-browse-mode-maybe-h ()
  "Turn on `+gh-browse-mode' in buffers of /github; Markdown rendered."
  (when (+gh-browse--place-at)
    (when (and buffer-file-name (derived-mode-p 'markdown-mode) (not (derived-mode-p 'gfm-view-mode))
               (fboundp 'gfm-view-mode))
      (gfm-view-mode))
    (+gh-browse-mode 1)))

(add-hook 'find-file-hook #'+gh-browse-mode-maybe-h)
(add-hook 'dired-after-readin-hook #'+gh-browse-mode-maybe-h)

;;;; This repository

(defun +gh-browse--with (place &rest changes)
  (let ((p (copy-+gh-place place)))
    (cl-loop for (k v) on changes by #'cddr
             do (pcase k (:ref (setf (+gh-place-ref p) v)) (:path (setf (+gh-place-path p) v))))
    p))

(defun +gh-browse--repo-api (place fmt &rest args)
  (apply #'format (concat "repos/%s/%s/" fmt) (+gh-place-owner place) (+gh-place-repo place) args))

(defun +gh--gh (&rest args)
  "Run gh with ARGS; its output (a `user-error' with it on failure)."
  (with-temp-buffer
    (let ((default-directory temporary-file-directory) (coding-system-for-read 'utf-8))
      (unless (zerop (apply #'call-process "gh" nil t nil args))
        (user-error "gh %s: %s" (car args) (string-trim (buffer-string))))
      (buffer-string))))

(defun +gh--json (&rest args)
  "gh ARGS, parsed (fresh, not cached)."
  (json-parse-string (apply #'+gh--gh args) :object-type 'plist :array-type 'list :null-object nil :false-object nil))

(defun +gh--age (iso)
  (if (or (null iso) (string-empty-p iso)) ""
    (let ((s (float-time (time-subtract nil (date-to-time iso)))))
      (cond ((< s 3600) (format "%dm" (/ s 60))) ((< s 86400) (format "%dh" (/ s 3600)))
            ((< s (* 86400 60)) (format "%dd" (/ s 86400))) (t (format "%dmo" (/ s 2592000)))))))

(defun +gh/ref (ref)
  "The same path at another REF: a branch, a tag or a commit."
  (interactive
   (let* ((p (+gh-browse--here))
          (names (append (mapcar (lambda (b) (plist-get b :name)) (+gh-fs--api (+gh-browse--repo-api p "branches?per_page=100")))
                         (mapcar (lambda (b) (plist-get b :name)) (+gh-fs--api (+gh-browse--repo-api p "tags?per_page=100"))))))
     (list (completing-read (format "Ref (now %s; a branch, tag or commit SHA): " (+gh-browse--ref (+gh-browse--here))) names))))
  (let* ((p (+gh-browse--here)) (line (and buffer-file-name (line-number-at-pos))))
    (+gh-browse-note 'ref :repo (+gh--repo-arg p) :ref ref)
    (+gh-browse-open (+gh-browse--with p :ref ref) line)))

;;;;; History and diffs

(defun +gh/log ()
  "The commits that touched this path, at this ref."
  (interactive)
  (let* ((p (+gh-browse--here))
         (commits (+gh--json "api" (+gh-browse--repo-api p "commits?sha=%s&path=%s&per_page=60"
                                                        (url-hexify-string (+gh-browse--ref p))
                                                        (url-hexify-string (+gh-place-path p))))))
    (+gh-list-show (format "*GitHub log: %s:%s*" (+gh--repo-arg p) (+gh-place-path p))
                   [("Commit" 9 nil) ("Date" 11 t) ("Author" 20 t) ("Message" 0 nil)]
                   (mapcar (lambda (c)
                             (let ((commit (plist-get c :commit)))
                               (list (list :commit (plist-get c :sha) :place p)
                                     (vector (propertize (substring (plist-get c :sha) 0 8) 'face 'font-lock-constant-face)
                                             (substring (or (plist-get (plist-get commit :author) :date) "") 0 10)
                                             (or (plist-get (plist-get commit :author) :name) "")
                                             (car (split-string (or (plist-get commit :message) "") "\n"))))))
                           commits)
                   p nil (list #'+gh/log))))

(defun +gh--diff-buffer (name text)
  (with-current-buffer (get-buffer-create name)
    (let ((inhibit-read-only t)) (erase-buffer) (insert text))
    (diff-mode) (setq buffer-read-only t) (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

(defun +gh/commit-diff (place sha)
  "The diff of commit SHA in PLACE's repository."
  (+gh-browse-note 'commit :repo (+gh--repo-arg place) :sha sha)
  (+gh--diff-buffer (format "*GitHub diff: %s %s*" (+gh--repo-arg place) (substring sha 0 8))
                    (+gh--gh "api" "-H" "Accept: application/vnd.github.diff" (+gh-browse--repo-api place "commits/%s" sha))))

;;;;; Issues, pull requests, releases, contributors

(defun +gh/issues (&optional prs)
  "Open issues (pull requests with PRS) of this repository."
  (interactive)
  (let* ((p (+gh-browse--here))
         (items (+gh--json (if prs "pr" "issue") "list" "-R" (+gh--repo-arg p) "--limit" "100" "--json"
                           (if prs "number,title,author,updatedAt,labels,isDraft"
                             "number,title,author,updatedAt,labels"))))
    (+gh-list-show (format "*GitHub %s: %s*" (if prs "pull requests" "issues") (+gh--repo-arg p))
                   [("#" 6 +gh-list--sort-number) ("Title" 60 t) ("Author" 16 t) ("Updated" 8 t) ("Labels" 0 nil)]
                   (mapcar (lambda (i)
                             (list (list (if prs :pr :issue) (plist-get i :number) :place p)
                                   (vector (number-to-string (plist-get i :number))
                                           (concat (if (plist-get i :isDraft) (propertize "draft " 'face 'shadow) "")
                                                   (plist-get i :title))
                                           (or (plist-get (plist-get i :author) :login) "")
                                           (+gh--age (plist-get i :updatedAt))
                                           (mapconcat (lambda (l) (propertize (plist-get l :name) 'face 'font-lock-keyword-face))
                                                      (plist-get i :labels) " "))))
                           items)
                   p nil (list #'+gh/issues prs))))

(defun +gh/prs () "Open pull requests of this repository." (interactive) (+gh/issues t))

(defun +gh--forge-topic (place number)
  "Forge's topic NUMBER of PLACE's repository, if forge tracks it."
  (when (and (require 'forge nil t) (fboundp 'forge-get-repository))
    (ignore-errors
      (when-let* ((repo (forge-get-repository (list "github.com" (+gh-place-owner place) (+gh-place-repo place)) nil :tracked)))
        (forge-get-topic (list repo number))))))

(defun +gh--view (kind number place)
  "Issue or PR NUMBER of PLACE's repository: in forge if it tracks the
repository, else as Markdown with its comments."
  (+gh-browse-note (intern kind) :repo (+gh--repo-arg place) :number number)
  (if-let* ((topic (+gh--forge-topic place number)))
      (forge-visit-topic topic)
    (let ((text (+gh--gh kind "view" (number-to-string number) "-R" (+gh--repo-arg place) "--comments")))
      (with-current-buffer (get-buffer-create (format "*GitHub %s %s#%d*" kind (+gh--repo-arg place) number))
        (let ((inhibit-read-only t)) (erase-buffer) (insert text))
        (if (fboundp 'gfm-view-mode) (gfm-view-mode) (view-mode))
        (setq-local +gh-browse--list-place place)
        (setq default-directory (file-name-as-directory (+gh-browse--file (+gh-browse--with place :path ""))))
        (goto-char (point-min))
        (pop-to-buffer (current-buffer))))))

(defun +gh/releases ()
  "Releases of this repository; RET browses the tag."
  (interactive)
  (let ((p (+gh-browse--here)))
    (+gh-list-show (format "*GitHub releases: %s*" (+gh--repo-arg p))
                   [("Tag" 22 t) ("Name" 40 t) ("Published" 10 t) ("" 0 nil)]
                   (mapcar (lambda (r)
                             (list (list :ref (plist-get r :tagName) :place p)
                                   (vector (plist-get r :tagName) (or (plist-get r :name) "")
                                           (+gh--age (plist-get r :publishedAt))
                                           (concat (if (plist-get r :isLatest) (propertize "latest " 'face 'success) "")
                                                   (if (plist-get r :isPrerelease) (propertize "pre" 'face 'warning) "")))))
                           (+gh--json "release" "list" "-R" (+gh--repo-arg p) "--limit" "50"
                                      "--json" "tagName,name,publishedAt,isLatest,isPrerelease"))
                   p nil (list #'+gh/releases))))

(defun +gh/contributors ()
  "Contributors of this repository; RET: their profile."
  (interactive)
  (let ((p (+gh-browse--here)))
    (+gh-list-show (format "*GitHub contributors: %s*" (+gh--repo-arg p))
                   [("Login" 24 t) ("Commits" 8 +gh-list--sort-number) ("" 0 nil)]
                   (mapcar (lambda (c) (list (list :user (plist-get c :login))
                                             (vector (plist-get c :login) (number-to-string (plist-get c :contributions)) "")))
                           (+gh--json "api" (+gh-browse--repo-api p "contributors?per_page=100")))
                   p nil (list #'+gh/contributors))))

(defun +gh/star ()
  "Star this repository (or unstar it)."
  (interactive)
  (let* ((p (+gh-browse--here)) (path (format "user/starred/%s" (+gh--repo-arg p)))
         (starred (let ((default-directory temporary-file-directory))
                    (zerop (call-process "gh" nil nil nil "api" path)))))
    (when (y-or-n-p (format "%s %s? " (if starred "Unstar" "Star") (+gh--repo-arg p)))
      (+gh--gh "api" "-X" (if starred "DELETE" "PUT") path)
      (message "%s %s" (if starred "Unstarred" "Starred") (+gh--repo-arg p)))))

(defun +gh/copy-url ()
  "Copy the github.com URL of what you look at (with the line in a file)."
  (interactive)
  (let ((url (+gh-browse--web-url (+gh-browse--here) (and buffer-file-name (line-number-at-pos)))))
    (kill-new url) (message "Copied %s" url)))

(defun +gh/web ()
  "Open what you look at on github.com."
  (interactive)
  (browse-url (+gh-browse--web-url (+gh-browse--here) (and buffer-file-name (line-number-at-pos)))))

;;;; Clone, magit, forge

(defconst +gh-clone-kinds
  '(("partial"  "history, file contents only as checked out (git clone --filter=blob:none)" "--filter=blob:none")
    ("treeless" "commits only; trees and files on demand (--filter=tree:0): least to download, slow git log -- path" "--filter=tree:0")
    ("shallow"  "the last commit only (--depth 1): no history" "--depth" "1")
    ("sparse"   "partial, and only the directory you are in checked out (--sparse)" "--filter=blob:none" "--sparse")
    ("full"     "everything (plain git clone)"))
  "Ways to clone: (NAME DESCRIPTION . GIT-ARGS).")

(defun +gh--clone-read-kind ()
  (let* ((completion-extra-properties
          (list :annotation-function (lambda (k) (concat "  " (propertize (cadr (assoc k +gh-clone-kinds)) 'face 'shadow))))))
    (completing-read "Clone how (partial: little to download, full history)? "
                     (mapcar #'car +gh-clone-kinds) nil t nil nil "partial")))

(defun +gh/clone (&optional kind)
  "Clone this repository the KIND way (asked; partial by default) and open
the same file at the same line locally, or magit.  Offers forge after."
  (interactive (list (unless (file-directory-p (expand-file-name (+gh--repo-arg (+gh-browse--here)) +gh-browse-clone-dir))
                       (+gh--clone-read-kind))))
  (let* ((p (+gh-browse--here))
         (line (and buffer-file-name (line-number-at-pos)))
         (dir (expand-file-name (+gh--repo-arg p) +gh-browse-clone-dir))
         (open (lambda ()
                 (let ((local (expand-file-name (+gh-place-path p) dir)))
                   (cond ((and line (file-regular-p local))
                          (find-file local) (goto-char (point-min)) (forward-line (1- line)))
                         ((require 'magit nil t) (magit-status-setup-buffer dir))
                         (t (dired dir)))))))
    (if (file-directory-p dir)
        (funcall open)
      (let* ((size (plist-get (+gh-fs--api (format "repos/%s" (+gh--repo-arg p))) :size))
             (args (cddr (assoc (or kind "partial") +gh-clone-kinds))))
        (when (y-or-n-p (format "Clone %s %s into %s? (repository %s in all) " (or kind "partial") (+gh--repo-arg p)
                                (abbreviate-file-name dir) (file-size-human-readable (* 1024 (or size 0)))))
          (make-directory (file-name-directory dir) t)
          (+gh-browse-note 'clone :repo (+gh--repo-arg p) :kind kind)
          (let ((buf (get-buffer-create "*gh clone*")))
            (message "Cloning %s (%s)…" (+gh--repo-arg p) kind)
            (set-process-sentinel
             (apply #'start-process "gh-clone" buf "git" "clone"
                    (append args (when-let* ((ref (+gh-place-ref p))) (unless (string-match-p "\\`[0-9a-f]\\{40\\}\\'" ref) (list "--branch" ref)))
                            (list (format "https://github.com/%s.git" (+gh--repo-arg p)) dir)))
             (lambda (proc _)
               (when (memq (process-status proc) '(exit signal))
                 (if (not (zerop (process-exit-status proc))) (pop-to-buffer buf)
                   (let ((default-directory dir))
                     (when (equal kind "sparse")
                       (call-process "git" nil buf nil "sparse-checkout" "set"
                                     (or (file-name-directory (+gh-place-path p)) (+gh-place-path p) "")))
                     (when-let* ((ref (+gh-place-ref p)))
                       (when (string-match-p "\\`[0-9a-f]\\{40\\}\\'" ref)
                         (call-process "git" nil buf nil "checkout" ref))))
                   (funcall open)
                   (when (and (require 'forge nil t)
                              (y-or-n-p "Track it in forge too (issues and pull requests in magit)? "))
                     (let ((default-directory dir))
                       (forge-add-repository (format "https://github.com/%s" (+gh--repo-arg p)))))))))))))))

(defun +gh--remote-place (dir)
  "The GitHub place of the local repository at DIR (its origin)."
  (let* ((default-directory dir)
         (url (string-trim (with-output-to-string
                             (with-current-buffer standard-output
                               (call-process "git" nil t nil "remote" "get-url" "origin"))))))
    (when (string-match "github\\.com[:/]\\([^/]+\\)/\\([^/]+?\\)\\(?:\\.git\\)?\\'" url)
      (+gh-place-make :owner (match-string 1 url) :repo (match-string 2 url) :path ""))))

;;;###autoload
(defun +gh/browse-here ()
  "This local file (or repository) on GitHub: same branch, file and line.
In a /github buffer the other way: clone it, open it locally (`+gh/clone')."
  (interactive)
  (if (+gh-browse--place-at) (call-interactively #'+gh/clone)
    (let* ((root (or (locate-dominating-file default-directory ".git") (user-error "Not in a git repository")))
           (p (or (+gh--remote-place root) (user-error "No GitHub remote (origin) here")))
           (default-directory root)
           (branch (string-trim (shell-command-to-string "git rev-parse --abbrev-ref HEAD")))
           (line (and buffer-file-name (line-number-at-pos))))
      (setf (+gh-place-ref p) (if (equal branch "HEAD") (string-trim (shell-command-to-string "git rev-parse HEAD")) branch)
            (+gh-place-path p) (if buffer-file-name (file-relative-name buffer-file-name root) ""))
      (+gh-browse-open p line))))

(with-eval-after-load 'magit
  (ignore-errors
    (transient-append-suffix 'magit-dispatch "!"
      '("G" "GitHub (this file, any branch)" +gh/browse-here))))

;;;; Lists (tabulated, mouse-ready, bookmarkable)

(defvar-local +gh-list--more nil "A function returning the next rows, or nil.")
(defvar-local +gh-list--filter nil "The / filter: a string, or nil.")
(defvar-local +gh-list--all nil "Every row, before the filter.")
(defvar-local +gh-list--how nil "(FUNCTION . ARGS) that made this list again (bookmarks, g).")
(defvar-local +gh-list--columns nil "The column header, as tabulated-list made it.")

(defun +gh-list--sort-number (a b)
  (< (string-to-number (aref (cadr a) 0)) (string-to-number (aref (cadr b) 0))))

(defun +gh-list--propertize (rows)
  "Mouse affordances on ROWS: highlight and a hint."
  (mapcar (lambda (row)
            (list (car row)
                  (vconcat (mapcar (lambda (cell) (if (stringp cell)
                                                      (propertize cell 'mouse-face 'highlight
                                                                  'help-echo "mouse-1: open · mouse-3: actions")
                                                    cell))
                                   (cadr row)))))
          rows))

(defun +gh-list-show (name format rows &optional place more how)
  "Show ROWS ((ID [CELLS]) …) in buffer NAME with FORMAT.
PLACE: the repository; MORE: fetches more rows; HOW: (FN . ARGS) to redo it."
  (with-current-buffer (get-buffer-create name)
    (+gh-list-mode)
    ;; SPC f f, SPC p f and dired start here: the repository, or /github/.
    (setq default-directory (if place (file-name-as-directory (+gh-browse--file (+gh-browse--with place :path "")))
                              (concat +gh-fs-root "/")))
    (setq tabulated-list-format format
          +gh-list--all (+gh-list--propertize rows)
          +gh-list--more more
          +gh-list--filter nil
          +gh-list--how how
          +gh-browse--list-place place)
    (tabulated-list-init-header)
    (setq +gh-list--columns header-line-format)
    (+gh-list--refresh)
    (pop-to-buffer-same-window (current-buffer))))

(defun +gh-list--refresh ()
  (setq tabulated-list-entries
        (if (not +gh-list--filter) +gh-list--all
          (seq-filter (lambda (row) (cl-some (lambda (c) (and (stringp c) (string-match-p (regexp-quote +gh-list--filter) c)))
                                              (cadr row)))
                      +gh-list--all)))
  (tabulated-list-print t)
  (setq-local mode-line-process
              (format " %d%s" (length tabulated-list-entries)
                      (if +gh-list--filter (format " “%s”" +gh-list--filter) ""))))

(defun +gh-list-filter (string)
  "Show only rows containing STRING (empty: all)."
  (interactive (list (read-string "Filter (empty: all): " +gh-list--filter)))
  (setq +gh-list--filter (unless (string-empty-p string) string))
  (+gh-list--refresh))

(defun +gh-list-more ()
  "Load more rows."
  (interactive)
  (if-let* ((rows (and +gh-list--more (funcall +gh-list--more))))
      (progn (setq +gh-list--all (append +gh-list--all (+gh-list--propertize rows)))
             (+gh-list--refresh) (message "%d rows" (length +gh-list--all)))
    (message "No more")))

(defun +gh-list-redo ()
  "Fetch this list again."
  (interactive)
  (if +gh-list--how (apply (car +gh-list--how) (cdr +gh-list--how)) (message "Can't redo this list")))

(defun +gh-list--id () (or (tabulated-list-get-id) (user-error "Nothing on this line")))

(defun +gh-list-open ()
  "Open the row at point."
  (interactive)
  (let ((id (+gh-list--id)))
    (pcase (car id)
      (:repo (+gh-browse-open (+gh-browse--parse (cadr id))))
      (:commit (+gh-browse-note 'commit :repo (+gh--repo-arg (plist-get id :place)) :sha (cadr id))
               (+gh-browse-open (+gh-browse--with (plist-get id :place) :ref (cadr id))))
      (:ref (+gh-browse-open (+gh-browse--with (plist-get id :place) :ref (cadr id) :path "")))
      (:issue (+gh--view "issue" (cadr id) (plist-get id :place)))
      (:pr (+gh--view "pr" (cadr id) (plist-get id :place)))
      (:user (+gh/profile (cadr id)))
      (:url (browse-url (cadr id))))))

(defun +gh-list-mouse-open (event)
  "Open the row clicked (a click on a column header sorts instead)."
  (interactive "e")
  (mouse-set-point event)
  (+gh-list-open))

(defun +gh-list-diff ()
  "The diff of the commit or pull request at point."
  (interactive)
  (let ((id (+gh-list--id)))
    (pcase (car id)
      (:commit (+gh/commit-diff (plist-get id :place) (cadr id)))
      (:pr (+gh--diff-buffer (format "*GitHub PR diff %s#%d*" (+gh--repo-arg (plist-get id :place)) (cadr id))
                             (+gh--gh "pr" "diff" (number-to-string (cadr id)) "-R" (+gh--repo-arg (plist-get id :place)))))
      (_ (user-error "No diff for this row")))))

(defun +gh-list-web ()
  "The row on github.com."
  (interactive)
  (let ((id (+gh-list--id)) (p +gh-browse--list-place))
    (browse-url
     (pcase (car id)
       ((or :repo :user) (concat "https://github.com/" (cadr id)))
       (:issue (format "https://github.com/%s/issues/%d" (+gh--repo-arg (plist-get id :place)) (cadr id)))
       (:pr (format "https://github.com/%s/pull/%d" (+gh--repo-arg (plist-get id :place)) (cadr id)))
       (:commit (format "https://github.com/%s/commit/%s" (+gh--repo-arg (plist-get id :place)) (cadr id)))
       (:ref (format "https://github.com/%s/releases/tag/%s" (+gh--repo-arg p) (cadr id)))
       (:url (cadr id))))))

(defun +gh-list-owner ()
  "The profile of the row's owner or author."
  (interactive)
  (let ((id (+gh-list--id)))
    (+gh/profile (pcase (car id)
                   (:repo (car (split-string (cadr id) "/")))
                   (:user (cadr id))
                   (_ (aref (tabulated-list-get-entry) 2))))))

(defun +gh-list-clone ()
  "Clone the repository at point."
  (interactive)
  (let ((id (+gh-list--id)))
    (unless (eq (car id) :repo) (user-error "Not a repository"))
    (let ((+gh-browse--list-place (+gh-browse--parse (cadr id))))
      (call-interactively #'+gh/clone))))

(defun +gh-list-sort ()
  "Sort by a column (or click its header)."
  (interactive)
  (let* ((names (cl-loop for col across tabulated-list-format when (nth 2 col) collect (car col)))
         (col (completing-read "Sort by: " names nil t)))
    (tabulated-list-sort (cl-position col (append tabulated-list-format nil) :key #'car :test #'equal))))

(defun +gh-list-context-menu (menu click)
  "Actions on the clicked row, for the right-click menu."
  (save-excursion
    (mouse-set-point click)
    (when-let* ((id (tabulated-list-get-id)))
      (define-key-after menu [gh-open] '(menu-item "Open" +gh-list-open))
      (define-key-after menu [gh-web] '(menu-item "Open on github.com" +gh-list-web))
      (define-key-after menu [gh-owner] '(menu-item "Owner / author profile" +gh-list-owner))
      (when (memq (car id) '(:commit :pr))
        (define-key-after menu [gh-diff] '(menu-item "Diff" +gh-list-diff)))
      (when (eq (car id) :repo)
        (define-key-after menu [gh-clone] '(menu-item "Clone…" +gh-list-clone)))
      (define-key-after menu [gh-filter] '(menu-item "Filter…" +gh-list-filter))
      (define-key-after menu [gh-sep] '(menu-item "--"))))
  menu)

(defvar-keymap +gh-list-mode-map
  :parent tabulated-list-mode-map
  "RET" #'+gh-list-open  "<mouse-2>" #'+gh-list-mouse-open
  "o" #'+gh-list-web  "p" #'+gh-list-owner  "d" #'+gh-list-diff  "c" #'+gh-list-clone
  "/" #'+gh-list-filter  "S" #'+gh-list-sort  "+" #'+gh-list-more  "g" #'+gh-list-redo
  "?" #'+gh-menu)

(define-derived-mode +gh-list-mode tabulated-list-mode "GitHub"
  "A list of GitHub things: rows open with RET or a click; headers sort."
  (setq-local context-menu-functions (cons #'+gh-list-context-menu (bound-and-true-p context-menu-functions)))
  (setq-local bookmark-make-record-function #'+gh-bookmark-make-record)
  (when (fboundp 'context-menu-mode) (context-menu-mode 1)))

;; A click on a row opens it (tabulated-list rows are not buttons).
(define-key +gh-list-mode-map [down-mouse-1] #'ignore)
(define-key +gh-list-mode-map [mouse-1] #'+gh-list-mouse-open)

;;;; Repositories: search, trending, stars, anyone's

(defun +gh--repo-rows (repos)
  (mapcar (lambda (r)
            (let ((name (or (plist-get r :full_name)
                            (concat (plist-get (plist-get r :owner) :login) "/" (plist-get r :name)))))
              (list (list :repo name)
                    (vector name
                            (number-to-string (or (plist-get r :stargazers_count) 0))
                            (or (plist-get r :language) "")
                            (+gh--age (or (plist-get r :pushed_at) (plist-get r :updated_at)))
                            (or (plist-get r :description) "")))))
          repos))

(defun +gh-list--sort-stars (a b)
  (< (string-to-number (aref (cadr a) 1)) (string-to-number (aref (cadr b) 1))))

(defconst +gh--repo-format
  [("Repository" 38 t) ("★" 7 +gh-list--sort-stars :right-align t) ("Language" 12 t) ("Pushed" 7 t) ("Description" 0 nil)])

(defun +gh--search-repos (query &optional sort title)
  "Repositories matching QUERY (GitHub search syntax), by SORT."
  (+gh-browse-note 'search :query query)
  (let* ((page 1)
         (fetch (lambda ()
                  (prog1 (+gh--repo-rows
                          (plist-get (+gh--json "api" "-X" "GET" "search/repositories"
                                                "-f" (concat "q=" query) "-f" (concat "sort=" (or sort "stars"))
                                                "-f" "order=desc" "-f" "per_page=50" "-f" (format "page=%d" page))
                                     :items))
                    (cl-incf page)))))
    (+gh-list-show (format "*GitHub: %s*" (or title query)) +gh--repo-format (funcall fetch) nil fetch
                   (list #'+gh--search-repos query sort title))))

(defun +gh--qualifiers (args)
  "Search qualifiers (language:x stars:>n …) from transient ARGS."
  (mapconcat #'identity (seq-filter (lambda (a) (string-match-p "\\`[a-z]+:" a)) args) " "))

(defun +gh--arg (args prefix)
  (cl-loop for a in args when (string-prefix-p prefix a) return (substring a (length prefix))))

(defun +gh/search (query &optional args)
  "Search repositories: QUERY plus the menu's filters (ARGS)."
  (interactive (list (read-string "Search repositories: ") (transient-args '+gh-search-menu)))
  (+gh--search-repos (string-trim (concat query " " (+gh--qualifiers args))) (+gh--arg args "--sort=")))

(defun +gh/trending (&optional args)
  "Trending: the most starred repositories created in the period (ARGS)."
  (interactive (list (transient-args '+gh-search-menu)))
  (let* ((days (string-to-number (or (+gh--arg args "--since=") "7")))
         (since (format-time-string "%Y-%m-%d" (time-subtract nil (* days 86400)))))
    (+gh--search-repos (string-trim (format "created:>%s %s" since (+gh--qualifiers args))) "stars"
                       (format "trending, last %d days %s" days (+gh--qualifiers args)))))

(defun +gh--paged-repos (title path)
  (let* ((page 1)
         (fetch (lambda () (prog1 (+gh--repo-rows (+gh--json "api" (format "%s%sper_page=100&page=%d" path
                                                                           (if (string-search "?" path) "&" "?") page)))
                             (cl-incf page)))))
    (+gh-list-show title +gh--repo-format (funcall fetch) nil fetch (list #'+gh--paged-repos title path))))

(defun +gh/stars (&optional user)
  "Starred repositories (yours, or USER's), newest star first."
  (interactive)
  (+gh--paged-repos (format "*GitHub stars: %s*" (or user "you"))
                    (if user (format "users/%s/starred" user) "user/starred")))

(defun +gh/repos (&optional user)
  "USER's repositories (yours), recently pushed first."
  (interactive)
  (+gh--paged-repos (format "*GitHub repositories: %s*" (or user "you"))
                    (if user (format "users/%s/repos?sort=pushed" user) "user/repos?sort=pushed")))

;;;; The pages (dashboard, profiles, notifications, report) are in +gh-pages.el,
;;;; loaded with the first one: magit-section isn't needed before.

(defvar-local +gh-page--how nil "(FUNCTION . ARGS) that made this page (bookmarks).")
(let ((pages (expand-file-name "+gh-pages" (file-name-directory (or load-file-name buffer-file-name)))))
  (dolist (fn '(+gh/dashboard +gh/profile +gh/notifications +gh/report))
    (autoload fn pages nil t)))

;;;; Bookmarks: every list and page

(defun +gh-bookmark-make-record ()
  "A bookmark record for this GitHub list or page."
  (let ((how (or +gh-list--how +gh-page--how)))
    (unless how (user-error "This list can't be bookmarked"))
    `(,(buffer-name) (how . ,how) (handler . +gh-bookmark-jump) (position . ,(point)))))

(defun +gh-bookmark-jump (bookmark)
  "Show the GitHub list or page BOOKMARK points to."
  (let ((how (bookmark-prop-get bookmark 'how)))
    (apply (car how) (cdr how))
    (goto-char (min (or (bookmark-get-position bookmark) 1) (point-max)))))

(put '+gh-bookmark-jump 'bookmark-handler-type "GitHub")

;;;; Visits, read back (the report and owner completion use them)

(defun +gh-browse--visits ()
  "Every noted visit, oldest first: plists with :time :kind and the rest."
  (when (file-readable-p +gh-browse-visits-file)
    (with-temp-buffer
      (insert-file-contents +gh-browse-visits-file)
      (let (out)
        (goto-char (point-min))
        (while (not (eobp))
          (when-let* ((e (ignore-errors (read (current-buffer))))
                      (time (ignore-errors (encode-time (iso8601-parse (car e))))))
            (push (append (list :time time :kind (cadr e)) (cddr e)) out))
          (skip-chars-forward " \n"))
        (nreverse out)))))

(defun +gh--count (fn visits)
  "VISITS counted by FN's value (nil skipped), most first: ((VALUE . N) …)."
  (let ((h (make-hash-table :test #'equal)) out)
    (dolist (v visits) (when-let* ((k (funcall fn v))) (cl-incf (gethash k h 0))))
    (maphash (lambda (k n) (push (cons k n) out)) h)
    (sort out (lambda (a b) (> (cdr a) (cdr b))))))

;;;; Rendered, as github.com shows it

;; READMEs mix Markdown and HTML; markdown-mode shows the HTML as tags.
;; Rendered, they come from GitHub's own renderer (POST /markdown, gfm, in
;; the repository's context: tables, emoji, #123, HTML) and are drawn by
;; shr; links resolve against the file's github.com URL and come back here.
;; Images stay off (metered link) until you ask: I, or `+gh-render-images'.

(defcustom +gh-render-readmes t
  "Non-nil: READMEs open rendered (v shows the source)."
  :type 'boolean :group '+gh-browse)

(defcustom +gh-render-images nil
  "Non-nil: rendered pages load their images (each is a download)."
  :type 'boolean :group '+gh-browse)

(declare-function shr-insert-document "shr" (dom))
(declare-function libxml-parse-html-region "xml.c" (start end &optional base-url discard-comments))
(defvar shr-inhibit-images)
(defvar shr-base)
(defvar browse-url-handlers)
(declare-function shr-next-link "shr" ())
(declare-function shr-previous-link "shr" ())
(defvar-local +gh-render--source nil "The /github file this page renders.")

(defun +gh-render--html (file)
  "FILE (under /github) as HTML, from GitHub's renderer (cached by content)."
  (let* ((p (+gh-browse--place-at file))
         (sha (nth 2 (+gh-fs--entry file)))
         (cached (expand-file-name (format "rendered/%s.html" sha) +gh-fs-cache-directory)))
    (if (file-exists-p cached)
        (with-temp-buffer (insert-file-contents cached) (buffer-string))
      (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
             (input (make-temp-file "gh-md" nil ".json"
                                    (json-serialize (list :text text :mode "gfm" :context (+gh--repo-arg p)))))
             (html (unwind-protect (+gh--gh "api" "markdown" "--input" input) (delete-file input))))
        (make-directory (file-name-directory cached) t)
        (let ((coding-system-for-write 'utf-8)) (write-region html nil cached nil 'silent))
        html))))

(defun +gh-render--browse (url &rest _)
  "Follow URL from a rendered page: GitHub places here, the rest outside."
  (let ((place (+gh-browse--parse url t))
        (anchor (and (string-match "#\\(.+\\)\\'" url) (match-string 1 url))))
    (cond
     ((and place anchor (equal (+gh-browse--file place) (and +gh-render--source (+gh-browse--file (+gh-browse--place-at +gh-render--source)))))
      (+gh-render--goto-anchor anchor))
     (place (+gh-browse-open place))
     (t (let ((browse-url-handlers nil)) (browse-url url))))))

(defun +gh-render--goto-anchor (anchor)
  "The heading for ANCHOR (GitHub's slug) in this rendered page."
  (let ((pos (or (text-property-any (point-min) (point-max) 'shr-target-id (concat "user-content-" anchor))
                 (text-property-any (point-min) (point-max) 'shr-target-id anchor)
                 (save-excursion
                   (goto-char (point-min))
                   (let ((case-fold-search t)
                         (words (split-string anchor "-" t)))
                     (and (re-search-forward (concat "^" (mapconcat #'regexp-quote words "[^[:alnum:]\n]+")) nil t)
                          (line-beginning-position)))))))
    (if pos (progn (push-mark) (goto-char pos) (recenter 0)) (message "No heading for #%s" anchor))))

(defun +gh/render (&optional file)
  "Show FILE (this /github file) rendered as github.com shows it."
  (interactive)
  (let* ((file (or file buffer-file-name (user-error "Not a file")))
         (p (or (+gh-browse--place-at file) (user-error "Not a GitHub file")))
         (html (+gh-render--html file))
         (base (+gh-browse--web-url p))
         (buf (get-buffer-create (format "*GitHub: %s/%s*" (+gh--repo-arg p) (+gh-place-path p)))))
    (require 'shr)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (+gh-render-mode)
        (setq default-directory (file-name-directory file))
        (setq +gh-render--source file
              +gh-browse--list-place p)
        (let ((dom (with-temp-buffer (insert html) (libxml-parse-html-region (point-min) (point-max) base)))
              (shr-inhibit-images (not +gh-render-images))
              (shr-base nil))
          (shr-insert-document dom))
        (goto-char (point-min))
        (setq-local header-line-format
                    (list " " (propertize (+gh--repo-arg p) 'face 'bold)
                          (propertize (format "  /%s" (+gh-place-path p)) 'face 'font-lock-string-face)
                          (propertize "    rendered · v source · I images · RET/click links · SPC o G menu" 'face 'shadow)))))
    (+gh-browse-note 'file :repo (+gh--repo-arg p) :path (+gh-place-path p) :rendered t)
    (pop-to-buffer-same-window buf)))

(defun +gh-render-source ()
  "Toggle between the rendered page and its source."
  (interactive)
  (if +gh-render--source
      (let ((+gh-render-readmes nil)) (find-file +gh-render--source))
    (+gh/render)))

(defun +gh-render-images ()
  "Show this page's images (downloads them)."
  (interactive)
  (let ((+gh-render-images t) (pos (point)))
    (+gh/render +gh-render--source)
    (goto-char (min pos (point-max)))))

(defvar-keymap +gh-render-mode-map
  :parent special-mode-map
  "v" #'+gh-render-source  "I" #'+gh-render-images  "?" #'+gh-menu
  "TAB" #'shr-next-link  "<backtab>" #'shr-previous-link)

(define-derived-mode +gh-render-mode special-mode "GitHub"
  "A GitHub file, rendered: links come back to GitHub in Emacs."
  (setq-local browse-url-handlers '(("\\`https?://\\(?:www\\.\\)?github\\.com/" . +gh-render--browse)))
  (setq-local bookmark-make-record-function
              (lambda () `(,(buffer-name) (filename . ,+gh-render--source) (handler . +gh-render--bookmark-jump)))))

(defun +gh-render--bookmark-jump (bookmark)
  (+gh/render (bookmark-prop-get bookmark 'filename)))

(with-eval-after-load 'evil
  (evil-make-overriding-map +gh-render-mode-map 'normal))
;;;; The menu

(defun +gh--in-repo-p () (and (or (+gh-browse--place-at) +gh-browse--list-place) t))

(transient-define-prefix +gh-search-menu ()
  "Search and trending, with filters."
  ["Filters"
   ("-l" "Language" "language:" :class transient-option
    :choices ("emacs-lisp" "nix" "rust" "python" "go" "typescript" "javascript" "c" "c++" "haskell" "lean" "zig" "lua" "shell"))
   ("-s" "Stars at least" "stars:>=" :class transient-option :reader transient-read-number-N+)
   ("-t" "Topic" "topic:" :class transient-option)
   ("-u" "User or org" "user:" :class transient-option)
   ("-o" "Sort" "--sort=" :class transient-option :choices ("stars" "forks" "updated" "help-wanted-issues"))
   ("-p" "Trending period (days)" "--since=" :class transient-option :reader transient-read-number-N+)]
  ["Find"
   ("s" "Search repositories" +gh/search)
   ("t" "Trending" +gh/trending)])

;;;###autoload (autoload '+gh-menu "+gh-browse" nil t)
(transient-define-prefix +gh-menu ()
  "GitHub: browse, this repository, discover, remember."
  [:description (lambda () (if-let* ((p (or (+gh-browse--place-at) +gh-browse--list-place)))
                               (format "GitHub · %s @ %s · /%s" (+gh--repo-arg p) (+gh-browse--ref p) (or (+gh-place-path p) ""))
                             "GitHub"))
   ["Go"
    ("b" "Browse a repository" +gh/browse)
    ("d" "Dashboard" +gh/dashboard)
    ("n" "Notifications" +gh/notifications)
    ("p" "Profile" +gh/profile)
    ("s" "Search, trending…" +gh-search-menu)
    ("*" "Your stars" +gh/stars)
    ("R" "Your repositories" +gh/repos)
    ("/" "As directories (/github/)" (lambda () (interactive) (dired (concat +gh-fs-root "/"))))
    ("a" "Report: what you look at" +gh/report)]
   ["This repository" :if +gh--in-repo-p
    ("r" "README" +gh/browse-readme)
    ("V" "Rendered, as on github.com" +gh/render :if (lambda () buffer-file-name))
    ("^" "Top directory" +gh/browse-root)
    ("f" "Find file (all files)" project-find-file)
    ("B" "Branch, tag, commit" +gh/ref)
    ("l" "History of this path" +gh/log)
    ("i" "Issues" +gh/issues)
    ("P" "Pull requests" +gh/prs)]
   ["" :if +gh--in-repo-p
    ("v" "Releases" +gh/releases)
    ("c" "Contributors" +gh/contributors)
    ("o" "Owner's profile" (lambda () (interactive) (+gh/profile (+gh-place-owner (+gh-browse--here)))))
    ("S" "Star / unstar" +gh/star)
    ("y" "Copy URL" +gh/copy-url)
    ("w" "Open on github.com" +gh/web)
    ("C" "Clone (how?) + open locally" +gh/clone)]
   ["Local" :if-not +gh--in-repo-p
    ("h" "This file/repository on GitHub" +gh/browse-here)]])

(with-eval-after-load 'evil
  (evil-make-overriding-map +gh-list-mode-map 'normal))

(map! :leader :desc "GitHub" "o G" #'+gh-menu)

(provide '+gh-browse)
;;; +gh-browse.el ends here
