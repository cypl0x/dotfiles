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

(package! magit-delta)         ;; delta pager integration for magit
(package! blamer)              ;; inline git blame
(package! git-link)            ;; copy GitHub/GitLab permalink
(package! github-browse-file)  ;; open file on GitHub
(package! git-undo)
(package! embark-vc)
(package! gh)
(package! gh-notify)
(package! my-repo-pins)
(package! consult-ghq)
(package! consult-ls-git)

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
;; Disabled / under evaluation
;; ---------------------------------------------------------------------------

;; (package! kdeconnect)        ;; KDE Connect — not needed in EXWM sessions
;; (package! magithub)          ;; superseded by forge

