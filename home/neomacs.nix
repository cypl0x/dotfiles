{
  config,
  lib,
  pkgs,
  neomacs,
  ...
}:
# NEO Emacs (github.com/eval-exec/neomacs, Emacs's C core rewritten in Rust)
# as a second Emacs for testing, beside the main one, with the same Doom
# config.  Nothing here shadows `emacs' or `emacsclient':
#
#   neomacs             NEO Emacs v0.0.20 running ~/.config/doom, its Doom
#                       build in ~/.local/share/neomacs-doom (the package
#                       checkouts are the main Emacs's, linked: nothing is
#                       cloned twice), server name "neomacs"
#   neomacs-doom-sync   `doom sync' for it (byte-compiles the packages with
#                       NEO Emacs; run once after a switch, and after
#                       `doom sync' changes packages)
#
# The release is prebuilt in eval-exec.cachix.org (modules/system/nix-common.nix).
lib.mkIf (config.home.username == "wap") (let
  neo = neomacs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  local = "${config.xdg.dataHome}/neomacs-doom/";
  setup = ''
    local=${lib.escapeShellArg local}
    mkdir -p "$local/straight"
    # The main Emacs's package checkouts, shared (builds stay separate).
    [ -e "$local/straight/repos" ] || ln -s "$HOME/.config/emacs/.local/straight/repos" "$local/straight/repos"
    export DOOMLOCALDIR="$local" NEOMACS_DOOM=1
    # Upstream defaults to RUST_LOG=info: some 125 KB/s into the terminal while
    # you work (205 MB in half an hour), each line written as it happens, so
    # a busy terminal makes neomacs wait.  Warnings and errors only; set
    # RUST_LOG yourself for more.
    export RUST_LOG="''${RUST_LOG:-warn}"
  '';
in {
  home.packages = [
    (pkgs.writeShellScriptBin "neomacs" ''
      ${setup}
      exec ${neo}/bin/neomacs --init-directory "$HOME/.config/emacs" "$@"
    '')
    (pkgs.writeShellScriptBin "neomacs-doom-sync" ''
      ${setup}
      export EMACS=${neo}/bin/neomacs
      exec "$HOME/.config/emacs/bin/doom" sync "$@"
    '')
  ];
})
