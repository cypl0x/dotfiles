;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; Several third-party packages below (claude-code, ollama-buddy, ...) call
;; transient-define-prefix at their top level to define a menu. transient is
;; a macro, so straight's normal dependency handling — loading a dependency's
;; *autoloads* before building a dependent package — isn't enough to make it
;; visible; autoloads only provide lazy function stubs, not macros. Without
;; the real feature loaded, `doom sync`'s autoload generator doesn't
;; recognize transient-define-prefix and inlines the raw form into the
;; dependent package's *-autoloads.el, which then fails to load with
;; "Symbol's function definition is void: transient-define-prefix". `:tools
;; magit` already builds transient earlier in this same sync, so a plain
;; `require' here (not just `package!', which only registers/builds) is
;; enough to make the macro available for everything built after this line.
(require 'transient)

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
(package! agent-recall)              ;; Search/browse agent-shell transcripts
(package! agent-shell-attention)     ;; Modeline attention tracker
(package! agent-shell-math-renderer) ;; LaTeX math rendering in agent-shell
(package! ob-agent-shell)            ;; Org-babel backend for agent-shell
(package! aider)             ;; aider.el — CLI pair-programming, drives `aider` on PATH

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

;; ghostel: now provided via Doom's :term ghostel module (init.el).
;; evil-ghostel still needed as explicit package.
(package! evil-ghostel)      ;; evil-mode keybindings for ghostel buffers

;; ---------------------------------------------------------------------------
;; Reading
;; ---------------------------------------------------------------------------

(package! nov)                 ;; epub reader

;; ---------------------------------------------------------------------------
;; Misc utilities
;; ---------------------------------------------------------------------------

(package! leo)                 ;; dict.leo.org translation (word lookup, DE<->EN)
;; gt: multi-engine translation incl. DeepL. Explicit recipe — the bare name
;; isn't in Doom's straight recipe repos (doom sync: "Could not find package").
(package! go-translate
  :recipe (:host github :repo "lorniu/go-translate"))
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
;; Org — knowledge management, agenda, visual polish
;; ---------------------------------------------------------------------------

(package! org-roam)            ;; Zettelkasten: bidirectional links, knowledge graph
(package! consult-org-roam)    ;; Vertico integration for org-roam
(package! org-super-agenda)    ;; Group/filter org-agenda into readable sections
(package! org-ql)              ;; SQL-like query language for org
(package! org-modern)          ;; Modern visual styling (bullets, tables, tags)
(package! org-appear)          ;; Auto-reveal markup at point (links, emphasis)
(package! org-transclusion)    ;; Live embed content from other org files
(package! org-noter)           ;; Synchronized PDF/document annotation
(package! org-download)        ;; Paste/drag images into org
(package! citar)               ;; Citation management with org integration
(package! citar-org-roam)      ;; Bridge citar + org-roam bibliographic notes

;; ---------------------------------------------------------------------------
;; Writing / prose
;; ---------------------------------------------------------------------------

(package! jinx)                ;; Enchant-based spellchecker (faster than flyspell)
(package! mixed-pitch)         ;; Variable-pitch in prose, fixed-pitch in code
(package! svg-tag-mode)        ;; Replace text tags with SVG badges
(package! typst-ts-mode)       ;; Tree-sitter mode for typst
(package! powerthesaurus)       ;; Thesaurus via powerthesaurus.org

;; ---------------------------------------------------------------------------
;; AI / LLM — extensions
;; ---------------------------------------------------------------------------

(package! gptel)               ;; LLM client in any buffer (Claude, GPT, Ollama)
(package! ob-lean              ;; Org-babel for Lean 4 code blocks
  :recipe (:host github :repo "0xAX/ob-lean"))

;; ---------------------------------------------------------------------------
;; Completion / UI
;; ---------------------------------------------------------------------------

(package! nerd-icons-corfu)    ;; Icons in corfu completion popup
(package! pulsar)              ;; Pulse current line after big motions
(package! sideline)            ;; Show info in sideline (diagnostics, blame, etc.)
(package! sideline-flymake)    ;; Flymake diagnostics in sideline

;; ---------------------------------------------------------------------------
;; Nix / system
;; ---------------------------------------------------------------------------

(package! envrc)               ;; Buffer-local direnv (critical for NixOS + TRAMP)

;; ---------------------------------------------------------------------------
;; Navigation / discovery
;; ---------------------------------------------------------------------------

(package! elisp-demos)         ;; Inject usage examples into *help* buffers

;; ---------------------------------------------------------------------------
;; Disabled / under evaluation
;; ---------------------------------------------------------------------------

;; (package! kdeconnect)        ;; KDE Connect — not needed in EXWM sessions
;; (package! magithub)          ;; superseded by forge


;; ---------------------------------------------------------------------------
;; Vellumory, the PDF reader (:tools vellumory, home/vellumory.nix)
;; ---------------------------------------------------------------------------

;; The module's own recipe tracks GitHub main; pin it to the release the flake
;; builds the worker from (flake.nix: github:cypl0x/vellumory/v0.1.0).
(package! vellumory
  :recipe (:host github :repo "cypl0x/vellumory" :files ("lisp/*.el"))
  :pin "7cdddc3f917da629063ee3f22f03f7f1f0440042") ; v0.1.0
