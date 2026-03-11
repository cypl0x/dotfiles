;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; ---------------------------------------------------------------------------
;; Identity
;; ---------------------------------------------------------------------------

(setq user-full-name "Wolfhard Prell"
      user-mail-address "mail@wolfhard.net")

;; ---------------------------------------------------------------------------
;; UI
;; ---------------------------------------------------------------------------

(setq doom-font (font-spec :family "Cascadia Code NF" :size 14))
(setq doom-theme 'doom-vibrant)
(setq display-line-numbers-type t)

;; Date/time in modeline
(setq display-time-format "%Y-%m-%d %H:%M"
      display-time-24hr-format t)
(display-time-mode 1)

;; ---------------------------------------------------------------------------
;; Org
;; ---------------------------------------------------------------------------

;; Must be set before org loads.
(setq org-directory "~/notes/")

;; ---------------------------------------------------------------------------
;; Keep the folding state
;; ---------------------------------------------------------------------------

(use-package! savefold
  :init
  (setq savefold-backends '(outline org markdown))
  (setq savefold-directory (locate-user-emacs-file "savefold"))  ;; default

  :config
  (savefold-mode 1))

;; ---------------------------------------------------------------------------
;; Editor
;; ---------------------------------------------------------------------------

;; Unbounded kill ring — never discard yanked text.
(setq kill-ring-max most-positive-fixnum)

;; Persist kill ring across restarts.
(after! savehist
  ;; Persist a very large kill-ring history across restarts.
  (setq savehist-length most-positive-fixnum)
  (add-to-list 'savehist-additional-variables 'kill-ring)
  (savehist-mode 1))

;; Kill-ring / clipboard UX
(setq save-interprogram-paste-before-kill t
      yank-pop-change-selection t
      kill-do-not-save-duplicates t)

(after! consult
  (map! "M-y" #'consult-yank-pop
        :leader
        "y" #'consult-yank-pop))

(after! vertico
  (map! :map vertico-map
        "C-j" #'vertico-next
        "C-k" #'vertico-previous
        "C-h" #'vertico-directory-up
        "C-l" #'vertico-insert))

(defun +vertico-preview-candidate ()
  "Show the current Vertico candidate in a read-only buffer."
  (interactive)
  (let* ((cand (when (fboundp 'vertico--candidate)
                 (vertico--candidate)))
         (text (if (stringp cand) (substring-no-properties cand) "")))
    (with-current-buffer (get-buffer-create "*Kill Ring Preview*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min))
        (view-mode 1))
      (display-buffer (current-buffer)))))

(after! vertico
  (map! :map vertico-map
        "C-c C-o" #'+vertico-preview-candidate))

;; Wrap long candidates in the minibuffer (useful for consult-yank-pop).
(add-hook 'minibuffer-setup-hook
          (lambda ()
            (setq truncate-lines nil
                  word-wrap t)))

;; Buffer cycling on German keyboard layout (ö/ä instead of [/]).
(map! "M-ö" #'previous-buffer
      "M-ä" #'next-buffer)

;; ---------------------------------------------------------------------------
;; Packages
;; ---------------------------------------------------------------------------

(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; ---------------------------------------------------------------------------
;; Git / Version control
;; ---------------------------------------------------------------------------

;; ── Magit ──────────────────────────────────────────────────────────────────
(after! magit
  ;; Show word-granularity diffs in all hunks — spot tiny changes at a glance.
  (setq magit-diff-refine-hunk 'all))

;; ── Forge — GitHub / GitLab issue & PR management ─────────────────────────
;; Initial setup (once per machine):
;;   1. Add to ~/.authinfo.gpg:
;;        machine api.github.com login USERNAME^forge password GITHUB_TOKEN
;;   2. In a project magit buffer: M-x forge-add-repository  (pulls issues/PRs)
;;   3. Keybindings live under the magit "'" (forge-dispatch) transient.
(after! forge
  ;; Show up to 60 open and 20 recently-closed topics per repository.
  (setq forge-topic-list-limit '(60 . 20)))

;; ── magit-delta — syntax-highlighted diffs ─────────────────────────────────
;; Requires: delta binary  (cargo install git-delta  or  nix: pkgs.delta)
(use-package! magit-delta
  :hook (magit-mode . magit-delta-mode)
  :config
  ;; --color-only: let magit own the diff layout; delta only adds ANSI colours.
  ;; Omitting --line-numbers avoids hunk-staging breakage caused by delta
  ;; reformatting the diff offsets that magit relies on.
  (setq magit-delta-delta-args
        '("--max-line-distance" "0.6"
          "--true-color" "always"
          "--color-only")))

;; ── difftastic — structural, syntax-aware diffs ────────────────────────────
;; Understands language syntax: moved/renamed code shows as moves, not add+del.
;; Requires: difft binary  (cargo install difftastic  or  nix: pkgs.difftastic)
;; Usage: press "D" or "S" inside the magit-diff transient (C-c C-d / SPC g d).
(use-package! difftastic
  :after magit
  :config
  ;; Append difftastic commands to the end of the magit-diff transient.
  (transient-append-suffix 'magit-diff '(-1 -1)
    [("D" "Difftastic diff (dwim)" difftastic-magit-diff)
     ("S" "Difftastic show"        difftastic-magit-show)])
  ;; Enable default difftastic bindings (M-RET in blame, M-d in file dispatch).
  (difftastic-bindings-mode))

;; ── blamer.el — GitLens-style inline blame annotation ─────────────────────
(use-package! blamer
  :custom
  ;; Wait 0.5 s of idle time before rendering the annotation.
  (blamer-idle-time 0.5)
  ;; Start the annotation this many columns from the left edge.
  (blamer-min-offset 70)
  ;; Truncate long commit messages at 60 characters.
  (blamer-max-commit-message-length 60)
  ;; 'visual: annotate only the line the cursor is on (least intrusive).
  ;; 'both:   annotate every line.  'selected: annotate visual selection.
  (blamer-type 'visual)
  (blamer-author-formatter " %s ")
  (blamer-datetime-formatter "[%s] ")
  (blamer-commit-formatter "· %s")
  :config
  ;; Match the annotation colour to the comments face of the active theme.
  (custom-set-faces!
    `(blamer-face :foreground ,(doom-color 'comments) :italic t)))

;; ── magit-todos — TODO/FIXME/… section in magit status ────────────────────
(after! magit-todos
  ;; Keep in sync with hl-todo keywords.
  (setq magit-todos-keywords-list
        '("TODO" "FIXME" "HACK" "REVIEW" "NOTE" "DEPRECATED" "BUG")))

;; ── git-link — stable commit-hash permalink URLs ───────────────────────────
(use-package! git-link
  :config
  ;; Use commit hash rather than branch name → links survive branch renames.
  (setq git-link-use-commit t))

;; ── embark-vc — embark actions on VC / Magit candidates ───────────────────
(use-package! embark-vc
  :after (embark magit))

;; ── consult-ls-git — consult source: tracked files & recent commits ────────
(use-package! consult-ls-git
  :after consult)

;; ── consult-ghq — browse and jump to GHQ-managed repositories ─────────────
(use-package! consult-ghq
  :after consult)

;; ── gh-notify — GitHub notifications inside Emacs ─────────────────────────
(use-package! gh-notify
  :config
  ;; Show notifications updated within the last 48 hours.
  (setq gh-notify-max-time-since-update 48))

;; ── consult-gh — interactive GitHub CLI interface ──────────────────────────
;; Requires: gh CLI installed and authenticated via  gh auth login
;; Provides consult-style search for repos, issues, PRs, files, and code.
(use-package! consult-gh
  :after consult
  :config
  ;; Load optional embark integration (provides embark actions on gh results).
  (require 'consult-gh-embark nil t)
  (setq consult-gh-default-clone-directory "~/projects/"
        consult-gh-show-preview t))

;; ── smerge-mode — merge-conflict navigation & resolution ──────────────────
;; Auto-activate when opening a file that contains conflict markers.
(add-hook 'find-file-hook
          (lambda ()
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward "^<<<<<<" nil t)
                (smerge-mode 1)))))

;; ── Unified keybindings — SPC g ────────────────────────────────────────────
;; Doom already provides under SPC g:
;;   g/G  magit-status / here          b  magit-branch-checkout
;;   B    magit-blame-addition         t  git-timemachine-toggle
;;   d    diff prefix                  f  find prefix
;;   l    list prefix                  m  magit-merge prefix
;;   o    browse-at-remote prefix      r  rebase prefix
;;   s    stage prefix                 z  stash prefix
;; Below we fill in the remaining slots with our extra tools.
(map! :leader
      (:prefix ("g" . "git")
       ;; ── Inline annotations (blamer) ──────────────────────────────────
       ;; SPC g B  = magit-blame-addition  (line-by-line, enter Magit blame)
       ;; SPC g a  = blamer overlay        (idle, non-intrusive, current line)
       :desc "Toggle inline blame"          "a"  #'blamer-mode
       :desc "Show blame popup"             "A"  #'blamer-show-commit-info

       ;; ── Merge-conflict resolution (smerge) ──────────────────────────
       ;; Capital M to avoid collision with magit's lowercase 'm' merge prefix.
       (:prefix ("M" . "conflict")
        :desc "Next conflict"               "n"  #'smerge-next
        :desc "Prev conflict"               "p"  #'smerge-prev
        :desc "Keep mine (upper)"           "u"  #'smerge-keep-upper
        :desc "Keep theirs (lower)"         "l"  #'smerge-keep-lower
        :desc "Keep base"                   "b"  #'smerge-keep-base
        :desc "Keep current (at point)"     "m"  #'smerge-keep-current
        :desc "Keep all variants"           "a"  #'smerge-keep-all
        :desc "Auto-resolve"                "r"  #'smerge-resolve
        :desc "Open in ediff"               "e"  #'smerge-ediff)

       ;; ── Extend Doom's 'open in browser' prefix (SPC g o) ────────────
       ;; Existing: SPC g o o  browse-at-remote
       ;;           SPC g o y  copy URL to kill ring
       (:prefix ("o" . "open in browser")
        :desc "Copy permalink (hash)"       "l"  #'git-link
        :desc "Copy commit permalink"       "L"  #'git-link-commit)

       ;; ── Extend Doom's 'list' prefix (SPC g l) ───────────────────────
       ;; Existing: SPC g l i/p/n  forge issues/PRs/notifications
       ;;           SPC g l r/s/t/z  repos/submodules/todos/stashes
       (:prefix ("l" . "list")
        :desc "Files in repo (git ls)"      "g"  #'consult-ls-git
        :desc "Files in repo (other win)"   "G"  #'consult-ls-git-other-window)

       ;; ── GitHub hub (consult-gh + gh-notify) ─────────────────────────
       ;; Requires: gh auth login
       (:prefix ("h" . "github")
        :desc "Search repos"                "r"  #'consult-gh-search-repos
        :desc "Search issues"               "i"  #'consult-gh-search-issues
        :desc "Search pull requests"        "p"  #'consult-gh-search-prs
        :desc "Search code"                 "c"  #'consult-gh-search-code
        :desc "My issues"                   "I"  #'consult-gh-issue-list
        :desc "My pull requests"            "P"  #'consult-gh-pr-list
        :desc "Notifications"               "n"  #'gh-notify)

       ;; ── GHQ repository management ────────────────────────────────────
       :desc "Jump to repo (ghq)"           "q"  #'consult-ghq-find
       :desc "Grep across repos (ghq)"      "Q"  #'consult-ghq-grep))

(use-package! claude-code
  :config
  (global-set-key (kbd "C-c c") #'claude-code-transient)
  ;; Fall back to default-directory when not inside a Projectile project.
  (advice-add 'claude-code-run :around
    (lambda (orig-fn &rest args)
      (unless (projectile-project-root)
        (setq-local projectile-project-root default-directory))
      (apply orig-fn args))))

;; eat — terminal emulator in Eshell.
;; Provided by Nix (emacsPackages.eat); no package! declaration needed.
(after! eat
  (add-hook 'eshell-mode-hook #'eat-eshell-mode)
  (setq eat-term-name "xterm-256color"))

(with-eval-after-load 'eshell
  (load! "eshell/functions"))

;; ---------------------------------------------------------------------------
;; Language Server (LSP)
;; ---------------------------------------------------------------------------

(use-package! eglot-ltex
  :ensure t
  :hook (text-mode . (lambda ()
                       (require 'eglot-ltex)
                       (eglot-ensure)))
  :init
  ;; (setq eglot-ltex-server-path "path/to/ltex-ls-XX.X.X/"
  ;;       eglot-ltex-communication-channel 'stdio))
                                        ; 'stdio or 'tcp
)
;; ---------------------------------------------------------------------------
;; Universal app launcher (local lisp file)
;; ---------------------------------------------------------------------------

(load! "lisp/app-launcher")

;; ---------------------------------------------------------------------------
;; EXWM — only loaded when running as the window manager
;; SDDM sets DESKTOP_SESSION=exwm when the EXWM session is selected at login.
;; ---------------------------------------------------------------------------

(when (or (string= (getenv "DESKTOP_SESSION") "exwm")
          (string= (getenv "XDG_CURRENT_DESKTOP") "EXWM"))
  (load! "exwm"))

;; ---------------------------------------------------------------------------
;; Private config path override
;; SPC f p opens the dotfiles source instead of the read-only Nix store symlink.
;; ~/.config/doom/ is managed by home-manager; edits belong in ~/dotfiles/home/doom/.
;; ---------------------------------------------------------------------------

(defun doom/find-file-in-private-config ()
  "Browse the Doom config source in the dotfiles repository."
  (interactive)
  (doom-project-find-file (expand-file-name "~/dotfiles/home/doom/")))
