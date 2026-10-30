;;; lisp/+proced.el --- ps aux | rg …; kill N, as one live buffer -*- lexical-binding: t; -*-
;;
;; Built from atuin evidence (2026-10-30, all thinkpad history): `ps aux'
;; piped into rg, fzf, bat or wl-copy to find a PID, then `kill N' (41
;; kills).  Emacs's own proced is that loop: SPC o k lists every process
;; with its command line, refreshing while visible.  f narrows to command
;; lines matching a regexp (the `| rg' step), o… sorts, m marks, x sends a
;; signal (evil-collection keys); in
;; short, ps aux | rg … and kill N without leaving Emacs.
;;
;;; Code:

(defvar proced-auto-update-flag)
(defvar proced-auto-update-interval)
(defvar proced-enable-color-flag)
(defvar proced-format)
(defvar proced-filter)
(defvar proced-filter-alist)
(defvar evil-snipe-disabled-modes)

;; proced makes these buffer-local, so `setq' here would only reach the
;; buffer this happens to load in.
(with-eval-after-load 'proced
  (setq-default proced-auto-update-flag 'visible   ; refresh only while on screen
        proced-auto-update-interval 2
        proced-enable-color-flag t
        proced-format 'medium              ; user, pid, %cpu, %mem, args …
        proced-filter 'all))               ; `sudo ps aux', not just yours

(declare-function proced-update "proced" (&optional revert quiet))

(defun +proced/grep (regexp)
  "Show only processes whose command line matches REGEXP, like ps aux | rg.
An empty REGEXP shows all processes again."
  (interactive (list (read-regexp "Command line matches (empty: all)")))
  ;; A named entry in `proced-filter-alist': older proced (Emacs 30) takes
  ;; only names there, not a list of filters.
  (setf (alist-get '+proced-grep proced-filter-alist) `((args . ,regexp)))
  (setq proced-filter (if (string-empty-p regexp) 'all '+proced-grep))
  (proced-update t))

;; f filters in stock proced; evil-snipe would take it (and s) otherwise.
(after! evil-snipe
  (add-to-list 'evil-snipe-disabled-modes 'proced-mode))
(map! :map proced-mode-map :n "f" #'+proced/grep)

(map! :leader :desc "Processes (proced)" "o k" #'proced)

(provide '+proced)
;;; +proced.el ends here
