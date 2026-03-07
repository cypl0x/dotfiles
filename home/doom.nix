{...}: {
  imports = [./emacs-deps.nix];

  # Doom Emacs configuration files, managed as read-only Nix store symlinks.
  #
  # custom.el is intentionally excluded: Emacs writes to it via M-x customize
  # and the Nix store is read-only. Doom creates it automatically when absent.
  #
  # After a home-manager switch, run `doom sync` once to rebuild Doom's
  # straight.el profile if init.el or packages.el changed.
  home.file = {
    ".config/doom/config.el".source = ./doom/config.el;
    ".config/doom/init.el".source = ./doom/init.el;
    ".config/doom/packages.el".source = ./doom/packages.el;
    ".config/doom/exwm.el".source = ./doom/exwm.el;
    ".config/doom/lisp/app-launcher.el".source = ./doom/lisp/app-launcher.el;
  };
}
