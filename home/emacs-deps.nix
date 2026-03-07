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
    # nil (Nix LSP) is installed system-wide in hosts/thinkpad
    # dart LSP is bundled with the dart SDK in hosts/thinkpad

    # direnv integration (tools/direnv module)
    direnv

    # app-launcher.el: window focus and .desktop file launching
    wmctrl # window switching via wmctrl -a
    xdg-utils # provides gtk-launch for .desktop app launching
  ];
}
