{ config, pkgs, lib, ... }:

{
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  time.timeZone = "UTC";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
