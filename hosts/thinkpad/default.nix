{pkgs, ...}: {
  imports = [
    # Hardware and platform configuration
    ./hardware.nix

    # System modules
    ../../modules/system/packages.nix
    ../../modules/system/shell.nix
    ../../modules/system/security.nix
    ../../modules/system/locale.nix
    ../../modules/system/desktop.nix

    # User configuration
    ../../modules/users/wap.nix

    # Host-specific configuration
    ./thinkpad-packages.nix
  ];

  # Bootloader configuration and LUKS encryption
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.luks.devices."luks-2367f432-b059-480c-820a-12f84d964582".device = "/dev/disk/by-uuid/2367f432-b059-480c-820a-12f84d964582";
  };

  # Network configuration
  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
  };

  # Nix settings
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # ThinkPad-specific hardware support
  services = {
    # iOS device management
    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };

    # Fingerprint authentication
    fprintd.tod.enable = true;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken.
  system.stateVersion = "23.11";
}
