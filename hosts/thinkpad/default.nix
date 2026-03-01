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
    ../../modules/system/exwm.nix

    # User configuration
    ../../modules/users/root.nix
    ../../modules/users/cypl0x.nix
    ../../modules/users/wap.nix
    ../../modules/users/proxy.nix

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

  # Enable nix-ld for running unpatched dynamic binaries (e.g. Android SDK)
  programs.nix-ld.enable = true;

  # ThinkPad-specific hardware support
  services = {
    # iOS device management
    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };

    # Fingerprint authentication
    fprintd.tod.enable = true;

    # OpenSSH AcceptEnv (nixpkgs unstable uses list format)
    openssh.settings.AcceptEnv = ["LANG" "LC_*"];

    # In order to get AnyType login key visible
    # https://github.com/anyproto/anytype-ts/issues/729#issuecomment-2799841750
    # gnome.gnome-keyring.enable = true;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken.
  system.stateVersion = "23.11";
}
