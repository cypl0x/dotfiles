_: {
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
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix

    # Host-specific configuration
    ./services.nix
  ];

  # Basic system settings
  boot = {
    tmp.cleanOnBoot = true;
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  zramSwap.enable = true;

  # Network configuration
  networking.hostName = "homelab";
  networking.domain = "";

  # System settings
  time.timeZone = "UTC";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = "23.11";
}
