{pkgs, ...}: {
  # Desktop environment configuration for workstations
  # KDE Plasma 6 with X11

  services = {
    # Enable the X11 windowing system
    xserver = {
      enable = true;
      # Configure keymap in X11
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    # Enable the KDE Plasma Desktop Environment
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;

    # Enable CUPS to print documents
    printing.enable = true;

    # Enable sound with pipewire
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Enable flatpak support
    flatpak.enable = true;
  };

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  security.rtkit.enable = true;
  xdg.portal.enable = true;

  # Font configuration
  fonts.packages = with pkgs; [
    cascadia-code
  ];

  # Desktop-specific packages
  environment.systemPackages = with pkgs; [
    # KDE applications
    kdePackages.kate
    kdePackages.kmail

    # Browsers
    firefox
    brave
    tor-browser

    # Office suite
    libreoffice-qt
    hunspell
    hunspellDicts.en_US
    hunspellDicts.de_DE

    # Media and utilities
    cheese
    thunderbird

    # Development
    vscode
  ];
}
