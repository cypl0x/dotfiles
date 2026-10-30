;;; lisp/+nav.el --- Navigation, discovery, and help enhancements -*- lexical-binding: t; -*-
;;
;; Enhanced help system, embark extensions, pulsar navigation feedback,
;; sideline info display, and discovery transient menus.
;;
;;; Code:

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
        sideline-backends-right '(sideline-flymake)))

(use-package! sideline-flymake
  :after sideline)

;;;; elisp-demos — Examples in help ──────────────────────────────────────────

(use-package! elisp-demos
  :after helpful
  :config
  (advice-add 'helpful-update :after #'elisp-demos-advice-helpful-update))

;;;; envrc — Buffer-local direnv ─────────────────────────────────────────────

(use-package! envrc
  :config
  (envrc-global-mode))

;;;; Discovery transient — Master help menu ──────────────────────────────────

(transient-define-prefix +nav/help-transient ()
    "Master help and discovery menu."
    ["Describe"
     ("k" "Key"                describe-key)
     ("f" "Function"           helpful-callable)
     ("v" "Variable"           helpful-variable)
     ("F" "Face"               describe-face)
     ("m" "Mode"               describe-mode)
     ("p" "Package"            describe-package)]
    ["Lookup"
     ("a" "Apropos"            apropos-command)
     ("d" "Doom modules"       doom/help-modules)
     ("D" "Doom search"        doom/help)
     ("i" "Info manual"        info)
     ("l" "Library"            find-library)]
    ["Navigation"
     ("b" "Bindings"           describe-bindings)
     ("B" "Personal bindings"  describe-personal-keybindings)
     ("w" "Where is"           where-is)
     ("K" "Which-key top"      which-key-show-top-level)
     ("M" "Which-key keymap"   which-key-show-keymap)])

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

;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      :desc "Help/discover menu"  "?" #'+nav/help-transient
      :desc "Buffer menu"         "," #'+nav/buffer-transient

      ;; Append to existing window prefix — do NOT re-create with ("w" . "window").
      (:prefix "w"
       :desc "Swap windows"       "S" #'+nav/swap-windows
       :desc "Toggle maximize"    "M" #'+nav/toggle-maximize)

      ;; Append to existing search prefix — do NOT re-create with ("s" . "search").
      (:prefix "s"
       :desc "Project TODOs"      "T" #'+nav/search-project-todo
       :desc "Org headings"       "O" #'+nav/search-org-headings))

(provide '+nav)
;;; +nav.el ends here
