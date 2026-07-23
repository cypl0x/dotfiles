{pkgs, ...}: let
  # Doom Vibrant wallpaper, generated at build time. A dark "aurora" mesh of
  # soft, heavily-blurred Doom-palette colour blobs over the darkest base, with
  # a faint NixOS snowflake watermark centred and a gentle vignette. Matches the
  # palette exactly, no external asset fetch.
  doomWallpaper =
    pkgs.runCommand "doom-vibrant-wallpaper.png" {
      nativeBuildInputs = [pkgs.imagemagick];
    } ''
      # 1. Aurora base. Render small + heavily blurred (fast), then upscale — a
      #    huge blur on a full-res canvas would make every rebuild crawl. More,
      #    lower-opacity blobs than before blend into smoother gradients; a
      #    faint grain kills the banding a big blur otherwise leaves behind.
      magick -size 640x360 xc:'#14161b' \
        -fill 'rgba(81,175,239,0.42)'   -draw 'circle 120,110 120,250' \
        -fill 'rgba(31,85,130,0.55)'    -draw 'circle 60,300  60,420'  \
        -fill 'rgba(197,123,219,0.38)'  -draw 'circle 540,285 540,410' \
        -fill 'rgba(123,194,117,0.26)'  -draw 'circle 565,70  565,160' \
        -fill 'rgba(92,239,255,0.22)'   -draw 'circle 330,330 330,410' \
        -fill 'rgba(169,161,225,0.20)'  -draw 'circle 360,60  360,150' \
        -blur 0x40 \
        -resize 2560x1440 \
        -attenuate 0.6 +noise Gaussian \
        \( -size 2560x1440 radial-gradient:none-'#0b0d11d0' \) -compose over -composite \
        aurora.png

      # 2. NixOS-style six-fold snowflake. One branch (stem + twig pairs) drawn
      #    once, then rotated 0/60/…/300° and merged — a subtle Doom-blue motif.
      magick -size 1440x1440 xc:none \
        -stroke '#5c9fd6' -strokewidth 15 -fill none \
        -draw 'line 720,720 720,150' \
        -draw 'line 720,345 618,258' -draw 'line 720,345 822,258' \
        -draw 'line 720,470 638,401' -draw 'line 720,470 802,401' \
        -draw 'line 720,595 660,545' -draw 'line 720,595 780,545' \
        arm.png
      magick arm.png \
        \( arm.png -distort SRT 60  \) \
        \( arm.png -distort SRT 120 \) \
        \( arm.png -distort SRT 180 \) \
        \( arm.png -distort SRT 240 \) \
        \( arm.png -distort SRT 300 \) \
        -background none -layers merge +repage snow.png

      # 3. Composite the flake faint + softened over the aurora, centred.
      magick aurora.png \
        \( snow.png -channel A -evaluate multiply 0.12 +channel -blur 0x1.2 \) \
        -gravity center -compose over -composite \
        "$out"
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
    ".config/hypr/hyprlock.conf".source = ./hyprland/hyprlock.conf;
    ".config/hypr/hypridle.conf".source = ./hyprland/hypridle.conf;
    ".config/hypr/hyprpaper.conf".source = ./hyprland/hyprpaper.conf;
    ".config/hypr/wallpaper.png".source = doomWallpaper;
    ".config/eww/eww.yuck".source = ./hyprland/eww/eww.yuck;
    ".config/eww/eww.scss".source = ./hyprland/eww/eww.scss;
    ".config/eww/scripts/net.sh" = {
      source = ./hyprland/eww/scripts/net.sh;
      executable = true;
    };
    ".config/hypr/scripts/run-or-raise.sh" = {
      source = ./hyprland/scripts/run-or-raise.sh;
      executable = true;
    };
    ".config/hypr/scripts/set-wallpaper.sh" = {
      source = ./hyprland/scripts/set-wallpaper.sh;
      executable = true;
    };
    ".config/hypr/scripts/lock-stats.sh" = {
      source = ./hyprland/scripts/lock-stats.sh;
      executable = true;
    };
    ".config/hypr/scripts/window-switcher.sh" = {
      source = ./hyprland/scripts/window-switcher.sh;
      executable = true;
    };
    ".config/hypr/scripts/doom-buffer-switcher.sh" = {
      source = ./hyprland/scripts/doom-buffer-switcher.sh;
      executable = true;
    };
    ".config/hypr/scripts/hypr-cheatsheet.sh" = {
      source = ./hyprland/scripts/hypr-cheatsheet.sh;
      executable = true;
    };
    ".config/hypr/scripts/waybar-claude.sh" = {
      source = ./hyprland/scripts/waybar-claude.sh;
      executable = true;
    };
    ".config/hypr/scripts/rofi-run-cmd.sh" = {
      source = ./hyprland/scripts/rofi-run-cmd.sh;
      executable = true;
    };
    ".config/hypr/scripts/firefox-tab-switcher.sh" = {
      source = ./hyprland/scripts/firefox-tab-switcher.sh;
      executable = true;
    };
    ".config/hypr/scripts/claude-notify.sh" = {
      source = ./hyprland/scripts/claude-notify.sh;
      executable = true;
    };
    ".config/waybar/config.jsonc".source = ./hyprland/waybar/config.jsonc;
    ".config/waybar/style.css".source = ./hyprland/waybar/style.css;
    ".config/swaync/config.json".source = ./hyprland/swaync/config.json;
    ".config/swaync/style.css".source = ./hyprland/swaync/style.css;
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

  # hypridle, hyprpaper, swayosd, waybar, and swaync are all started via
  # exec-once in hyprland.conf — no separate systemd services needed.
  # Systemd services scoped to graphical-session.target would fire in KDE/GNOME
  # too, where ext-idle-notifier-v1 and hyprpaper's socket don't exist.
}
