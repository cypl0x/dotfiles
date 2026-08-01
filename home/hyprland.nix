{
  pkgs,
  lib,
  ...
}: let
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

    # uwsm (login via "Hyprland (uwsm-managed)" in ly) already provides
    # systemd session integration. Home-manager's own defaults to on too and
    # binds hyprland-session.target the same way uwsm binds the compositor
    # service — the two racing during startup was what killed the compositor
    # right after login. See wiki.hypr.land/Nix/Hyprland-on-Home-Manager.
    systemd.enable = false;
  };

  # ── Config files ─────────────────────────────────────────────────────────

  # PCManFM / libfm defaults. Fully managed: prefs set in the GUI may be
  # rewritten on the next home-manager activation (add them here if you care).
  # view_mode: icon | compact | thumbnail | list  (list = detailed list view)
  # sort: <col>;ascending|descending  — cols: name, mtime, size, type, …
  xdg.configFile = {
    # force: PCManFM rewrites this when the GUI is used, and a stale
    # pcmanfm.conf.bak would then make HM activation refuse to back up.
    "pcmanfm/default/pcmanfm.conf" = {
      force = true;
      text = ''
        [config]
        bm_open_method=0
        # "Open Terminal Here" — matches $terminal in hyprland.conf
        terminal=kitty

        [volume]
        mount_on_startup=1
        mount_removable=1
        autorun=1

        [ui]
        always_show_tabs=0
        max_tab_chars=32
        win_width=960
        win_height=640
        side_pane_mode=dirtree
        # Detailed list view (Name / Size / Type / Modified columns)
        view_mode=list
        show_hidden=1
        # Newest files first
        sort=mtime;descending;
        toolbar=newtab;navigation;home;
        show_statusbar=1
        pathbar_mode_buttons=0
        close_on_unmount=1
        change_tab_on_drop=1
      '';
    };
    "libfm/libfm.conf" = {
      force = true;
      text = ''
        [config]
        terminal=kitty
      '';
    };
  };

  home = {
    file = {
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
      ".config/hypr/scripts/toggle-scratch-term.sh" = {
        source = ./hyprland/scripts/toggle-scratch-term.sh;
        executable = true;
      };
      ".config/waybar/config.jsonc".source = ./hyprland/waybar/config.jsonc;
      ".config/waybar/style.css".source = ./hyprland/waybar/style.css;
      ".config/swaync/config.json".source = ./hyprland/swaync/config.json;
      ".config/swaync/style.css".source = ./hyprland/swaync/style.css;
      ".config/rofi/doom-vibrant.rasi".source = ./hyprland/rofi/doom-vibrant.rasi;
    };

    # XDG Wayland hints (supplement what Hyprland sets in the session)
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland;xcb";
      SDL_VIDEODRIVER = "wayland";
      CLUTTER_BACKEND = "wayland";
    };

    # Default browser → Firefox; PDF → zathura. Uses xdg-mime/xdg-settings so we
    # don't clobber the rest of a hand-edited mimeapps.list (image handlers, etc.).
    activation.setDesktopDefaults = lib.hm.dag.entryAfter ["writeBoundary"] ''
      xdg_mime=${pkgs.xdg-utils}/bin/xdg-mime
      xdg_settings=${pkgs.xdg-utils}/bin/xdg-settings
      $DRY_RUN_CMD $xdg_settings set default-web-browser firefox.desktop || true
      for mime in \
        x-scheme-handler/http \
        x-scheme-handler/https \
        x-scheme-handler/chrome \
        text/html \
        application/xhtml+xml
      do
        $DRY_RUN_CMD $xdg_mime default firefox.desktop "$mime" || true
      done
      # PDF plugin desktop (mupdf backend); meta org.pwmt.zathura.desktop also works.
      $DRY_RUN_CMD $xdg_mime default org.pwmt.zathura-pdf-mupdf.desktop application/pdf || true
      $DRY_RUN_CMD $xdg_mime default org.pwmt.zathura-pdf-mupdf.desktop application/x-pdf || true
    '';
  };

  # ── PDF viewer (Skim analogue: auto-reloads when the file changes) ────────
  # Primary for LaTeX/preview + general reading. Okular remains an optional
  # second install for annotations/forms if you miss the KDE workflow.
  programs.zathura = {
    enable = true;
    options = {
      # Invert light-paper PDFs into the Doom palette for night reading.
      recolor = true;
      recolor-keephue = true;
      recolor-darkcolor = "#bbc2cf";
      recolor-lightcolor = "#242730";
      default-bg = "#242730";
      default-fg = "#bbc2cf";
      statusbar-bg = "#1c1f24";
      statusbar-fg = "#bbc2cf";
      inputbar-bg = "#21242b";
      inputbar-fg = "#bbc2cf";
      highlight-color = "rgba(81,175,239,0.4)";
      highlight-active-color = "rgba(81,175,239,0.7)";
      selection-clipboard = "clipboard";
      adjust-open = "best-fit";
      # Render a bit denser on the ThinkPad panel.
      font = "Maple Mono NF 10";
    };
  };

  # ── hyprshell: hold-ALT MRU window switcher (the old "hyprswitch") ────────
  # Hyprland has no native cross-workspace window cycler — `cyclenext` only ever
  # walks the current workspace. hyprshell's "switch" mode is the real alt-tab:
  # hold ALT, tap Tab to walk a most-recently-used list, release ALT to commit.
  #
  # It registers its keybind by pushing `bind` keywords into the running
  # compositor at startup, so ALT+Tab must stay unbound in hyprland.conf —
  # otherwise a `hyprctl reload` (SUPER+CTRL+R) puts the static bind back on top.
  # Because we use configType = "hyprlang" rather than lua, hyprshell logs
  # "eval is only supported with the lua config manager, trying legacy syntax"
  # on every start. Cosmetic — the legacy path installs the binds fine.
  #
  # filter_by = [] means "every window": the default is [current_monitor],
  # which would hide the other screen's windows once a monitor is plugged in.
  # `overview` is deliberately left unset (= disabled) — it ships its own app
  # launcher and there are already four of those on SUPER+Space variants.
  services.hyprshell = {
    enable = true;
    # exec-once, not a unit — see the note below on graphical-session.target.
    systemd.enable = false;
    settings = {
      # Schema version of this config. Without it hyprshell logs "Config file
      # does not have a version specified" and skips its migration check; bump
      # when a hyprshell release changes the config layout.
      version = 4;
      windows = {
        scale = 8.5;
        items_per_row = 5;
        switch = {
          modifier = "alt";
          key = "Tab";
          filter_by = [];
        };
      };
    };
  };

  # hypridle, hyprpaper, swayosd, waybar, swaync, and hyprshell are all started
  # via exec-once in hyprland.conf — no separate systemd services needed.
  # Systemd services scoped to graphical-session.target would fire in KDE/GNOME
  # too, where ext-idle-notifier-v1 and hyprpaper's socket don't exist.
}
