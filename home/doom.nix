{
  config,
  lib,
  ...
}: let
  # wap edits Doom from the live checkout: lisp/ and snippets/ link straight
  # into ~/dotfiles (out of store), so a saved file is live after `load-file'
  # with no rebuild, and new modules need no hand-made symlink. Other users
  # have no checkout and get store copies.
  live = config.home.username == "wap";
  checkout = path:
    config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/dotfiles/home/doom/${path}";
in {
  imports = [./emacs-deps.nix];

  # Doom Emacs configuration files, managed as read-only Nix store symlinks.
  #
  # custom.el is intentionally excluded: Emacs writes to it via M-x customize
  # and the Nix store is read-only. Doom creates it automatically when absent.
  #
  # After a home-manager switch, run `doom sync` once to rebuild Doom's
  # straight.el profile if init.el or packages.el changed.
  home.file = lib.mkMerge [
    {
      ".config/doom/config.el".source = ./doom/config.el;
      ".config/doom/init.el".source = ./doom/init.el;
      ".config/doom/packages.el".source = ./doom/packages.el;
    }
    (lib.mkIf live {
      ".config/doom/lisp".source = checkout "lisp";
      ".config/doom/snippets".source = checkout "snippets";
    })
    (lib.mkIf (!live) {
      ".config/doom/lisp/app-launcher.el".source = ./doom/lisp/app-launcher.el;
    })
  ];
}
