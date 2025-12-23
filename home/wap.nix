{ config, pkgs, lib, ... }:

{
  imports = [ ./common.nix ];

  home.username = "wap";

  # Work specific git config
  programs.git = {
    userName = lib.mkForce "Work Account";
    userEmail = lib.mkForce "wap@work.com"; # Placeholder
  };
}
