;;; lisp/+nav.el --- Navigation, discovery, and help enhancements -*- lexical-binding: t; -*-
;;
;; Enhanced help system, embark extensions, pulsar navigation feedback,
;; sideline info display, and discovery transient menus.
;;
;;; Code:

(require 'cl-lib)

;;;; pulsar — Visual navigation feedback ─────────────────────────────────────

(use-package! pulsar
  :config
  (setq pulsar-pulse t
        pulsar-delay 0.05
        pulsar-iterations 10
        pulsar-face 'pulsar-magenta)
  ;; Pulse after navigation commands.
  (dolist (fn '(recenter-top-bottom
                move-to-window-line-top-bottom
                reposition-window
                bookmark-jump
                other-window
                delete-window
                delete-other-windows
                forward-page
                backward-page
                scroll-up-command
                scroll-down-command
                windmove-right
                windmove-left
                windmove-up
                windmove-down
                +lookup/definition
                +lookup/references
                org-next-visible-heading
                org-previous-visible-heading
                org-forward-heading-same-level
                org-backward-heading-same-level))
    (add-to-list 'pulsar-pulse-functions fn))
  (pulsar-global-mode 1))

;;;; sideline — Show info alongside code ─────────────────────────────────────

(use-package! sideline
  :hook (prog-mode . sideline-mode)
  :config
  (setq sideline-display-backend-name t
        ;; Diagnostics come from flycheck (:checkers syntax), not flymake.
        sideline-backends-right '(sideline-flycheck)))

(use-package! sideline-flycheck
  :hook (flycheck-mode . sideline-flycheck-setup))

;;;; elisp-demos — Examples in help ──────────────────────────────────────────

(use-package! elisp-demos
  :after helpful
  :config
  (advice-add 'helpful-update :after #'elisp-demos-advice-helpful-update))

;; The help menu that was here is C-ß / SPC ? now (lisp/+discover.el).

(transient-define-prefix +nav/buffer-transient ()
    "Buffer operations."
    ["Switch"
     ("b" "Switch buffer"       consult-buffer)
     ("B" "All buffers"         ibuffer)
     ("p" "Project buffers"     consult-project-buffer)
     ("r" "Recent files"        consult-recent-file)]
    ["Actions"
     ("s" "Save"                save-buffer)
     ("S" "Save all"            evil-write-all)
     ("k" "Kill buffer"         kill-current-buffer)
     ("K" "Kill others"         doom/kill-other-buffers)
     ("n" "New"                 evil-buffer-new)
     ("R" "Revert"              revert-buffer-quick)]
    ["Navigate"
     ("l" "Goto line"           consult-goto-line)
     ("o" "Outline"             consult-outline)
     ("i" "Imenu"               consult-imenu)
     ("m" "Bookmark"            consult-bookmark)])

;;;; M-ö / M-ä — every buffer, in a ring ────────────────────────────────────
;;
;; `previous-buffer' walks only the window's own history, and Doom's frame
;; `buffer-predicate' skips "unreal" buffers: *Info*, popups, *scratch*,
;; anything without a file.  These walk all of them (Emacs's hidden ones,
;; named with a leading space, aside), most recent first.  The order is
;; taken at the first press, so a run of presses doesn't reshuffle it; the
;; buffer you stop on counts as visited once you do something else.

(defvar +buffer-ring--commands '(+buffer/previous +buffer/next))
(defvar +buffer-ring--list nil "The buffers of the run of presses going on.")

(defun +buffer-ring--buffers ()
  (cl-remove-if (lambda (b) (string-prefix-p " " (buffer-name b))) (buffer-list)))

(defun +buffer-ring--done-h ()
  "A run of presses ended: the buffer it stopped on was visited."
  (unless (memq this-command +buffer-ring--commands)
    (remove-hook 'pre-command-hook #'+buffer-ring--done-h)
    (setq +buffer-ring--list nil)
    (select-window (selected-window))))  ; puts it first in `buffer-list'

(defun +buffer-ring--step (n)
  (unless (and +buffer-ring--list (memq last-command +buffer-ring--commands))
    (setq +buffer-ring--list (+buffer-ring--buffers))
    (add-hook 'pre-command-hook #'+buffer-ring--done-h))
  (setq +buffer-ring--list (cl-remove-if-not #'buffer-live-p +buffer-ring--list))
  (let* ((ring +buffer-ring--list)
         (i (or (cl-position (current-buffer) ring) 0))
         (buf (nth (mod (+ i n) (length ring)) ring)))
    (when buf
      (switch-to-buffer buf t t))))   ; norecord: the order stays put

(defun +buffer/previous (&optional n)
  "The buffer visited before this one, of all buffers (Info, popups, scratch…)."
  (interactive "p")
  (+buffer-ring--step (or n 1)))

(defun +buffer/next (&optional n)
  "The other way round from `+buffer/previous': the least recent first."
  (interactive "p")
  (+buffer-ring--step (- (or n 1))))

;;;; SPC b U — reopen what you closed ─────────────────────────────────────────
;;
;; Like a browser's Ctrl-Shift-T: the file buffers you killed, newest first,
;; each where you were in it (point, window start).  SPC b U reopens the
;; last one; with C-u, pick one.  Kept across restarts (savehist).  From
;; M-x attempts: "reop" (2026-11-05), nothing matched it.

(defvar +buffer-closed nil
  "Files of killed buffers, newest first: (FILE POINT WINDOW-START TIME).")
(defvar +buffer-closed-max 50 "How many closed files are remembered.")

(defun +buffer--remember-closed-h ()
  "Remember this file buffer, being killed, to reopen it."
  (when-let* ((file buffer-file-name))
    (let ((win (get-buffer-window (current-buffer))))
      (setq +buffer-closed
            (seq-take (cons (list (abbreviate-file-name file) (point)
                                  (if win (window-start win) (point))
                                  (float-time))
                            (seq-remove (lambda (e) (equal (car e) (abbreviate-file-name file)))
                                        +buffer-closed))
                      +buffer-closed-max)))))

(defvar savehist-additional-variables)
(add-hook 'kill-buffer-hook #'+buffer--remember-closed-h)
(with-eval-after-load 'savehist
  (add-to-list 'savehist-additional-variables '+buffer-closed))

(defun +buffer--closed-open ()
  "The remembered closed files that exist and aren't open now."
  (seq-filter (lambda (e) (and (file-exists-p (car e)) (not (find-buffer-visiting (car e)))))
              +buffer-closed))

(defun +buffer/reopen-closed (&optional pick)
  "Reopen the file buffer closed last, where you were in it.
With PICK (\\[universal-argument]), choose among those closed before."
  (interactive "P")
  (let* ((closed (or (+buffer--closed-open) (user-error "No closed file to reopen")))
         (entry (if (not pick) (car closed)
                  (let* ((cands (mapcar (lambda (e)
                                          (cons (format "%s  (%s ago)" (car e)
                                                        (format-seconds "%Y, %D, %H, %M%z" (- (float-time) (nth 3 e))))
                                                e))
                                        closed)))
                    (cdr (assoc (completing-read "Reopen: " cands nil t) cands))))))
    (pcase-let ((`(,file ,pos ,start . ,_) entry))
      (find-file file)
      (goto-char (min pos (point-max)))
      (set-window-start (selected-window) (min start (point-max))))))

(map! :leader :desc "Reopen closed buffer (C-u: pick)" "b U" #'+buffer/reopen-closed)

;;;; Window management enhancements ──────────────────────────────────────────

(defun +nav/swap-windows ()
  "Swap the current window's buffer with the next window's buffer."
  (interactive)
  (let* ((this-win (selected-window))
         (next-win (next-window))
         (this-buf (window-buffer this-win))
         (next-buf (window-buffer next-win)))
    (set-window-buffer this-win next-buf)
    (set-window-buffer next-win this-buf)
    (select-window next-win)))

(defun +nav/toggle-maximize ()
  "Toggle between maximizing the current window and restoring layout."
  (interactive)
  (if (= 1 (length (window-list)))
      (when (get-register :+nav-layout)
        (jump-to-register :+nav-layout))
    (window-configuration-to-register :+nav-layout)
    (delete-other-windows)))

;;;; Search enhancements ─────────────────────────────────────────────────────

(defun +nav/search-project-todo ()
  "Search for TODO/FIXME/HACK/NOTE comments in the current project."
  (interactive)
  (consult-ripgrep (or (projectile-project-root) default-directory)
                   "\\b(TODO|FIXME|HACK|BUG|NOTE|REVIEW)\\b"))

(defun +nav/search-org-headings ()
  "Search all org headings across org-directory."
  (interactive)
  (consult-org-heading nil
                       (directory-files-recursively
                        org-directory "\\.org$")))

;;;; Copy a file's name ─────────────────────────────────────────────────────
;; SPC f y copies the path; kill-file-path was run through M-x 6 times for
;; the same.  These two copy just the name.

(defun +file--yank (name)
  (if (not name)
      (user-error "No file here")
    (kill-new name)
    (message "Copied: %s" name)))

;;;###autoload
(defun +file/yank-name ()
  "Copy this buffer's file name, without its directory."
  (interactive)
  (+file--yank (and buffer-file-name (file-name-nondirectory buffer-file-name))))

;;;###autoload
(defun +file/yank-base-name ()
  "Copy this buffer's file name without directory and extension."
  (interactive)
  (+file--yank (and buffer-file-name (file-name-base buffer-file-name))))

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      :desc "Buffer menu"         "," #'+nav/buffer-transient

      ;; Append to existing window prefix — do NOT re-create with ("w" . "window").
      (:prefix "w"
       :desc "Swap windows"       "S" #'+nav/swap-windows
       :desc "Toggle maximize"    "M" #'+nav/toggle-maximize)

      (:prefix "f"
       :desc "Yank file name"     "n" #'+file/yank-name
       :desc "Yank name, no ext." "N" #'+file/yank-base-name)

      ;; Append to existing search prefix — do NOT re-create with ("s" . "search").
      (:prefix "s"
       :desc "Project TODOs"      "T" #'+nav/search-project-todo
       :desc "Org headings"       "O" #'+nav/search-org-headings))

(provide '+nav)
;;; +nav.el ends here
