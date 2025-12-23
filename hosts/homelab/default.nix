{ pkgs, ... }: {
  imports = [
    # Hardware and platform configuration
    ./hardware.nix

    # System modules
    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/monitoring.nix

    # Service modules
    ../../modules/services/nginx.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/tor.nix

    # User configuration
    ../../modules/users/root.nix

    # Host-specific configuration
    ./services.nix
  ];

  # Basic system settings
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  # Network configuration
  networking.hostName = "homelab";
  networking.domain = "";

  # Boot loader configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # System settings
  time.timeZone = "UTC";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "23.11";
}
