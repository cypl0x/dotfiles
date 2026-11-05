;;; lisp/+org-canvas.el --- An infinite board of cards, as an Org file -*- lexical-binding: t; -*-
;;
;; Obsidian's Canvas, kept as text: a canvas is an Org file (canvas/NAME.org
;; in the vault), each card a heading whose properties place it (:X: :Y:),
;; whose body is its text, and which may stand for a note (:NOTE:, a file);
;; :TO: lists the cards it points to.  The board draws them (SVG, the
;; theme's colors) and you work on it from the keyboard or the mouse:
;;
;;   SPC n r C   open or start a canvas
;;   n / N       a text card / a card for a note     e   edit the card's text
;;   TAB         select the next card (click selects too)
;;   arrows      move it         c   connect it to another    d   delete it
;;   RET         open its note   H J K L  pan    + -  zoom    g  redraw
;;
;; Changes go into the canvas file through its Emacs buffer, saved.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'org)

(declare-function +org-graph--root "+org-graph" ())

(defvar +org-canvas-step 40 "Pixels a card moves per arrow key.")
(defvar +org-canvas-card '(220 . 90) "A card's size in pixels.")

;;;; The file

(defun +org-canvas-cards (file)
  "FILE's cards: list of plists (:id :title :text :x :y :note :to :pos)."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (let (cards)
       (org-map-entries
        (lambda ()
          (push (list :id (or (org-entry-get nil "CUSTOM_ID") (org-id-get-create))
                      :title (org-get-heading t t t t)
                      :text (string-trim (buffer-substring-no-properties
                                          (save-excursion (org-end-of-meta-data t) (point))
                                          (save-excursion (org-end-of-subtree t) (point))))
                      :x (string-to-number (or (org-entry-get nil "X") "40"))
                      :y (string-to-number (or (org-entry-get nil "Y") "40"))
                      :note (org-entry-get nil "NOTE")
                      :to (split-string (or (org-entry-get nil "TO") "") " " t)
                      :pos (point))
                cards))
        "LEVEL=1")
       (nreverse cards)))))

(defun +org-canvas--at (file id fn)
  "Call FN at card ID's heading in FILE's buffer, then save it."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (goto-char (point-min))
     (when (or (re-search-forward (format "^[ \t]*:\\(?:CUSTOM_\\)?ID:[ \t]+%s[ \t]*$" (regexp-quote id)) nil t))
       (org-back-to-heading t)
       (funcall fn)))
    (save-buffer)))

(defun +org-canvas-add (file title &optional note text x y)
  "Add a card TITLE (for NOTE, with TEXT) at X Y to FILE; its id."
  (let ((id (format "card-%s" (format-time-string "%Y%m%d%H%M%S%3N"))))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-max))
       (unless (bolp) (insert "\n"))
       (insert "* " title "\n")
       (org-entry-put nil "CUSTOM_ID" id)
       (org-entry-put nil "X" (number-to-string (or x 40)))
       (org-entry-put nil "Y" (number-to-string (or y 40)))
       (when note (org-entry-put nil "NOTE" note))
       (when text (org-end-of-meta-data t) (insert text "\n")))
      (save-buffer))
    id))

;;;; Drawing

(defvar-local +org-canvas--file nil "The canvas file shown.")
(defvar-local +org-canvas--selected nil "The selected card's id.")
(defvar-local +org-canvas--offset '(0 . 0) "Pan: the board's top left.")
(defvar-local +org-canvas--zoom 1.0 "Zoom.")

(defun +org-canvas-svg (cards selected offset zoom width height)
  "CARDS drawn in WIDTH x HEIGHT (OFFSET, ZOOM; SELECTED marked): (SVG . MAP)."
  (let* ((fg (or (face-foreground 'default nil t) "#000000"))
         (bg (or (face-background 'default nil t) "#ffffff"))
         (card-bg (or (and (facep 'org-block) (face-background 'org-block nil t))
                     (and (facep 'hl-line) (face-background 'hl-line nil t)) bg))
         (accent (or (face-foreground 'font-lock-keyword-face nil t) fg))
         (dim (or (face-foreground 'shadow nil t) fg))
         (cw (* zoom (car +org-canvas-card))) (ch (* zoom (cdr +org-canvas-card)))
         (svg (svg-create width height)) map)
    (svg-rectangle svg 0 0 width height :fill bg)
    (cl-flet ((sx (c) (* zoom (- (plist-get c :x) (car offset))))
              (sy (c) (* zoom (- (plist-get c :y) (cdr offset)))))
      ;; Arrows first, under the cards: center to center.
      (dolist (c cards)
        (dolist (to (plist-get c :to))
          (when-let* ((d (cl-find to cards :key (lambda (k) (plist-get k :id)) :test #'equal)))
            (let* ((x1 (+ (sx c) (/ cw 2))) (y1 (+ (sy c) (/ ch 2)))
                   (x2 (+ (sx d) (/ cw 2))) (y2 (+ (sy d) (/ ch 2)))
                   (dx (- x2 x1)) (dy (- y2 y1))
                   ;; Where the line meets the target card's edge: the head goes there.
                   (s (min (if (zerop dx) 1e9 (/ (/ cw 2) (abs dx))) (if (zerop dy) 1e9 (/ (/ ch 2) (abs dy)))))
                   (ex (- x2 (* dx s))) (ey (- y2 (* dy s)))
                   (len (max 1 (sqrt (+ (* dx dx) (* dy dy)))))
                   (ux (/ dx len)) (uy (/ dy len)) (head 10))
              (svg-line svg x1 y1 ex ey :stroke dim :stroke-width 1.5)
              (svg-polygon svg (list (cons ex ey)
                                     (cons (- ex (* head ux) (* 0.5 head uy)) (- ey (* head uy) (* -0.5 head ux)))
                                     (cons (- ex (* head ux) (* -0.5 head uy)) (- ey (* head uy) (* 0.5 head ux))))
                           :fill dim)))))
      (dolist (c cards)
        (let ((x (sx c)) (y (sy c)) (sel (equal (plist-get c :id) selected)))
          (svg-rectangle svg x y cw ch :rx 8 :fill card-bg
                         :stroke (if sel accent dim) :stroke-width (if sel 3 1))
          (svg-text svg (truncate-string-to-width (concat (if (plist-get c :note) "▣ " "") (plist-get c :title)) 26 nil nil "…")
                    :x (+ x 10) :y (+ y (* zoom 22)) :fill fg :font-size (round (* zoom 14)) :font-weight "bold")
          (cl-loop for line in (seq-take (split-string (plist-get c :text) "\n" t) 3) for i from 1
                   do (svg-text svg (truncate-string-to-width line 32 nil nil "…")
                                :x (+ x 10) :y (+ y (* zoom (+ 22 (* 18 i)))) :fill dim :font-size (round (* zoom 12))))
          (push (list (cons 'rect (cons (cons (round x) (round y)) (cons (round (+ x cw)) (round (+ y ch)))))
                      (intern (concat "card:" (plist-get c :id)))
                      (list 'help-echo (plist-get c :title) 'pointer 'hand))
                map))))
    (cons svg map)))

(defun +org-canvas--card-click (event)
  "Select the card clicked in EVENT."
  (interactive "e")
  (let ((name (symbol-name (or (posn-area (event-start event)) 'none))))
    (when (string-prefix-p "card:" name)
      (setq +org-canvas--selected (substring name 5))
      (+org-canvas-render))))

(defvar +org-canvas-mode-map)

(defun +org-canvas-render ()
  "Draw this buffer's canvas."
  (let* ((inhibit-read-only t)
         (cards (+org-canvas-cards +org-canvas--file))
         (win (get-buffer-window (current-buffer)))
         (w (max 600 (if win (- (window-body-width win t) 20) 900)))
         (h (max 400 (if win (- (window-body-height win t) 60) 600)))
         (drawn (+org-canvas-svg cards +org-canvas--selected +org-canvas--offset +org-canvas--zoom w h))
         (map (make-sparse-keymap)))
    (unless (or +org-canvas--selected (null cards))
      (setq +org-canvas--selected (plist-get (car cards) :id)))
    (erase-buffer)
    (insert (propertize (file-name-base +org-canvas--file) 'face 'bold)
            (propertize (format "   %d cards · n/N card · e edit · TAB select · arrows move · c connect · d delete · RET note · HJKL pan · +- zoom\n"
                                (length cards))
                        'face 'shadow))
    (dolist (area (cdr drawn)) (define-key map (vector (nth 1 area) 'mouse-1) #'+org-canvas--card-click))
    (use-local-map (make-composed-keymap map +org-canvas-mode-map))
    (if (display-images-p)
        (insert-image (svg-image (car drawn) :map (cdr drawn)) "[canvas]")
      (dolist (c cards) (insert (format "  %s%s\n" (if (equal (plist-get c :id) +org-canvas--selected) "▶ " "  ") (plist-get c :title)))))
    (goto-char (point-min))))

;;;; Commands

(defun +org-canvas--selected-card ()
  (or (cl-find +org-canvas--selected (+org-canvas-cards +org-canvas--file)
               :key (lambda (c) (plist-get c :id)) :test #'equal)
      (user-error "No card selected (n makes one)")))

(defun +org-canvas-new (title)
  "A text card TITLE, below the selected one."
  (interactive "sCard title: ")
  (let* ((sel (ignore-errors (+org-canvas--selected-card)))
         (id (+org-canvas-add +org-canvas--file title nil nil
                              (if sel (plist-get sel :x) (+ 40 (car +org-canvas--offset)))
                              (if sel (+ (plist-get sel :y) (cdr +org-canvas-card) 30) (+ 40 (cdr +org-canvas--offset))))))
    (setq +org-canvas--selected id)
    (+org-canvas-render)))

(defun +org-canvas-new-note (file)
  "A card for the note FILE (asked from the vault)."
  (interactive (list (read-file-name "Note: " (+org-graph--root) nil t)))
  (let* ((title (with-temp-buffer (insert-file-contents file nil 0 2000) (goto-char (point-min))
                                  (if (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t) (match-string 1) (file-name-base file))))
         (sel (ignore-errors (+org-canvas--selected-card)))
         (id (+org-canvas-add +org-canvas--file title (abbreviate-file-name file) nil
                              (if sel (+ (plist-get sel :x) (car +org-canvas-card) 40) 40)
                              (if sel (plist-get sel :y) 40))))
    (setq +org-canvas--selected id)
    (+org-canvas-render)))

(defun +org-canvas-move (dx dy)
  "Move the selected card by DX DY steps."
  (let ((c (+org-canvas--selected-card)))
    (+org-canvas--at +org-canvas--file (plist-get c :id)
                     (lambda ()
                       (org-entry-put nil "X" (number-to-string (+ (plist-get c :x) (* dx +org-canvas-step))))
                       (org-entry-put nil "Y" (number-to-string (+ (plist-get c :y) (* dy +org-canvas-step))))))
    (+org-canvas-render)))

(defun +org-canvas-left () "Move left." (interactive) (+org-canvas-move -1 0))
(defun +org-canvas-right () "Move right." (interactive) (+org-canvas-move 1 0))
(defun +org-canvas-up () "Move up." (interactive) (+org-canvas-move 0 -1))
(defun +org-canvas-down () "Move down." (interactive) (+org-canvas-move 0 1))

(defun +org-canvas-next ()
  "Select the next card."
  (interactive)
  (let* ((ids (mapcar (lambda (c) (plist-get c :id)) (+org-canvas-cards +org-canvas--file)))
         (i (or (cl-position +org-canvas--selected ids :test #'equal) -1)))
    (setq +org-canvas--selected (nth (mod (1+ i) (max 1 (length ids))) ids))
    (+org-canvas-render)))

(defun +org-canvas-connect ()
  "Point the selected card to another (asked by title)."
  (interactive)
  (let* ((c (+org-canvas--selected-card))
         (others (seq-remove (lambda (k) (equal (plist-get k :id) (plist-get c :id))) (+org-canvas-cards +org-canvas--file)))
         (pick (completing-read "Connect to: " (mapcar (lambda (k) (plist-get k :title)) others) nil t))
         (target (cl-find pick others :key (lambda (k) (plist-get k :title)) :test #'equal)))
    (+org-canvas--at +org-canvas--file (plist-get c :id)
                     (lambda () (org-entry-put nil "TO" (string-join (delete-dups (append (plist-get c :to) (list (plist-get target :id)))) " "))))
    (+org-canvas-render)))

(defun +org-canvas-delete ()
  "Delete the selected card (and arrows to it)."
  (interactive)
  (let ((c (+org-canvas--selected-card)))
    (when (y-or-n-p (format "Delete the card %s? " (plist-get c :title)))
      (+org-canvas--at +org-canvas--file (plist-get c :id)
                       (lambda () (delete-region (point) (save-excursion (org-end-of-subtree t t) (point)))))
      (dolist (k (+org-canvas-cards +org-canvas--file))
        (when (member (plist-get c :id) (plist-get k :to))
          (+org-canvas--at +org-canvas--file (plist-get k :id)
                           (lambda () (org-entry-put nil "TO" (string-join (remove (plist-get c :id) (plist-get k :to)) " "))))))
      (setq +org-canvas--selected nil)
      (+org-canvas-render))))

(defun +org-canvas-edit ()
  "Edit the selected card's text (the canvas file, at that card)."
  (interactive)
  (let ((c (+org-canvas--selected-card)) (file +org-canvas--file))
    (find-file-other-window file)
    (goto-char (plist-get c :pos))
    (org-fold-show-subtree)
    (org-end-of-meta-data t)))

(defun +org-canvas-open ()
  "Open the selected card's note."
  (interactive)
  (let ((c (+org-canvas--selected-card)))
    (if-let* ((note (plist-get c :note))) (find-file-other-window (expand-file-name note))
      (+org-canvas-edit))))

(defun +org-canvas--pan (dx dy)
  (setq +org-canvas--offset (cons (+ (car +org-canvas--offset) (* dx 200)) (+ (cdr +org-canvas--offset) (* dy 150))))
  (+org-canvas-render))
(defun +org-canvas-pan-left () "Pan left." (interactive) (+org-canvas--pan -1 0))
(defun +org-canvas-pan-right () "Pan right." (interactive) (+org-canvas--pan 1 0))
(defun +org-canvas-pan-up () "Pan up." (interactive) (+org-canvas--pan 0 -1))
(defun +org-canvas-pan-down () "Pan down." (interactive) (+org-canvas--pan 0 1))
(defun +org-canvas-zoom-in () "Zoom in." (interactive) (setq +org-canvas--zoom (* +org-canvas--zoom 1.2)) (+org-canvas-render))
(defun +org-canvas-zoom-out () "Zoom out." (interactive) (setq +org-canvas--zoom (/ +org-canvas--zoom 1.2)) (+org-canvas-render))
(defun +org-canvas-redraw () "Redraw." (interactive) (+org-canvas-render))

(defvar-keymap +org-canvas-mode-map
  :parent special-mode-map
  "n" #'+org-canvas-new "N" #'+org-canvas-new-note "e" #'+org-canvas-edit
  "TAB" #'+org-canvas-next "c" #'+org-canvas-connect "d" #'+org-canvas-delete
  "RET" #'+org-canvas-open "g" #'+org-canvas-redraw
  "<left>" #'+org-canvas-left "<right>" #'+org-canvas-right
  "<up>" #'+org-canvas-up "<down>" #'+org-canvas-down
  "H" #'+org-canvas-pan-left "L" #'+org-canvas-pan-right
  "K" #'+org-canvas-pan-up "J" #'+org-canvas-pan-down
  "+" #'+org-canvas-zoom-in "-" #'+org-canvas-zoom-out)

(define-derived-mode +org-canvas-mode special-mode "Canvas"
  "A canvas of cards (see `+org/canvas').")

;; Evil's normal state would take these keys; the board is a special buffer.
(with-eval-after-load 'evil
  (when (fboundp 'evil-set-initial-state) (evil-set-initial-state '+org-canvas-mode 'emacs)))

;;;###autoload
(defun +org/canvas (name)
  "Open the canvas NAME (canvas/NAME.org in the vault), made if new."
  (interactive
   (let ((dir (expand-file-name "canvas/" (+org-graph--root))))
     (list (completing-read "Canvas: " (and (file-directory-p dir)
                                            (mapcar #'file-name-base (directory-files dir nil "\\.org\\'")))))))
  (let* ((dir (expand-file-name "canvas/" (+org-graph--root)))
         (file (expand-file-name (concat name ".org") dir)))
    (make-directory dir t)
    (unless (file-exists-p file)
      (with-temp-file file (insert (format "#+title: Canvas: %s\n\n" name))))
    (with-current-buffer (get-buffer-create (format "*canvas: %s*" name))
      (+org-canvas-mode)
      (setq +org-canvas--file file)
      (pop-to-buffer (current-buffer))
      (+org-canvas-render))))

(map! :leader :desc "Canvas (cards on a board)" "n r C" #'+org/canvas)

(provide '+org-canvas)
;;; +org-canvas.el ends here
