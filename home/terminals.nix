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
    ".config/ghostty/ghostty-tabs.css".source = ./terminals/ghostty-tabs.css;
    ".config/alacritty/alacritty.toml".source = ./terminals/alacritty.toml;
    ".config/rio/config.toml".source = ./terminals/rio.toml;
    # Warp reads themes from ~/.local/share/warp-terminal/themes on Linux.
    ".local/share/warp-terminal/themes/doom_vibrant.yaml".source = ./terminals/warp-doom-vibrant.yaml;
  };
}
