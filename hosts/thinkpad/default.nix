{pkgs, ...}: {
  imports = [
    # Hardware and platform configuration
    ./hardware.nix
    ../../modules/hardware/yubikey.nix

    # System modules
    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/nix-common.nix
    ../../modules/system/locale.nix
    ../../modules/system/desktop.nix
    ../../modules/services/tailscale.nix

    # User configuration
    ../../modules/users/root.nix
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix
    ../../modules/users/proxy.nix

    # Host-specific configuration
    ./hyprland.nix
    ./thinkpad-packages.nix
    ./power.nix
  ];

  # Bootloader configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  boot.kernelPackages = pkgs.linuxPackages_6_18;

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
  };

  # Tailscale subnet router for the friend's LAN where Tuya devices live.
  # The advertised route must be approved in the Tailscale admin console.
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = ["--advertise-routes=192.168.2.0/24"];
  };

  # Enable nix-ld for running unpatched dynamic binaries (e.g. Android SDK)
  programs.nix-ld.enable = true;

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
    # Keyboard backlight to max on boot/resume
    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpacpi::kbd_backlight", RUN+="${pkgs.bash}/bin/sh -c 'cat /sys/class/leds/%k/max_brightness > /sys/class/leds/%k/brightness'"
    '';

    # iOS device management
    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };

    # Fingerprint authentication.
    # Plain fprintd (open libfprint drivers). NOT tod: fprintd.tod.enable
    # needs a proprietary per-reader TOD driver (e.g. libfprint-2-tod1-vfs0090 /
    # -goodix) that was never wired, so it loaded no device and did nothing.
    # No USB fingerprint reader is currently detected via lsusb; if this
    # ThinkPad's reader turns out to require TOD, re-enable tod AND set
    # services.fprintd.tod.driver to the matching driver package.
    fprintd.enable = true;

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
