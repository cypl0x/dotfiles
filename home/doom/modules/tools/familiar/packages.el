;; -*- no-byte-compile: t; -*-
;;; tools/familiar/packages.el

;; familiar is its own package (lisp/familiar/, MELPA-ready), installed from
;; this checkout.  Not byte-compiled: the build links the sources, so a saved
;; file is live after `load-file', as for the rest of lisp/; straight still
;; makes its autoloads.
(package! familiar
  :recipe (:local-repo "../../../lisp/familiar"
           :files ("*.el")
           :build (:not compile native-compile)))

;; Its optional dependencies: mcp-server-lib for the bridge agents use
;; (familiar-mcp), mcp.el for MCP servers as tools and their sampling
;; requests (familiar-mcp-client, familiar-mcp-sampling).
(package! mcp)
(package! mcp-server-lib)
