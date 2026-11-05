;;; lisp/+org-graph.el --- The vault as a graph, in Emacs -*- lexical-binding: t; -*-
;;
;; Obsidian's graph view, in a buffer: notes as circles (larger the more
;; links they have, colored by their folder), links as lines, the note you
;; came from ringed.  Click a note (or RET on it in the list below) to open
;; it; hover for its title.  No browser, no server: SVG drawn by Emacs.
;;
;;   SPC n r g   the graph around this note (depth 1)
;;   +  -        one step further / nearer      a   the whole vault / local
;;   f           files and folders linked (images, PDFs …) shown or not
;;   u           unlinked mentions (a note naming another, unlinked), dashed
;;   g           read the vault again            q   quit
;;
;; The vault itself is read, not org-roam's database: that one records
;; id: links only, and most links here are file: links.  A note is an Org
;; file; a link is an id: link (resolved through org-roam) or a file: link
;; to another note.  Layout: Fruchterman-Reingold, spring-embedded, in Lisp.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'svg)

(defvar org-roam-directory)
(declare-function org-roam-db-query "ext:org-roam-db" (sql &rest args))

(defvar +org-graph-directory nil "The vault; nil: `org-roam-directory'.")
(defvar +org-graph-size '(900 . 600) "The graph's size in pixels.")

;;;; Reading the vault

(defun +org-graph--root ()
  (file-name-as-directory (expand-file-name (or +org-graph-directory (bound-and-true-p org-roam-directory) "~/vault/"))))

(defun +org-graph--filetag (file)
  "FILE's first #+filetags tag, or nil."
  (with-temp-buffer
    (insert-file-contents file nil 0 4000)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+filetags:[ \t]*:?\\([^: \t\n]+\\)" nil t)
      (match-string 1))))

(defun +org-graph--title (file)
  "FILE's #+title, else its name."
  (with-temp-buffer
    (insert-file-contents file nil 0 4000)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-base file))))

(defun +org-graph--ids ()
  "org-roam's ID → file, when org-roam is there."
  (let ((h (make-hash-table :test #'equal)))
    (when (fboundp 'org-roam-db-query)
      (ignore-errors
        (dolist (row (org-roam-db-query [:select [id file] :from nodes]))
          (puthash (car row) (expand-file-name (cadr row)) h))))
    h))

(defun +org-graph-read (&optional root)
  "The vault under ROOT as (NODES . EDGES).
NODES: hash FILE → plist (:title :group :kind); EDGES: list of (A . B)."
  (let* ((root (or root (+org-graph--root)))
         (files (directory-files-recursively root "\\.org\\'" nil
                                             (lambda (d) (not (string-match-p "/\\.git\\'" d)))))
         (ids (+org-graph--ids))
         (nodes (make-hash-table :test #'equal))
         edges)
    (dolist (f files)
      (let ((rel (file-relative-name f root)))
        (puthash f (list :title (+org-graph--title f)
                         ;; Its first tag, else its folder: top-level notes had one color.
                         :group (or (+org-graph--filetag f)
                                    (if (string-search "/" rel) (car (split-string rel "/")) ""))
                         :kind 'note)
                 nodes)))
    (dolist (f files)
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (while (re-search-forward "\\[\\[\\(id\\|file\\):\\([^]:][^]]*?\\)\\(?:::[^]]*\\)?\\]" nil t)
          (let* ((type (match-string 1)) (target (match-string 2))
                 (dest (if (equal type "id") (gethash target ids)
                         (expand-file-name target (file-name-directory f)))))
            (when (and dest (not (equal dest f)))
              (unless (gethash dest nodes)
                (puthash dest (list :title (abbreviate-file-name dest) :group "" :kind 'file) nodes))
              (cl-pushnew (cons f dest) edges :test #'equal))))))
    (cons nodes edges)))

(defun +org-graph-mentions (graph)
  "Unlinked mentions in GRAPH: (A . B) where note A's text names note B's
title (four letters or more) and doesn't link to it.  The links to make."
  (pcase-let ((`(,nodes . ,edges) graph))
    (let (titles out)
      (maphash (lambda (f n) (when (and (eq (plist-get n :kind) 'note) (>= (length (plist-get n :title)) 4))
                               (push (cons f (plist-get n :title)) titles)))
               nodes)
      (maphash
       (lambda (f n)
         (when (and (eq (plist-get n :kind) 'note) (file-readable-p f))
           (let ((text (with-temp-buffer (insert-file-contents f) (buffer-string)))
                 (case-fold-search t))
             (pcase-dolist (`(,g . ,title) titles)
               (when (and (not (equal f g))
                          (not (member (cons f g) edges)) (not (member (cons g f) edges))
                          (string-match-p (concat "\\b" (regexp-quote title) "\\b") text))
                 (push (cons f g) out))))))
       nodes)
      out)))

(defun +org-graph-local (graph center depth &optional files)
  "GRAPH cut to the notes within DEPTH links of CENTER (either way); FILES:
keep linked files that aren't notes."
  (pcase-let ((`(,nodes . ,edges) graph))
    (let ((keep (make-hash-table :test #'equal)) (frontier (list center)))
      (puthash center t keep)
      (dotimes (_ depth)
        (let (next)
          (dolist (e edges)
            (dolist (pair (list (cons (car e) (cdr e)) (cons (cdr e) (car e))))
              (when (and (member (car pair) frontier) (not (gethash (cdr pair) keep)))
                (puthash (cdr pair) t keep) (push (cdr pair) next))))
          (setq frontier next)))
      (+org-graph--filter graph (lambda (f) (and (gethash f keep) (or files (eq (plist-get (gethash f nodes) :kind) 'note) (equal f center))))))))

(defun +org-graph--filter (graph pred)
  "GRAPH with the nodes PRED keeps, and the edges between them."
  (pcase-let ((`(,nodes . ,edges) graph))
    (let ((kept (make-hash-table :test #'equal)))
      (maphash (lambda (k v) (when (funcall pred k) (puthash k v kept))) nodes)
      (cons kept (seq-filter (lambda (e) (and (gethash (car e) kept) (gethash (cdr e) kept))) edges)))))

;;;; Layout: Fruchterman-Reingold

(defun +org-graph-layout (graph width height &optional iterations)
  "Positions for GRAPH's nodes in WIDTH x HEIGHT: hash NODE → (X . Y)."
  (pcase-let* ((`(,nodes . ,edges) graph)
               (keys (hash-table-keys nodes))
               (n (max 1 (length keys)))
               (area (* width height))
               (k (* 0.75 (sqrt (/ (float area) n))))
               (pos (make-hash-table :test #'equal))
               (temp (/ width 8.0)))
    ;; A deterministic start: a circle (the same graph, the same picture).
    (cl-loop for key in (sort keys #'string<) for i from 0
             do (puthash key (cons (+ (/ width 2.0) (* (/ width 3.0) (cos (/ (* 2 float-pi i) n))))
                                   (+ (/ height 2.0) (* (/ height 3.0) (sin (/ (* 2 float-pi i) n)))))
                         pos))
    (dotimes (_ (or iterations 120))
      (let ((disp (make-hash-table :test #'equal)))
        (dolist (v keys) (puthash v (cons 0.0 0.0) disp))
        ;; Every pair repels.
        (cl-loop for (v . rest) on keys
                 do (dolist (u rest)
                      (let* ((pv (gethash v pos)) (pu (gethash u pos))
                             (dx (- (car pv) (car pu))) (dy (- (cdr pv) (cdr pu)))
                             (d (max 0.01 (sqrt (+ (* dx dx) (* dy dy)))))
                             (f (/ (* k k) d)))
                        (cl-incf (car (gethash v disp)) (* (/ dx d) f)) (cl-incf (cdr (gethash v disp)) (* (/ dy d) f))
                        (cl-decf (car (gethash u disp)) (* (/ dx d) f)) (cl-decf (cdr (gethash u disp)) (* (/ dy d) f)))))
        ;; Links attract.
        (dolist (e edges)
          (let* ((pv (gethash (car e) pos)) (pu (gethash (cdr e) pos))
                 (dx (- (car pv) (car pu))) (dy (- (cdr pv) (cdr pu)))
                 (d (max 0.01 (sqrt (+ (* dx dx) (* dy dy)))))
                 (f (/ (* d d) k)))
            (cl-decf (car (gethash (car e) disp)) (* (/ dx d) f)) (cl-decf (cdr (gethash (car e) disp)) (* (/ dy d) f))
            (cl-incf (car (gethash (cdr e) disp)) (* (/ dx d) f)) (cl-incf (cdr (gethash (cdr e) disp)) (* (/ dy d) f))))
        ;; A pull to the middle keeps loose notes in view.
        (dolist (v keys)
          (let ((p (gethash v pos)) (dd (gethash v disp)))
            (cl-incf (car dd) (* 0.08 (- (/ width 2.0) (car p))))
            (cl-incf (cdr dd) (* 0.08 (- (/ height 2.0) (cdr p))))
            (let* ((len (max 0.01 (sqrt (+ (* (car dd) (car dd)) (* (cdr dd) (cdr dd))))))
                   (step (min len temp)))
              (puthash v (cons (min (- width 30) (max 30 (+ (car p) (* (/ (car dd) len) step))))
                               (min (- height 30) (max 30 (+ (cdr p) (* (/ (cdr dd) len) step)))))
                       pos))))
        (setq temp (* temp 0.95))))
    ;; Fill the picture: the layout scaled into it, room right of each
    ;; node for its label.
    (let ((xs (mapcar #'car (hash-table-values pos))) (ys (mapcar #'cdr (hash-table-values pos))))
      (when (cdr xs)
        (let* ((x0 (apply #'min xs)) (x1 (max (1+ x0) (apply #'max xs)))
               (y0 (apply #'min ys)) (y1 (max (1+ y0) (apply #'max ys))))
          (maphash (lambda (k p)
                     (puthash k (cons (+ 30 (* (- width 230) (/ (- (car p) x0) (- x1 x0))))
                                      (+ 30 (* (- height 60) (/ (- (cdr p) y0) (- y1 y0)))))
                              pos))
                   pos))))
    pos))

;;;; Drawing

(defun +org-graph--palette ()
  (mapcar (lambda (face) (or (face-foreground face nil t) "#888888"))
          '(font-lock-keyword-face font-lock-function-name-face font-lock-string-face
            font-lock-type-face font-lock-constant-face font-lock-variable-name-face
            font-lock-builtin-face)))

(defun +org-graph--degree (edges)
  (let ((h (make-hash-table :test #'equal)))
    (dolist (e edges) (cl-incf (gethash (car e) h 0)) (cl-incf (gethash (cdr e) h 0)))
    h))

(defun +org-graph-svg (graph pos center &optional mentions)
  "GRAPH drawn at POS (CENTER ringed; MENTIONS dashed): (SVG . IMAGE-MAP)."
  (pcase-let* ((`(,nodes . ,edges) graph)
               (`(,w . ,h) +org-graph-size)
               (fg (or (face-foreground 'default nil t) "#000000"))
               (bg (or (face-background 'default nil t) "#ffffff"))
               (dim (or (face-foreground 'shadow nil t) "#888888"))
               (palette (+org-graph--palette))
               (groups (delete-dups (sort (mapcar (lambda (k) (plist-get (gethash k nodes) :group))
                                                  (hash-table-keys nodes))
                                          #'string<)))
               (degree (+org-graph--degree edges))
               (svg (svg-create w h))
               (map nil))
    (svg-rectangle svg 0 0 w h :fill bg)
    (dolist (e edges)
      (let ((a (gethash (car e) pos)) (b (gethash (cdr e) pos)))
        (svg-line svg (car a) (cdr a) (car b) (cdr b) :stroke dim :stroke-width 1.2 :stroke-opacity 0.6)))
    ;; Unlinked mentions: the links to make, dashed.
    (dolist (e mentions)
      (let ((a (gethash (car e) pos)) (b (gethash (cdr e) pos)))
        (when (and a b)
          (svg-line svg (car a) (cdr a) (car b) (cdr b) :stroke dim :stroke-width 1
                    :stroke-dasharray "4,4" :stroke-opacity 0.8))))
    (maphash
     (lambda (key node)
       (let* ((p (gethash key pos))
              (note (eq (plist-get node :kind) 'note))
              (r (if note (+ 6 (* 2.5 (sqrt (gethash key degree 0)))) 4))
              (color (if note (nth (mod (or (cl-position (plist-get node :group) groups :test #'equal) 0)
                                        (length palette))
                                   palette)
                       dim)))
         (when (equal key center)
           (svg-circle svg (car p) (cdr p) (+ r 5) :fill "none" :stroke fg :stroke-width 2))
         (svg-circle svg (car p) (cdr p) r :fill color :fill-opacity (if note 0.9 0.5))
         (when note
           (svg-text svg (truncate-string-to-width (plist-get node :title) 28 nil nil "…")
                     :x (+ (car p) r 3) :y (+ (cdr p) 4) :fill fg :font-size 12))
         (push (list (cons 'circle (cons (cons (round (car p)) (round (cdr p))) (round (+ r 3))))
                     (intern (concat "node:" key))
                     (list 'help-echo (plist-get node :title) 'pointer 'hand))
               map)))
     nodes)
    (cons svg map)))

;;;; The buffer

(defvar-local +org-graph--center nil "The note the graph is around.")
(defvar-local +org-graph--depth 1 "How many links out from it.")
(defvar-local +org-graph--all nil "The whole vault instead.")
(defvar-local +org-graph--files nil "Linked files that aren't notes too.")
(defvar-local +org-graph--mentions t "Unlinked mentions as dashed lines.")
(defvar-local +org-graph--map nil "Image map areas: node symbol → file.")

(defun +org-graph--open (file)
  (if (file-exists-p file) (find-file-other-window file) (message "Not there: %s" file)))

(defun +org-graph--click (event)
  "Open the note clicked in EVENT."
  (interactive "e")
  (let* ((area (posn-area (event-start event)))
         (name (and area (symbol-name area))))
    (when (and name (string-prefix-p "node:" name))
      (+org-graph--open (substring name 5)))))

(defvar +org-graph-mode-map)

(defun +org-graph-render ()
  "Draw this buffer's graph."
  (let* ((inhibit-read-only t)
         (graph (+org-graph-read))
         (graph (cond (+org-graph--all
                       (if +org-graph--files graph
                         (+org-graph--filter graph (lambda (f) (eq (plist-get (gethash f (car graph)) :kind) 'note)))))
                      (t (+org-graph-local graph +org-graph--center +org-graph--depth +org-graph--files))))
         (mentions (and +org-graph--mentions (+org-graph-mentions graph)))
         ;; Mentions pull too, so what belongs together comes near.
         (pos (+org-graph-layout (cons (car graph) (append (cdr graph) mentions))
                                 (car +org-graph-size) (cdr +org-graph-size)))
         (drawn (+org-graph-svg graph pos +org-graph--center mentions))
         (map (make-sparse-keymap)))
    (erase-buffer)
    (insert (propertize (if +org-graph--all "The vault" (format "Around %s, %d link%s out"
                                                               (plist-get (gethash +org-graph--center (car graph)) :title)
                                                               +org-graph--depth (if (= 1 +org-graph--depth) "" "s")))
                        'face 'bold)
            (propertize (format "   %d notes, %d links, %d unlinked mentions (dashed)   + - depth · a vault/local · f files · u mentions · g again · q quit\n"
                                (hash-table-count (car graph)) (length (cdr graph)) (length mentions))
                        'face 'shadow))
    (if (not (display-images-p))
        (insert "(the drawing needs a graphical frame; the notes are listed below)\n")
      (dolist (area (cdr drawn))
        (define-key map (vector (nth 1 area) 'mouse-1) #'+org-graph--click))
      (insert-image (svg-image (car drawn) :map (cdr drawn)) "[graph]")
      (insert "\n"))
    (setq-local +org-graph--map map)
    (use-local-map (make-composed-keymap map +org-graph-mode-map))
    ;; The same notes, for the keyboard: most linked first.
    (insert "\n")
    (let ((degree (+org-graph--degree (cdr graph))) rows)
      (maphash (lambda (k v) (push (list k v (gethash k degree 0)) rows)) (car graph))
      (dolist (row (sort rows (lambda (a b) (> (nth 2 a) (nth 2 b)))))
        (pcase-let ((`(,file ,node ,deg) row))
          (insert (format "%3d  " deg))
          (insert-text-button (plist-get node :title) 'action (lambda (_) (+org-graph--open file))
                              'help-echo (abbreviate-file-name file) 'follow-link t)
          (insert (propertize (format "  %s\n" (if (equal (plist-get node :group) "") "" (plist-get node :group))) 'face 'shadow)))))
    (goto-char (point-min))))

(defvar-keymap +org-graph-mode-map
  :parent special-mode-map
  "+" #'+org-graph-deeper "-" #'+org-graph-nearer "a" #'+org-graph-toggle-all
  "f" #'+org-graph-toggle-files "u" #'+org-graph-toggle-mentions "g" #'+org-graph-refresh)

(define-derived-mode +org-graph-mode special-mode "Graph"
  "The vault as a graph (see `+org/graph').")

(defun +org-graph-refresh () "Read the vault again." (interactive) (+org-graph-render))
(defun +org-graph-deeper () "One link further." (interactive) (cl-incf +org-graph--depth) (+org-graph-render))
(defun +org-graph-nearer () "One link nearer." (interactive)
       (setq +org-graph--depth (max 1 (1- +org-graph--depth))) (+org-graph-render))
(defun +org-graph-toggle-all () "The whole vault, or around the note." (interactive)
       (setq +org-graph--all (not +org-graph--all)) (+org-graph-render))
(defun +org-graph-toggle-files () "Linked files that aren't notes, or not." (interactive)
       (setq +org-graph--files (not +org-graph--files)) (+org-graph-render))
(defun +org-graph-toggle-mentions () "Unlinked mentions, or not." (interactive)
       (setq +org-graph--mentions (not +org-graph--mentions)) (+org-graph-render))

;;;###autoload
(defun +org/graph (&optional all)
  "The graph around this note; with ALL (C-u), the whole vault."
  (interactive "P")
  (let ((center (and buffer-file-name (expand-file-name buffer-file-name))))
    (with-current-buffer (get-buffer-create "*note graph*")
      (+org-graph-mode)
      (setq +org-graph--center center +org-graph--all (or all (null center)))
      (+org-graph-render)
      (pop-to-buffer (current-buffer)))))

(map! :leader :desc "Graph of the vault" "n r g" #'+org/graph)

(provide '+org-graph)
;;; +org-graph.el ends here
