{pkgs, ...}: {
  # Application launchers — keyboard-first, Doom-vibrant.
  #
  # rofi stays the primary launcher on SUPER+Space (configured in
  # home/hyprland/hyprland.conf with home/hyprland/rofi/doom-vibrant.rasi).
  # These three modern alternatives are enabled side-by-side, each on its own
  # SUPER+<mod>+Space bind, so the winner can be chosen by feel. anyrun is
  # themed to Doom Vibrant here; walker and vicinae ship on their defaults for
  # now (their theme schemas are versioned — themed once one is chosen).
  #
  #   SUPER+Space         → rofi      (primary, themed)
  #   SUPER+SHIFT+Space   → walker
  #   SUPER+CTRL+Space    → anyrun    (themed)
  #   SUPER+ALT+Space     → vicinae

  # anyrun — Rust, plugin-based, Hyprland-native.
  programs.anyrun = {
    enable = true;
    config = {
      # anyrun shows nothing without plugins — wire the useful .so's shipped
      # in the anyrun package: app launcher, calculator, shell commands.
      plugins = [
        "${pkgs.anyrun}/lib/libapplications.so"
        "${pkgs.anyrun}/lib/librink.so"
        "${pkgs.anyrun}/lib/libshell.so"
      ];
      width.fraction = 0.3;
      hideIcons = false;
      closeOnClick = true;
      showResultsImmediately = true;
    };
    extraCss = ''
      window { background: transparent; }

      #window,
      #box {
        background-color: #242730;
        border: 2px solid #51afef;
        border-radius: 12px;
      }

      #entry {
        background-color: #1c1f24;
        color: #bbc2cf;
        border: 1px solid #484854;
        border-radius: 8px;
        margin: 8px;
        padding: 8px;
      }

      #main { color: #bbc2cf; }

      .match {
        color: #bbc2cf;
        padding: 4px 8px;
        border-radius: 6px;
      }
      .match:selected {
        background-color: #51afef;
        color: #1c1f24;
      }

      .plugin.info { color: #62686e; }
    '';
  };

  # walker — Go/GTK4, very popular in Hyprland dotfiles. Daemon-backed.
  services.walker = {
    enable = true;
    settings = {
      theme = "default";
    };
  };

  # vicinae — Raycast-style launcher daemon.
  programs.vicinae = {
    enable = true;
    systemd.enable = true; # autoStart defaults true under graphical-session
  };
}
