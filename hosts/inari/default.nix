{lib, pkgs, ...}: {
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
    ../../modules/system/nix-common.nix

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
  virtualisation.libvirtd.enable = true;

  # Work around libvirt unit using /usr/bin/sh (missing on NixOS)
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = lib.mkForce [
    "${pkgs.bash}/bin/sh -c 'umask 0077 && (dd if=/dev/random status=none bs=32 count=1 | systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
  ];

  users.users = {
    root.extraGroups = lib.mkAfter ["libvirtd" "kvm"];
    wap.extraGroups = lib.mkAfter ["libvirtd" "kvm"];
    cypl0x.extraGroups = lib.mkAfter ["libvirtd" "kvm"];
    proxy.extraGroups = lib.mkAfter ["libvirtd" "kvm"];
    fabian.extraGroups = lib.mkAfter ["libvirtd" "kvm"];
  };

  system.stateVersion = "24.11";

  # Push local builds to Cachix
  services.cachix-watch-store = {
    enable = true;
    cacheName = "cypl0x";
    cachixTokenFile = "/etc/cachix/cypl0x.token";
  };
}
