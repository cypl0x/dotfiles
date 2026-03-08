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
    nodePackages.typescript-language-server # lang/javascript +lsp
    nodePackages.bash-language-server # lang/sh +lsp
    copilot-language-server
    ltex-ls # LanguageTool language server
    ltex-ls-plus # LanguageTool language server (plus)
    marksman # markdown language server
    # nil (Nix LSP) is installed system-wide in hosts/thinkpad
    # dart LSP is bundled with the dart SDK in hosts/thinkpad

    # treesitter
    tree-sitter-grammars.tree-sitter-nix
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

    # app-launcher.el: window focus and .desktop file launching
    wmctrl # window switching via wmctrl -a
    xdg-utils # provides gtk-launch for .desktop app launching
  ];
}
