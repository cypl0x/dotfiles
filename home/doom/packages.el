;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; ---------------------------------------------------------------------------
;; UI / Editor
;; ---------------------------------------------------------------------------

(package! rainbow-delimiters)

;; ---------------------------------------------------------------------------
;; Save the state of the folding in org-mode
;; ---------------------------------------------------------------------------

(package! savefold)

;; ---------------------------------------------------------------------------
;; Kill ring
;; ---------------------------------------------------------------------------

(package! kill-file-path)
;; (package! clipetty)
;; (package! clipmon)

;; ---------------------------------------------------------------------------
;; EXWM — X11 window manager
;; Loaded only in EXWM sessions (guarded in config.el).
;; ---------------------------------------------------------------------------

(package! exwm)
(package! exwm-mff)            ;; focus-follows-mouse
;; (package! exwm-firefox-evil) ;; disabled — not used, conflicts with Tridactyl

;; Spookfox: Emacs <-> Firefox bridge (fuzzy tab switching via Vertico).
;; Also requires the browser extension:
;;   https://github.com/bitspook/spookfox/releases  (.xpi)
(package! spookfox
  :recipe (:host github :repo "bitspook/spookfox"
           :files ("lisp/*.el")))

;; ---------------------------------------------------------------------------
;; AI / LLM
;; ---------------------------------------------------------------------------

(package! claude-code)
(package! chatgpt-shell)
(package! codex-cli)         ;; OpenAI Codex CLI
(package! ollama-buddy)
(package! copilot)
(package! agent-shell)

;; MCP (Model Context Protocol) tooling
(package! mcp)
(package! mcp-server-lib)
(package! org-mcp)
(package! elisp-dev-mcp)

;; ---------------------------------------------------------------------------
;; Git / Version control
;; ---------------------------------------------------------------------------

(package! magit-delta)         ;; delta pager — syntax-highlighted diffs
(package! difftastic)          ;; structural, syntax-aware diffs (via difft binary)
(package! blamer)              ;; GitLens-style inline blame overlay
(package! git-link)            ;; stable commit-hash permalink URLs
(package! github-browse-file)  ;; open file on GitHub in browser
(package! git-undo)            ;; undo git operations
(package! embark-vc)           ;; embark actions for VC / Magit candidates
(package! gh)                  ;; GitHub API client (Elisp)
(package! gh-notify)           ;; GitHub notifications in Emacs
(package! my-repo-pins)        ;; pin / bookmark repositories
(package! consult-ghq)         ;; consult source for GHQ-managed repos
(package! consult-ls-git)      ;; consult source for tracked files & commits
(package! consult-gh)          ;; interactive GitHub CLI interface (uses gh binary)

;; Less commonly used git tools — enable as needed:
;; (package! github-explorer)
;; (package! git-walktree)
;; (package! gited)
;; (package! git-wip-timemachine)
;; (package! dashboard-project-status)
;; (package! git-lens)

;; ---------------------------------------------------------------------------
;; Terminal
;; ---------------------------------------------------------------------------

;; eat is provided via Nix (emacsPackages.eat) — do not manage via straight.el,
;; it causes broken byte-compilation in the NixOS sandbox.
;; (package! eat :recipe (:host codeberg :repo "akib/emacs-eat"))

(package! multi-vterm
  :recipe (:host github :repo "suonlight/multi-vterm"))

;; ---------------------------------------------------------------------------
;; Reading
;; ---------------------------------------------------------------------------

(package! nov)                 ;; epub reader

;; ---------------------------------------------------------------------------
;; Misc utilities
;; ---------------------------------------------------------------------------

(package! leo)                 ;; dict.leo.org translation
(package! frameshot)           ;; screenshot tool
(package! monet
  :recipe (:host github :repo "stevemolitor/monet"))

;; ---------------------------------------------------------------------------
;; Elisp linting / development
;; ---------------------------------------------------------------------------

(package! elisp-autofmt)
(package! package-lint)
(package! elsa)

;; ---------------------------------------------------------------------------
;; Language Server (LSP)
;; ---------------------------------------------------------------------------

(package! eglot-ltex :recipe (:host github :repo "emacs-languagetool/eglot-ltex"))

;; ---------------------------------------------------------------------------
;; Disabled / under evaluation
;; ---------------------------------------------------------------------------

;; (package! kdeconnect)        ;; KDE Connect — not needed in EXWM sessions
;; (package! magithub)          ;; superseded by forge

