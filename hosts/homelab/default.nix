_: {
  imports = [
    # Hardware and platform configuration
    ./hardware.nix

    # System modules
    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/monitoring.nix
    ../../modules/system/assertions.nix

    # Service modules
    ../../modules/services/nginx.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/tor.nix
    ../../modules/services/fail2ban.nix

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
  # 200 GB/month ÷ (30 days × 86400 s) ≈ 80 KB/s sustained rate
  torRelay.bandwidthRate = 80;
  torRelay.bandwidthBurst = 200;

  time.timeZone = "UTC";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # OpenSSH AcceptEnv (NixOS unstable uses list format)
  # Allow LC_TERMINAL for ShellFish
  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. Before changing, review the release notes.
  system.stateVersion = "24.11";
}
