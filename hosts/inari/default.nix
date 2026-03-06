_: {
  imports = [
    ./hardware.nix
    ./disk.nix
    ./services.nix
    ./nextcloud.nix
    ./gui-proxy.nix
    ./gui-fabian.nix

    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/monitoring.nix
    ../../modules/system/assertions.nix

    ../../modules/services/nginx.nix
    ../../modules/services/mosh.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/tor.nix

    ../../modules/users/root.nix
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix
    ../../modules/users/proxy.nix
    ../../modules/users/fabian.nix
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  networking = {
    hostName = "inari";
    domain = "";
    useDHCP = false;
    useNetworkd = true;
    enableIPv6 = true;
    nameservers = [
      "185.12.64.1"
      "2a01:4ff:ff00::add:2"
    ];
  };

  systemd.network = {
    enable = true;
    networks."10-wan" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
      dhcpV4Config = {
        UseDNS = false;
      };
    };
  };

  torRelay.nickname = "inari";

  time.timeZone = "UTC";
  nix.settings.experimental-features = ["nix-command" "flakes"];
  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];

  system.stateVersion = "24.11";
}
