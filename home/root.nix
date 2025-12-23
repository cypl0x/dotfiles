# Home Manager configuration for the root user.
# This file is intentionally left empty for now to resolve a build error.
# Add home-manager options for the root user here if needed.
{ config, pkgs, lib, ... }: {
  home.username = "root";
  home.homeDirectory = lib.mkForce "/root"; # Explicitly set home directory for root

  # Import common home-manager configurations
  imports = [
    ./common.nix
  ];

  # The root user doesn't share the same shell config as wap and cypl0x
  # So we will override it to use zsh
  programs.zsh.enable = true;

}