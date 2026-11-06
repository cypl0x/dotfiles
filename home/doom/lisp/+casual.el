;;; lisp/+casual.el --- SPC m m: what can I do here, as a menu, in every mode Casual knows -*- lexical-binding: t; -*-
;;
;; Casual (kickingvegas/casual) has a Magit-style menu for many of Emacs's
;; own modes.  Org's was already on SPC m m (+org-power.el); now that key
;; opens the menu of the mode you are in, wherever there is one:
;;
;;   dired  ibuffer  Info  agenda  bookmarks  help  man  image  csv
;;   calendar  compilation  make  eshell  eww  re-builder
;;
;; In calc (Emacs state, no SPC) and in isearch (C-s, /) it is C-o, as
;; Casual's own docs suggest.  C-ß y opens it too, and C-ß's search knows
;; "editing menu" (EditKit: everything about editing in one menu).
;;
;;; Code:

(defvar +casual-menus
  '((dired-mode          dired-mode-map          casual-dired-tmenu     casual-dired     dired)
    (ibuffer-mode        ibuffer-mode-map        casual-ibuffer-tmenu   casual-ibuffer   ibuffer)
    (Info-mode           Info-mode-map           casual-info-tmenu      casual-info      info)
    (org-agenda-mode     org-agenda-mode-map     casual-agenda-tmenu    casual-agenda    org-agenda)
    (bookmark-bmenu-mode bookmark-bmenu-mode-map casual-bookmarks-tmenu casual-bookmarks bookmark)
    (help-mode           help-mode-map           casual-help-tmenu      casual-help      help-mode)
    (Man-mode            Man-mode-map            casual-man-tmenu       casual-man       man)
    (image-mode          image-mode-map          casual-image-tmenu     casual-image     image-mode)
    (csv-mode            csv-mode-map            casual-csv-tmenu       casual-csv       csv-mode)
    (calendar-mode       calendar-mode-map       casual-calendar-tmenu  casual-calendar  calendar)
    (compilation-mode    compilation-mode-map    casual-compile-tmenu   casual-compile   compile)
    (makefile-mode       makefile-mode-map       casual-make-tmenu      casual-make      make-mode)
    (eshell-mode         eshell-mode-map         casual-eshell-tmenu    casual-eshell    esh-mode)
    (eww-mode            eww-mode-map            casual-eww-tmenu       casual-eww       eww)
    (reb-mode            reb-mode-map            casual-re-builder-tmenu casual-re-builder re-builder)
    (calc-mode           calc-mode-map           casual-calc-tmenu      casual-calc      calc))
  "(MODE MAP MENU LIBRARY AFTER): Casual's menu for MODE, from LIBRARY,
bound in MAP once AFTER is loaded.")

(defun +casual-menu-here ()
  "Casual's menu for this buffer's mode (or one it derives from), or nil."
  (cl-loop for (mode _ menu lib) in +casual-menus
           when (derived-mode-p mode)
           return (progn (require lib nil t) (and (fboundp menu) menu))))

;;;###autoload
(defun +casual/menu-here ()
  "What can I do here: Casual's menu for this mode."
  (interactive)
  (call-interactively (or (+casual-menu-here)
                          (user-error "No Casual menu for %s (C-ß: what is here)" major-mode))))

(pcase-dolist (`(,_mode ,map ,menu ,lib ,after) +casual-menus)
  (autoload menu (symbol-name lib) nil t)
  (with-eval-after-load after
    (when (boundp map)
      (if (eq map 'calc-mode-map)
          (define-key (symbol-value map) (kbd "C-o") menu)
        ;; map! wants the keymap's name as written.
        (eval `(map! :map ,map :localleader :desc "What can I do here (menu)" "m" #',menu) t)))))

(autoload 'casual-isearch-tmenu "casual-isearch" nil t)
(autoload 'casual-editkit-main-tmenu "casual-editkit" nil t)
(with-eval-after-load 'isearch
  (define-key isearch-mode-map (kbd "C-o") #'casual-isearch-tmenu))

(provide '+casual)
;;; +casual.el ends here
