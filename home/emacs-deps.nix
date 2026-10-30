{pkgs, ...}: {
  # Binary dependencies for Doom Emacs modules.
  # These are tools that Doom packages shell out to at runtime.
  # The Doom config itself lives in home/doom/ and is linked via home/doom.nix.
  home.packages = with pkgs; [
    # mu4e (email/mu4e +org +gmail module)
    mu # maildir indexer and mu4e backend
    isync # mbsync: IMAP sync daemon

    # LSP servers (tools/lsp +eglot module)
    rust-analyzer # lang/rust +lsp
    typescript-language-server # lang/javascript +lsp
    bash-language-server # lang/sh +lsp
    copilot-language-server
    ltex-ls # LanguageTool language server
    ltex-ls-plus # LanguageTool language server (plus)
    marksman # markdown language server
    # nil (Nix LSP) is installed system-wide in hosts/thinkpad
    # dart LSP is bundled with the dart SDK in hosts/thinkpad

    # treesitter (:tools tree-sitter module — required by lang/dart, lang/nix,
    # lang/rust's +tree-sitter flags; doom doctor errors without it)
    tree-sitter-grammars.tree-sitter-nix
    # tree-sitter-grammars.tree-sitter-dart # conflicts with tree-sitter-nix (queries/tags.scm)
    # tree-sitter-grammars.tree-sitter-rust # conflicts with tree-sitter nix
    # tree-sitter-grammars.tree-sitter-elisp
    # tree-sitter-grammars.tree-sitter-elisp
    # tree-sitter-grammars.tree-sitter-yaml
    # tree-sitter-grammars.tree-sitter-vim
    # tree-sitter-grammars.tree-sitter-tsx
    # tree-sitter-grammars.tree-sitter-toml
    # tree-sitter-grammars.tree-sitter-regex
    # tree-sitter-grammars.tree-sitter-python
    # tree-sitter-grammars.tree-sitter-markdown
    # tree-sitter-grammars.tree-sitter-make
    # tree-sitter-grammars.tree-sitter-latex
    # tree-sitter-grammars.tree-sitter-kotlin
    # tree-sitter-grammars.tree-sitter-json
    # tree-sitter-grammars.tree-sitter-javascript
    # tree-sitter-grammars.tree-sitter-typescript
    # tree-sitter-grammars.tree-sitter-html
    # tree-sitter-grammars.tree-sitter-css
    # tree-sitter-grammars.tree-sitter-haskell
    # tree-sitter-grammars.tree-sitter-dockerfile
    # tree-sitter-grammars.tree-sitter-cpp
    # tree-sitter-grammars.tree-sitter-commonlisp
    # tree-sitter-grammars.tree-sitter-c
    # tree-sitter-grammars.tree-sitter-bash
    # tree-sitter-grammars.tree-sitter-yaml

    # direnv integration (tools/direnv module)
    direnv

    # doom doctor: linters/formatters/screenshot tool it looks for on PATH
    nixfmt # lang/nix nix-format-buffer
    shellcheck # lang/sh script linting
    html-tidy # lang/web HTML formatting
    stylelint # lang/web CSS linting
    js-beautify # lang/web JS/CSS/HTML formatting
    ktlint # lang/kotlin flycheck-kotlin
    gnuplot # lang/org +gnuplot, org-plot/gnuplot
    maim # lang/org org-download-clipboard

    # app-launcher.el: window focus and .desktop file launching
    wmctrl # window switching via wmctrl -a
    xdg-utils # provides gtk-launch for .desktop app launching

    # vterm (term/vterm module) compiles a native module on first use via
    # SPC o T — it needs the full C toolchain, not just cmake.
    cmake
    libtool
    gnumake
    gcc

    # jinx spell-checker (lisp/+prose.el) — runtime + build deps for jinx-mod.so
    enchant_2
    pkg-config # jinx build finds enchant via pkg-config

    # org-roam-graph needs `dot` from graphviz
    graphviz

    # difftastic.el (config.el: magit diff menu D/S) runs the difft binary
    difftastic
  ];
}
