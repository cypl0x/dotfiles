{pkgs, ...}: {
  # Base graphical stack for the workstation.
  # Hyprland (Wayland) is the only desktop session — see hosts/thinkpad/hyprland.nix.

  services = {
    # X11 keymap (applies to XWayland clients under Hyprland).
    xserver.xkb = {
      layout = "de";
      variant = "";
      options = "caps:escape";
    };

    # Ly — minimal animated TTY greeter. Lists every session from the
    # wayland-/xsessions desktop files automatically (here: Hyprland).
    # YubiKey/fingerprint still work — they are PAM-level and greeter-agnostic.
    displayManager.ly = {
      enable = true;
      settings = {
        animation = "colormix"; # none | doom | matrix | colormix | gameoflife
        animate = true;
        clock = "%c";
        hide_borders = false;

        # Polish: big ASCII clock above a roomier, centred login box; masked
        # password with a bullet; wider input fields so long session names and
        # usernames aren't clipped.
        bigclock = true;
        margin_box_h = 4;
        margin_box_v = 2;
        input_len = 40;
        max_desktop_len = 40;
        asterisk = "*";
        clear_password = true; # wipe the field on a failed login
        blank_box = true; # blank the box background for cleaner contrast

        # Doom Vibrant colours (0x00RRGGBB). Background left untouched (black)
        # so only the input fields / text / borders are themed.
        fg = "0x00bbc2cf"; # text  — Doom foreground
        border_fg = "0x0051afef"; # box border — Doom blue
        error_fg = "0x00ff665c"; # errors — Doom red

        # colormix shader animated across the Doom Vibrant accent palette.
        # Analogous, dimmed blues → violet (not the old saturated magenta ↔
        # cyan ↔ violet, which flickered harsh and bright over the dark base):
        # neighbouring hues at ~55% brightness blend smoothly and stay subtle.
        # col3's high byte (0x20) is ly's blend weight, not part of the RGB —
        # keep it to preserve the mix intensity.
        colormix_col1 = "0x001f5582"; # Doom dark-blue
        colormix_col2 = "0x003d84b3"; # Doom blue, dimmed
        colormix_col3 = "0x206b6497"; # Doom violet, dimmed (0x20 = blend weight)
      };
    };

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
    kmymoney # personal finance (Qt app, DE-agnostic)

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
