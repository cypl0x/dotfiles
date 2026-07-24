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

        # Lava palette (0x00RRGGBB). Background left untouched (black) so the
        # box reads as molten glow over cooled rock — only fields/text/borders
        # are themed. Warm, condensed hues (all in the red→amber arc).
        fg = "0x00ffcf9e"; # text  — warm amber cream (legible on black)
        border_fg = "0x00ff5e1a"; # box border — glowing lava orange
        error_fg = "0x00ff2d55"; # errors — hot magma red

        # colormix shader animated across a condensed lava gradient: dark ember
        # red → molten orange → amber glow. Analogous warm hues at ~50–60%
        # brightness so the mix smoulders instead of flickering harshly over the
        # black base. col3's high byte (0x20) is ly's blend weight, not RGB —
        # keep it to preserve the mix intensity.
        colormix_col1 = "0x006e1e0a"; # dark ember red
        colormix_col2 = "0x00b34a1a"; # molten orange, dimmed
        colormix_col3 = "0x20cc8a2e"; # amber glow, dimmed (0x20 = blend weight)
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
