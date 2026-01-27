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
