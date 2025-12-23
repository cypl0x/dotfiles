# Home Manager configuration for the root user.
# This file is intentionally left empty for now to resolve a build error.
# Add home-manager options for the root user here if needed.
{ config, pkgs, ... }: {
  home = {
    username = "root";
    homeDirectory = "/root";
    stateVersion = "23.11";
  };
}