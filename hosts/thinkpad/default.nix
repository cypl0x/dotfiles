{
  lib,
  pkgs,
  ...
}: let
  sddmElementaryTheme = pkgs.stdenvNoCC.mkDerivation {
    pname = "sddm-elementary-os-theme";
    version = "git-bfbc671";
    src = pkgs.fetchFromGitHub {
      owner = "zayronxio";
      repo = "sddmElementaryOs";
      rev = "bfbc67127e440dd1d7757815ac7f7efec3000e6a";
      hash = "sha256-WRzkfV14AtbLqi+GRGbBl0CAtnbtfvIJ/Ta0q1Mjxjw=";
    };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/sddm/themes/sddmElementaryOs"
      cp -R ./* "$out/share/sddm/themes/sddmElementaryOs/"
      runHook postInstall
    '';
  };
in {
  imports = [
    # Hardware and platform configuration
    ./hardware.nix

    # System modules
    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/nix-common.nix
    ../../modules/system/locale.nix
    ../../modules/system/desktop.nix
    ../../modules/system/exwm.nix
    ../../modules/services/tailscale.nix

    # User configuration
    ../../modules/users/root.nix
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix
    ../../modules/users/proxy.nix

    # Host-specific configuration
    ./pantheon.nix
    ./thinkpad-packages.nix
  ];

  # Bootloader configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Network configuration
  networking = {
    hostName = "thinkpad";
    networkmanager.enable = true;
  };

  # Nix settings
  nix = {
    settings = {
      trusted-users = ["root" "@wheel"];
    };

    # Offload heavy builds to the Hetzner server
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "65.109.108.233";
        systems = ["x86_64-linux"];
        protocol = "ssh";
        sshUser = "root";
        sshKey = "/home/wap/.ssh/id_rsa";
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
      }
    ];
  };

  # Tailscale subnet router for the friend's LAN where Tuya devices live.
  # The advertised route must be approved in the Tailscale admin console.
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = ["--advertise-routes=192.168.2.0/24"];
  };

  # Enable nix-ld for running unpatched dynamic binaries (e.g. Android SDK)
  programs.nix-ld.enable = true;

  # Elementary-style SDDM theme (thinkpad only)
  environment.systemPackages = lib.mkAfter [sddmElementaryTheme];

  # Allow passwordless nixos-rebuild switch for wap on this host only
  security.sudo.extraRules = [
    {
      users = ["wap"];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild switch *";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # ThinkPad-specific hardware support
  services = {
    displayManager.sddm = {
      theme = "sddmElementaryOs";
      extraPackages = [sddmElementaryTheme];
    };

    # iOS device management
    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };

    # Fingerprint authentication
    fprintd.tod.enable = true;

    # In order to get AnyType login key visible
    # https://github.com/anyproto/anytype-ts/issues/729#issuecomment-2799841750
    # gnome.gnome-keyring.enable = true;

    # Push local builds to Cachix
    cachix-watch-store = {
      enable = true;
      cacheName = "cypl0x";
      cachixTokenFile = "/etc/cachix/cypl0x.token";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken.
  system.stateVersion = "23.11";
}
