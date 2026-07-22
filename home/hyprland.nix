{pkgs, ...}: let
  # Doom Vibrant wallpaper, generated at build time — a subtle radial vignette
  # from the lighter Doom base (#2a2e38) down to the darkest (#1c1f24), so it
  # matches the palette exactly and needs no external asset fetch.
  doomWallpaper =
    pkgs.runCommand "doom-vibrant-wallpaper.png" {
      nativeBuildInputs = [pkgs.imagemagick];
    } ''
      magick -size 3840x2160 \
        radial-gradient:'#2a2e38'-'#1c1f24' \
        -gravity center \
        $out
    '';
in {
  # Hyprland home-manager configuration — thinkpad only (added via sharedModules).
  # Mirrors the Doom Emacs aesthetic from tmux/wezterm: Doom Vibrant palette,
  # SUPER as leader key, vim hjkl navigation, leader-chord-style submaps.

  wayland.windowManager.hyprland = {
    enable = true;

    # We write raw hyprlang via extraConfig below, so pin the config format to
    # hyprlang and silence the 26.05 default-flip-to-lua warning.
    configType = "hyprlang";

    # Raw config — same approach as tmux (builtins.readFile)
    extraConfig = builtins.readFile ./hyprland/hyprland.conf;
  };

  # ── Config files ─────────────────────────────────────────────────────────

  home.file = {
    ".config/hypr/hyprlock.conf".source   = ./hyprland/hyprlock.conf;
    ".config/hypr/hypridle.conf".source   = ./hyprland/hypridle.conf;
    ".config/hypr/hyprpaper.conf".source  = ./hyprland/hyprpaper.conf;
    ".config/hypr/wallpaper.png".source   = doomWallpaper;
    ".config/eww/eww.yuck".source         = ./hyprland/eww/eww.yuck;
    ".config/eww/eww.scss".source         = ./hyprland/eww/eww.scss;
    ".config/eww/scripts/net.sh" = {
      source = ./hyprland/eww/scripts/net.sh;
      executable = true;
    };
    ".config/hypr/scripts/run-or-raise.sh" = {
      source = ./hyprland/scripts/run-or-raise.sh;
      executable = true;
    };
    ".config/waybar/config.jsonc".source  = ./hyprland/waybar/config.jsonc;
    ".config/waybar/style.css".source     = ./hyprland/waybar/style.css;
    ".config/mako/config".source          = ./hyprland/mako.conf;
    ".config/rofi/doom-vibrant.rasi".source = ./hyprland/rofi/doom-vibrant.rasi;
  };

  # ── Hyprland-aware session variables ─────────────────────────────────────

  home.sessionVariables = {
    # XDG Wayland hints (supplement what Hyprland sets in the session)
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
  };

  # hypridle, hyprpaper, swayosd, waybar, and mako are all started via
  # exec-once in hyprland.conf — no separate systemd services needed.
  # Systemd services scoped to graphical-session.target would fire in KDE/GNOME
  # too, where ext-idle-notifier-v1 and hyprpaper's socket don't exist.
}
