_: {
  imports = [
    ./hardware.nix
    ./disk.nix
    ./services.nix

    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/monitoring.nix
    ../../modules/system/assertions.nix

    ../../modules/services/nginx.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/tor.nix
    ../../modules/services/fail2ban.nix

    ../../modules/users/root.nix
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  networking.hostName = "inari";
  networking.domain = "";

  time.timeZone = "UTC";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];

  system.stateVersion = "24.11";
}
