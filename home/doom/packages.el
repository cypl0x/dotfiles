;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or
;; use 'M-x doom/reload'.


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; (package! org-cv)
;; (package! org-modern)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;; (package! this-package
;;   :recipe (:host github :repo "username/repo"
;;            :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;; (package! builtin-package :recipe (:nonrecursive t))
;; (package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
;; (package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")


;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)

(package! rainbow-delimiters)

;; EXWM: Emacs as the X11 window manager (loaded only in EXWM sessions)
(package! exwm)

;; Spookfox: Emacs <-> Firefox bridge for fuzzy tab switching via Vertico
;; Also requires the Spookfox Firefox extension:
;;   https://github.com/bitspook/spookfox/releases  (download the .xpi)
(package! spookfox
  :recipe (:host github :repo "bitspook/spookfox"
           :files ("lisp/*.el")))
(package! nov) ;; ebook / epub reader

(package! kdeconnect)

(package! mcp)
(package! mcp-server-lib)
(package! org-mcp)
(package! elisp-dev-mcp)

(package! claude-code)
(package! codex-cli)
(package! agent-shell)
(package! ollama-buddy)
(package! chatgpt-shell)
(package! copilot)
;; (package! monet)
(package! monet :recipe '(:host github :repo "stevemolitor/monet"))

(package! exwm-firefox-evil)
(package! exwm-mff) ;; exwm follow mouse

(package! frameshot)

(package! magit-delta)
(package! git-undo)
(package! blamer)
(package! embark-vc)
(package! github-browse-file)
(package! github-explorer)
(package! git-walktree)
(package! gited)
(package! git-wip-timemachine)
(package! gh-notify)
;; (package! magithub)
(package! my-repo-pins)
(package! consult-ghq)
(package! consult-ls-git)
(package! dashboard-project-status)
(package! git-lens)
(package! git-link)
(package! gh)

;; (package! lsp-nix) # obsolete due to eglot

(package! leo)

;; (package! mutli-vterm)
(package! mutli-vterm :recipe (:host github :repo "suonlight/multi-vterm"))
;; (package! eat)
;; eat is provided via Nix (emacsPackages.eat) — straight.el management removed
;; to avoid broken byte-compilation in the NixOS sandbox.
;; (package! eat :recipe (:host codeberg :repo "akib/emacs-eat"))

;; (package! app-launcher)
