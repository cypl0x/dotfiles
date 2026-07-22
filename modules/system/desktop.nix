{pkgs, ...}: {
  # Desktop environment configuration for workstations
  # KDE Plasma 6 with X11

  services = {
    # Enable the X11 windowing system
    xserver = {
      enable = true;
      # Configure keymap in X11
      xkb = {
        layout = "de";
        variant = "";
        options = "caps:escape";
      };
    };

    # Ly — minimal animated TTY greeter. Lists every session (Hyprland, EXWM,
    # KDE Plasma, GNOME) from the wayland-/xsessions desktop files
    # automatically. x11Support is required so the X11 sessions (EXWM, Plasma
    # X11) can launch. YubiKey/fingerprint still work — they are PAM-level and
    # greeter-agnostic.
    displayManager.ly = {
      enable = true;
      x11Support = true;
      settings = {
        animation = "matrix"; # cmatrix-style digital rain (doom fire looked bad)
        animate = true;
        clock = "%c";
        hide_borders = false;
        # Doom Vibrant accent for the input box borders (ly uses terminal
        # colour indices; 4 = blue → #51afef in most palettes).
        bg = 0;
        fg = 4;
      };
    };
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
    kdePackages.kmail-account-wizard
    kdePackages.kdepim-addons
    kdePackages.merkuro
    kdePackages.kdeconnect-kde
    kdePackages.ktorrent
    kdePackages.plasma-systemmonitor
    kdePackages.akregator
    kdePackages.marble
    kdePackages.tokodon
    kdePackages.plasmatube
    kdePackages.kaddressbook
    kdePackages.arianna
    kdePackages.kasts

    kmymoney

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
