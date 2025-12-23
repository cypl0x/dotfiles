{ config, pkgs, lib, ... }:

{
  imports = [ ./common.nix ];

  home.username = "wap";

  # Work specific git config
  programs.git = {
    settings = {
      user.name = lib.mkForce "Work Account";
      user.email = lib.mkForce "wap@work.com"; # Placeholder
    };
  };
}
