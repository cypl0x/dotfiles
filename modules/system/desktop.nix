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
        animation = "colormix"; # none | doom | matrix | colormix | gameoflife
        animate = true;
        clock = "%c";
        hide_borders = false;

        # Doom Vibrant colours (0x00RRGGBB). Background left untouched (black)
        # so only the input fields / text / borders are themed.
        fg = "0x00bbc2cf"; # text  — Doom foreground
        border_fg = "0x0051afef"; # box border — Doom blue
        error_fg = "0x00ff665c"; # errors — Doom red

        # colormix shader → Doom blue → magenta → dark wash. The third colour
        # keeps ly's high-byte blend weight (0x20) from the default.
        colormix_col1 = "0x0051afef"; # Doom blue
        colormix_col2 = "0x00c57bdb"; # Doom magenta
        colormix_col3 = "0x201c1f24"; # Doom darkest
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
    maple-mono.NF # Maple Mono Nerd Font — primary UI/terminal font
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
