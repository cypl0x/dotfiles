_: {
  # Terminal emulators beyond kitty (home/kitty-thinkpad.nix) and wezterm
  # (home/wezterm/wezterm.lua). Ghostty and Alacritty are configured via raw
  # config files so they track the exact Doom Vibrant palette and — where the
  # terminal supports splits/tabs — the Doom-Emacs C-Space leader scheme used
  # everywhere else (kitty / wezterm / tmux).
  #
  #   ghostty   → native splits + tabs, full leader scheme
  #   alacritty → no splits/tabs; palette + font only, muxing via tmux
  #   warp      → proprietary; theme colours only, no keybind file

  home.file = {
    ".config/ghostty/config".source = ./terminals/ghostty.config;
    ".config/alacritty/alacritty.toml".source = ./terminals/alacritty.toml;
    ".warp/themes/doom_vibrant.yaml".source = ./terminals/warp-doom-vibrant.yaml;
  };
}
