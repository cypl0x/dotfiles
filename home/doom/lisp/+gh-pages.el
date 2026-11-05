;;; lisp/+gh-pages.el --- GitHub pages in sections: dashboard, profiles, report -*- lexical-binding: t; -*-
;;
;; The foldable pages of the GitHub menu (SPC o G d, p, n, a), split from
;; +gh-browse.el so magit-section (~0.3 s to load) loads with the first
;; page you open, not at startup, and its macros always expand.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'magit-section)
(unless (featurep '+gh-browse)
  (load (expand-file-name "+gh-browse" (file-name-directory (or load-file-name buffer-file-name))) nil t))

;;;; Pages in sections: the dashboard, profiles, notifications

(defun +gh--button (label action &optional face)
  "LABEL as a button running ACTION on RET or a click."
  (propertize label 'face (or face 'default) 'mouse-face 'highlight 'help-echo "RET or click: open"
              'keymap (let ((map (make-sparse-keymap)))
                        (define-key map (kbd "RET") action) (define-key map [mouse-1] action)
                        (define-key map [mouse-2] action) map)))

(defun +gh--section (title items render &optional bare)
  "A foldable section TITLE listing ITEMS, each inserted by RENDER.
BARE: no count in the heading (a chart)."
  (magit-insert-section (gh-section title)
    (magit-insert-heading (propertize title 'face 'magit-section-heading 'font-lock-face 'magit-section-heading)
      (if bare "" (propertize (format " (%d)" (length items)) 'face 'shadow)))
    (if items (dolist (i items) (insert "  ") (funcall render i) (insert "\n"))
      (insert (propertize "  nothing\n" 'face 'shadow)))
    (insert "\n")))

(defun +gh--url-action (url)
  (lambda () (interactive)
    (if (string-match "github\\.com/\\([^/]+/[^/]+\\)/\\(issues\\|pull\\)/\\([0-9]+\\)" url)
        (+gh--view (if (equal (match-string 2 url) "pull") "pr" "issue") (string-to-number (match-string 3 url))
                   (+gh-browse--parse (match-string 1 url)))
      (browse-url url))))

(defun +gh--render-issue (i)
  (let* ((url (plist-get i :url))
         (repo (and (string-match "github\\.com/\\([^/]+/[^/]+\\)/" url) (match-string 1 url))))
    (insert (propertize (format "%-30s" (truncate-string-to-width (or repo "") 30)) 'face 'font-lock-constant-face)
            (+gh--button (format "#%-5d %s" (plist-get i :number) (truncate-string-to-width (plist-get i :title) 70))
                         (+gh--url-action url))
            (propertize (format "  %s" (+gh--age (plist-get i :updatedAt))) 'face 'shadow))))

(defun +gh--render-repo (r)
  (let ((name (or (plist-get r :full_name) (plist-get r :nameWithOwner))))
    (insert (+gh--button (format "%-40s" name) (lambda () (interactive) (+gh-browse-open (+gh-browse--parse name))) 'bold)
            (propertize (format " ★%-6s %s" (or (plist-get r :stargazers_count) (plist-get r :stargazerCount) 0)
                                (truncate-string-to-width (or (plist-get r :description) "") 70))
                        'face 'shadow))))

(defun +gh--group-events (events)
  "EVENTS newest first, repeats (same person, kind, repository) folded into
the newest with :count."
  (let ((groups (make-hash-table :test #'equal)) order)
    (dolist (e (sort (copy-sequence events)
                     (lambda (a b) (string> (or (plist-get a :created_at) "") (or (plist-get b :created_at) "")))))
      (let ((key (list (plist-get (plist-get e :actor) :login) (plist-get e :type) (plist-get (plist-get e :repo) :name))))
        (if-let* ((g (gethash key groups)))
            (plist-put g :count (1+ (plist-get g :count)))
          (push key order)
          (puthash key (append (list :count 1) e) groups))))
    (mapcar (lambda (k) (gethash k groups)) (nreverse order))))

(defun +gh--render-event (e)
  (let* ((repo (plist-get (plist-get e :repo) :name))
         (who (plist-get (plist-get e :actor) :login))
         (what (pcase (plist-get e :type)
                 ("WatchEvent" "starred") ("ForkEvent" "forked") ("CreateEvent" "created")
                 ("PushEvent" "pushed to") ("ReleaseEvent" "released") ("PublicEvent" "made public")
                 ("IssuesEvent" "worked on issues in") ("PullRequestEvent" "worked on a PR in")
                 ("IssueCommentEvent" "commented in") ("MemberEvent" "joined")
                 ("PullRequestReviewEvent" "reviewed a PR in") ("PullRequestReviewCommentEvent" "commented on a PR in")
                 ("DeleteEvent" "deleted a branch in") ("GollumEvent" "edited the wiki of")
                 (type (downcase (string-remove-suffix "Event" type))))))
    (insert (+gh--button (format "%-18s" who) (lambda () (interactive) (+gh/profile who)) 'font-lock-keyword-face)
            (format " %-20s " what)
            (+gh--button repo (lambda () (interactive) (+gh-browse-open (+gh-browse--parse repo))) 'bold)
            (propertize (format "  %s%s" (let ((c (or (plist-get e :count) 1))) (if (> c 1) (format "×%d · " c) ""))
                                (+gh--age (plist-get e :created_at)))
                        'face 'shadow))))

(defun +gh--group-notifications (ns)
  "NS with repeats (same repository, kind and title) folded into the newest,
counted in :count; newest first."
  (let ((groups (make-hash-table :test #'equal)) order)
    (dolist (n ns)
      (let ((key (list (plist-get (plist-get n :repository) :full_name)
                       (plist-get (plist-get n :subject) :type) (plist-get (plist-get n :subject) :title))))
        (if-let* ((g (gethash key groups)))
            (plist-put g :count (1+ (plist-get g :count)))
          (push key order)
          (puthash key (append (list :count 1) n) groups))))
    (mapcar (lambda (k) (gethash k groups)) (nreverse order))))

(defun +gh--render-notification (n)
  (let* ((subject (plist-get n :subject))
         (url (replace-regexp-in-string
               "api\\.github\\.com/repos/\\(.*\\)/pulls/" "github.com/\\1/pull/"
               (replace-regexp-in-string "api\\.github\\.com/repos/" "github.com/" (or (plist-get subject :url) "")))))
    (insert (propertize (format "%-30s" (truncate-string-to-width (plist-get (plist-get n :repository) :full_name) 30))
                        'face 'font-lock-constant-face)
            (let ((b (+gh--button (format "%-12s %s" (plist-get subject :type) (truncate-string-to-width (plist-get subject :title) 64))
                                  (+gh--url-action url)))
                  (thread (plist-get n :id)))
              (define-key (get-text-property 0 'keymap b) "r"
                          (lambda () (interactive)
                            (+gh--gh "api" "-X" "PATCH" (concat "notifications/threads/" thread))
                            (message "Marked read (g refreshes)")))
              (propertize b 'help-echo "RET or click: open · r: mark read"))
            (propertize (format "  %s%s · %s" (let ((c (or (plist-get n :count) 1))) (if (> c 1) (format "×%d · " c) ""))
                                (plist-get n :reason) (+gh--age (plist-get n :updated_at)))
                        'face 'shadow))))

(defun +gh--search-issues (kind query)
  (+gh--json "search" kind "--json" "number,title,url,updatedAt" "--limit" "20" "--" query))

(defvar-local +gh-page--how nil "(FUNCTION . ARGS) that made this page (bookmarks).")
(defvar-local +gh-page--render nil "How to render this page again.")

(defun +gh-page-refresh ()
  "Fetch and show this page again."
  (interactive)
  (funcall +gh-page--render))

(defvar-keymap +gh-page-mode-map
  "g" #'+gh-page-refresh  "?" #'+gh-menu)

;; magit-section loads with the first page, not at startup.
(with-eval-after-load 'magit-section
  (set-keymap-parent +gh-page-mode-map magit-section-mode-map)
  (define-derived-mode +gh-page-mode magit-section-mode "GitHub"
    "A GitHub page in foldable sections: TAB folds, RET or a click opens."
    (setq-local bookmark-make-record-function #'+gh-bookmark-make-record))
  (with-eval-after-load 'evil (evil-make-overriding-map +gh-page-mode-map 'normal)))

(defun +gh--page (name how render)
  "Show page NAME (redo with HOW) drawn by RENDER."
  (require 'magit-section)
  (with-current-buffer (get-buffer-create name)
    (+gh-page-mode)
    (setq default-directory (if (eq (car how) '+gh/profile) (format "%s/%s/" +gh-fs-root (cadr how))
                              (concat +gh-fs-root "/")))
    (setq +gh-page--how how
          +gh-page--render (lambda () (let ((inhibit-read-only t) (pos (point)))
                                        (erase-buffer)
                                        (magit-insert-section (gh-root) (funcall render))
                                        (goto-char (min pos (point-max))))))
    (funcall +gh-page--render)
    (goto-char (point-min))
    (pop-to-buffer-same-window (current-buffer))))

;;;###autoload
(defun +gh/dashboard ()
  "Your GitHub: what waits for you, what you follow, your repositories."
  (interactive)
  (+gh-browse-note 'dashboard)
  (let ((me (+gh-fs--me)))
    (+gh--page "*GitHub dashboard*" (list #'+gh/dashboard)
               (lambda ()
                 (insert (propertize (format "GitHub · %s" me) 'face '(:inherit bold :height 1.3))
                         (propertize (format "   %s · TAB fold · RET/click open · g refresh · ? menu\n\n"
                                             (format-time-string "%H:%M"))
                                     'face 'shadow))
                 (+gh--section "Review requested" (+gh--search-issues "prs" "is:open review-requested:@me") #'+gh--render-issue)
                 (+gh--section "Your pull requests" (+gh--search-issues "prs" "is:open author:@me") #'+gh--render-issue)
                 (+gh--section "Issues assigned to you" (+gh--search-issues "issues" "is:open assignee:@me") #'+gh--render-issue)
                 (+gh--section "Notifications" (+gh--group-notifications (+gh--json "api" "notifications?per_page=50"))
                               #'+gh--render-notification)
                 (+gh--section "From people you follow"
                               (seq-take (+gh--group-events (+gh--json "api" (format "users/%s/received_events?per_page=100" me))) 25)
                               #'+gh--render-event)
                 (+gh--section "Your repositories, recently pushed" (+gh--json "api" "user/repos?sort=pushed&per_page=10")
                               #'+gh--render-repo)))))

(defun +gh--avatar (login url)
  "LOGIN's avatar (96 px, cached on disk) as an image, or nil."
  (ignore-errors
    (let ((file (expand-file-name (format "avatars/%s.png" login) +gh-fs-cache-directory)))
      (unless (file-exists-p file)
        (make-directory (file-name-directory file) t)
        (url-copy-file (concat url (if (string-search "?" url) "&" "?") "s=96") file t))
      (create-image file nil nil :height 96 :ascent 'center))))


(defun +gh--contributions (login)
  "LOGIN's contribution calendar of the last year: ((DATE . COUNT) …)."
  (let ((weeks (plist-get (plist-get (plist-get (plist-get (plist-get
                (+gh--json "api" "graphql" "-f"
                           (format "query={ user(login:%S) { contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount } } } } } }" login))
                :data) :user) :contributionsCollection) :contributionCalendar) :weeks)))
    (cl-loop for w in weeks
             append (mapcar (lambda (d) (cons (plist-get d :date) (plist-get d :contributionCount)))
                            (plist-get w :contributionDays)))))

(defun +gh--render-contributions (days)
  "DAYS ((DATE . COUNT) …) as GitHub's calendar: weeks across, weekdays down."
  (if (zerop (apply #'+ 0 (mapcar #'cdr days)))
      (insert (propertize "No contributions in the last year\n" 'face 'shadow))
  (let* ((total (apply #'+ (mapcar #'cdr days)))
         (mx (max 1 (apply #'max 0 (mapcar #'cdr days))))
         (best (car (sort (copy-sequence days) (lambda (a b) (> (cdr a) (cdr b)))))))
    (insert (propertize (format "%d contributions in the last year · busiest day %s (%d)\n" total (car best) (cdr best))
                        'face 'shadow) "  ")
    (if (not (and (display-graphic-p) (image-type-available-p 'svg)))
        (insert (mapconcat (lambda (d) (if (zerop (cdr d)) "·" (string (aref "░▒▓█" (min 3 (floor (* 3.99 (/ (float (cdr d)) mx))))))))
                           days "")
                "\n")
      (let* ((p (+gh--palette)) (cell 12) (weeks (ceiling (length days) 7.0))
             (svg (svg-create (+ 10 (* weeks cell)) (+ 6 (* 7 cell)))))
        (svg-rectangle svg 0 0 (+ 10 (* weeks cell)) (+ 6 (* 7 cell)) :fill (plist-get p :bg))
        (cl-loop for d in days for i from 0
                 do (let ((v (cdr d)))
                      (svg-rectangle svg (+ 4 (* (/ i 7) cell)) (+ 3 (* (% i 7) cell)) (- cell 2) (- cell 2) :rx 2
                                     :fill (if (zerop v) (plist-get p :dim) (plist-get p :b))
                                     :fill-opacity (if (zerop v) 0.18 (+ 0.3 (* 0.7 (/ (float v) mx)))))))
        (insert-image (svg-image svg :ascent 'center) "[contributions]") (insert "\n"))))))
;;;###autoload
(defun +gh/profile (login)
  "LOGIN's profile: who, pinned, top repositories, activity, organizations."
  (interactive (list (read-string "GitHub user: " (thing-at-point 'symbol t))))
  (+gh-browse-note 'profile :user login)
  (+gh--page (format "*GitHub: %s*" login) (list #'+gh/profile login)
             (lambda ()
               (let* ((u (+gh--json "api" (format "users/%s" login)))
                      (pinned (plist-get (plist-get (plist-get (plist-get
                                                                (+gh--json "api" "graphql" "-f"
                                                                           (format "query={ user(login:%S) { pinnedItems(first:6){ nodes { ... on Repository { nameWithOwner description stargazerCount } } } } }" login))
                                                                :data) :user) :pinnedItems) :nodes))
                      (avatar (and (display-images-p) (+gh--avatar login (plist-get u :avatar_url)))))
                 (when avatar (insert-image avatar) (insert "  "))
                 (insert (propertize (or (plist-get u :name) login) 'face '(:inherit bold :height 1.4))
                         (propertize (format "  @%s\n" login) 'face 'shadow))
                 (when-let* ((bio (plist-get u :bio))) (insert bio "\n"))
                 (insert (propertize (string-join (delq nil (list (plist-get u :company) (plist-get u :location)
                                                                  (let ((b (plist-get u :blog))) (and b (not (string-empty-p b)) b))
                                                                  (format "%d followers · %d following · %d repositories"
                                                                          (plist-get u :followers) (plist-get u :following)
                                                                          (plist-get u :public_repos))))
                                                  " · ")
                                     'face 'shadow)
                         "\n  " (+gh--button "[repositories]" (lambda () (interactive) (+gh/repos login)))
                         "  " (+gh--button "[stars]" (lambda () (interactive) (+gh/stars login)))
                         "  " (+gh--button "[as a directory]" (lambda () (interactive) (dired (concat +gh-fs-root "/" login "/"))))
                         "  " (+gh--button "[on github.com]" (lambda () (interactive) (browse-url (plist-get u :html_url))))
                         "\n\n")
                 (+gh--section "Contributions" (list (+gh--contributions login)) #'+gh--render-contributions t)
                 (+gh--section "Pinned" pinned #'+gh--render-repo)
                 (+gh--section "Top repositories"
                               (seq-take (sort (+gh--json "api" (format "users/%s/repos?per_page=100&sort=pushed" login))
                                               (lambda (a b) (> (plist-get a :stargazers_count) (plist-get b :stargazers_count))))
                                         10)
                               #'+gh--render-repo)
                 (+gh--section "Recent activity" (seq-take (+gh--group-events (+gh--json "api" (format "users/%s/events/public?per_page=60" login))) 20)
                               #'+gh--render-event)
                 (+gh--section "Organizations" (+gh--json "api" (format "users/%s/orgs" login))
                               (lambda (o) (let ((l (plist-get o :login)))
                                             (insert (+gh--button l (lambda () (interactive) (+gh/profile l)) 'bold)))))))))

(defun +gh/notifications ()
  "Your notifications."
  (interactive)
  (+gh--page "*GitHub notifications*" (list #'+gh/notifications)
             (lambda () (+gh--section "Notifications" (+gh--group-notifications (+gh--json "api" "notifications?per_page=100"))
                                          #'+gh--render-notification))))


;;;; The report: what you look at on GitHub

(defun +gh--palette ()
  (let ((c (lambda (face attr fallback) (let ((v (face-attribute face attr nil t)))
                                          (if (and (stringp v) (not (string-prefix-p "unspecified" v))) v fallback)))))
    (list :bg (funcall c 'default :background "#242730") :fg (funcall c 'default :foreground "#bbc2cf")
          :dim (funcall c 'shadow :foreground "#5b6268") :a (funcall c 'font-lock-function-name-face :foreground "#51afef")
          :b (funcall c 'success :foreground "#7bc275"))))

(defun +gh--chart-days (visits)
  (let* ((days (let (out (time (plist-get (car visits) :time)))
                 (while (not (time-less-p nil time))
                   (push (format-time-string "%F" time) out)
                   (setq time (time-add time 86400)))
                 (nreverse out)))
         (counts (+gh--count (lambda (v) (format-time-string "%F" (plist-get v :time))) visits))
         (values (mapcar (lambda (d) (or (cdr (assoc d counts)) 0)) days))
         (mx (apply #'max 1 values)))
    (if (not (and (display-graphic-p) (image-type-available-p 'svg)))
        (insert "  " (mapconcat (lambda (v) (string (aref "▁▂▃▄▅▆▇█" (min 7 (floor (* 7.99 (/ (float v) mx))))))) values "") "\n")
      (let* ((p (+gh--palette)) (w (max 360 (min 1000 (- (window-body-width nil t) 40)))) (h 140)
             (n (length days)) (bw (min 40.0 (/ (float (- w 50)) (max 1 n)))) (svg (svg-create w h)))
        (svg-rectangle svg 0 0 w h :fill (plist-get p :bg))
        (cl-loop for v in values for i from 0
                 do (let ((bh (* (- h 30) (/ (float v) mx))))
                      (svg-rectangle svg (+ 40 (* i bw) 1) (- h 20 bh) (max 1 (- bw 2)) bh :fill (plist-get p :a) :fill-opacity 0.8)))
        (svg-text svg (number-to-string mx) :x 4 :y 14 :fill (plist-get p :dim) :font-size 11)
        (svg-text svg (car days) :x 40 :y (- h 4) :fill (plist-get p :dim) :font-size 11)
        (svg-text svg (car (last days)) :x (- w 80) :y (- h 4) :fill (plist-get p :dim) :font-size 11)
        (insert-image (svg-image svg :ascent 'center) "[visits per day]") (insert "\n")))))

(defun +gh--chart-heatmap (visits)
  (let ((grid (make-vector 168 0)) (names '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))
    (dolist (v visits)
      (let ((d (decode-time (plist-get v :time))))
        (cl-incf (aref grid (+ (* 24 (mod (+ 6 (decoded-time-weekday d)) 7)) (decoded-time-hour d))))))
    (let ((mx (max 1 (seq-max grid))))
      (if (not (and (display-graphic-p) (image-type-available-p 'svg)))
          (dotimes (day 7)
            (insert (format "  %s %s\n" (nth day names)
                            (mapconcat (lambda (h) (let ((v (aref grid (+ (* 24 day) h))))
                                                     (if (zerop v) "·" (string (aref "░▒▓█" (min 3 (floor (* 3.99 (/ (float v) mx)))))))))
                                       (number-sequence 0 23) ""))))
        (let* ((p (+gh--palette)) (cell 18) (left 40) (top 16)
               (svg (svg-create (+ left (* 24 cell) 10) (+ top (* 7 cell) 6))))
          (svg-rectangle svg 0 0 (+ left (* 24 cell) 10) (+ top (* 7 cell) 6) :fill (plist-get p :bg))
          (dotimes (h 24) (when (zerop (mod h 3))
                            (svg-text svg (format "%02d" h) :x (+ left (* h cell) 2) :y 12 :fill (plist-get p :dim) :font-size 10)))
          (dotimes (day 7)
            (svg-text svg (nth day names) :x 4 :y (+ top (* day cell) 13) :fill (plist-get p :dim) :font-size 11)
            (dotimes (h 24)
              (let ((v (aref grid (+ (* 24 day) h))))
                (svg-rectangle svg (+ left (* h cell)) (+ top (* day cell)) (- cell 2) (- cell 2) :rx 3
                               :fill (if (zerop v) (plist-get p :dim) (plist-get p :b))
                               :fill-opacity (if (zerop v) 0.15 (+ 0.25 (* 0.75 (/ (float v) mx))))))))
          (insert-image (svg-image svg :ascent 'center) "[visits by weekday and hour]") (insert "\n"))))))

(defun +gh--top (title counts &optional open)
  "A bar list TITLE of COUNTS ((NAME . N) …).
OPEN, a function of NAME, makes the names buttons."
  (+gh--section title (seq-take counts 12)
                (lambda (c)
                  (let* ((mx (cdr (car counts))) (n (round (* 30 (/ (float (cdr c)) mx)))))
                    (insert (if open (+gh--button (format "%-34s" (car c)) (lambda () (interactive) (funcall open (car c))) 'bold)
                              (format "%-34s" (car c)))
                            (propertize (make-string (max 1 n) ?█) 'face 'font-lock-function-name-face 'font-lock-face 'font-lock-function-name-face)
                            (format " %d" (cdr c)))))))


(defun +gh--render-pr-metrics (prs)
  "Your merged PRS (gh search prs): count, time to merge, where."
  (let* ((hours (mapcar (lambda (p) (/ (float-time (time-subtract (date-to-time (plist-get p :closedAt))
                                                                  (date-to-time (plist-get p :createdAt))))
                                       3600.0))
                        prs))
         (sorted (sort (copy-sequence hours) #'<))
         (median (and sorted (nth (/ (length sorted) 2) sorted)))
         (open (length (ignore-errors (+gh--json "search" "prs" "--author" "@me" "--state" "open" "-L" "100" "--json" "number"))))
         (repos (+gh--count (lambda (p) (plist-get (plist-get p :repository) :nameWithOwner)) prs)))
    (insert (format "%d merged in the last 90 days · %d open now · median time to merge %s\n"
                    (length prs) open
                    (cond ((null median) "–") ((< median 1) (format "%d min" (round (* 60 median))))
                          ((< median 48) (format "%.1f h" median)) (t (format "%.1f days" (/ median 24))))))
    (dolist (r (seq-take repos 5))
      (insert (format "    %-36s %d\n" (car r) (cdr r))))))
;;;###autoload
(defun +gh/report ()
  "What you look at on GitHub: when, which repositories, owners, files."
  (interactive)
  (+gh--page "*GitHub report*" (list #'+gh/report)
             (lambda ()
               (let* ((visits (+gh-browse--visits))
                      (hours (+gh--count (lambda (v) (decoded-time-hour (decode-time (plist-get v :time)))) visits))
                      (days (+gh--count (lambda (v) (nth (decoded-time-weekday (decode-time (plist-get v :time)))
                                                     '("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")))
                                        visits)))
                 (insert (propertize "What you look at on GitHub" 'face '(:inherit bold :height 1.3)) "\n\n")
                 (if (null visits)
                     (insert "Nothing noted yet: browse a little (SPC o G b), then come back.\n")
                   (insert (format "  %d visits since %s · %d repositories · %d owners\n"
                                   (length visits) (format-time-string "%F" (plist-get (car visits) :time))
                                   (length (+gh--count (lambda (v) (plist-get v :repo)) visits))
                                   (length (+gh--count (lambda (v) (or (plist-get v :user) (car (split-string (or (plist-get v :repo) "") "/" t)))) visits))))
                   (when hours
                     (insert (format "  Most active: %02d:00–%02d:59 (%d visits); busiest day: %s\n\n"
                                     (car (car hours)) (car (car hours)) (cdr (car hours)) (car (car days)))))
                   (+gh--section "Per day" (list visits) #'+gh--chart-days t)
                   (+gh--section "Weekday × hour" (list visits) #'+gh--chart-heatmap t)
                   (+gh--top "Repositories" (+gh--count (lambda (v) (plist-get v :repo)) visits)
                             (lambda (r) (+gh-browse-open (+gh-browse--parse r))))
                   (+gh--top "Owners" (+gh--count (lambda (v) (or (plist-get v :user) (car (split-string (or (plist-get v :repo) "") "/" t)))) visits)
                             #'+gh/profile)
                   (+gh--top "What" (+gh--count (lambda (v) (symbol-name (plist-get v :kind))) visits))
                   (+gh--top "File types" (+gh--count (lambda (v) (let ((p (plist-get v :path)))
                                                                    (and p (eq (plist-get v :kind) 'file)
                                                                         (or (file-name-extension p) "(none)"))))
                                                      visits))
                   (+gh--section "Your pull requests"
                                 (list (ignore-errors
                                         (+gh--json "search" "prs" "--author" "@me" "--merged" "-L" "100"
                                                    "--merged-at" (format-time-string ">=%Y-%m-%d" (time-subtract nil (* 90 86400)))
                                                    "--json" "createdAt,closedAt,repository")))
                                 #'+gh--render-pr-metrics t)
                   (+gh--top "Searches" (+gh--count (lambda (v) (plist-get v :query)) visits)
                             (lambda (q) (+gh--search-repos q))))))))



(provide '+gh-pages)
;;; +gh-pages.el ends here
