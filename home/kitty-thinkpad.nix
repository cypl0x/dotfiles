_: {
  programs.kitty = {
    enable = true;
    settings = {
      # Tab bar layout (tmux-like)
      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_bar_background = "#242730";
      active_tab_foreground = "#1c1f24";
      active_tab_background = "#51afef";
      inactive_tab_foreground = "#bbc2cf";
      inactive_tab_background = "#242730";
      tab_title_template = " {index}:{title} ";
      active_tab_title_template = " {index}:{title} ";

      # Doom Vibrant theme (Henrik Lissner)
      foreground = "#bbc2cf";
      background = "#242730";
      selection_foreground = "#bbc2cf";
      selection_background = "#6A8FBF";

      cursor = "#bbc2cf";
      cursor_text_color = "#242730";

      active_border_color = "#46D9FF";
      inactive_border_color = "#484854";

      color0 = "#2a2e38";
      color8 = "#484854";

      color1 = "#ff665c";
      color9 = "#ff665c";

      color2 = "#7bc275";
      color10 = "#99bb66";

      color3 = "#fcce7b";
      color11 = "#ecbe7b";

      color4 = "#51afef";
      color12 = "#51afef";

      color5 = "#C57BDB";
      color13 = "#c678dd";

      color6 = "#5cEfFF";
      color14 = "#46D9FF";

      color7 = "#DFDFDF";
      color15 = "#bbc2cf";
    };

    # Doom-like leader emulation (Ctrl+Space) using kitty multi-key shortcuts.
    # kitty has no true leader key, so we use key sequences: key1>key2.
    extraConfig = ''
      # Reload config
      map ctrl+space>r load_config_file

      # Pane navigation (vim-style)
      map ctrl+space>h neighboring_window left
      map ctrl+space>j neighboring_window bottom
      map ctrl+space>k neighboring_window top
      map ctrl+space>l neighboring_window right

      # Pane resize (Shift+H/J/K/L)
      map ctrl+space>H resize_window narrower 5
      map ctrl+space>J resize_window shorter 3
      map ctrl+space>K resize_window taller 3
      map ctrl+space>L resize_window wider 5

      # Window key-table equivalents (Ctrl+Space w ...)
      map ctrl+space>w>w focus_visible_window
      map ctrl+space>w>v launch --location=hsplit --cwd=current
      map ctrl+space>w>s launch --location=vsplit --cwd=current
      map ctrl+space>w>c close_window
      map ctrl+space>w>z toggle_layout stack
      map ctrl+space>w>= resize_window reset

      # Buffer/Tab key-table equivalents (Ctrl+Space b ...)
      map ctrl+space>b>n next_tab
      map ctrl+space>b>p previous_tab
      map ctrl+space>b>b select_tab
      map ctrl+space>b>k close_tab
      map ctrl+space>b>c new_tab
      map ctrl+space>b>1 goto_tab 1
      map ctrl+space>b>2 goto_tab 2
      map ctrl+space>b>3 goto_tab 3
      map ctrl+space>b>4 goto_tab 4
      map ctrl+space>b>5 goto_tab 5
      map ctrl+space>b>6 goto_tab 6
      map ctrl+space>b>7 goto_tab 7
      map ctrl+space>b>8 goto_tab 8
      map ctrl+space>b>9 goto_tab 9

      # Project/OS window equivalents (Ctrl+Space p ...)
      map ctrl+space>p>w nth_os_window -1
      map ctrl+space>p>n new_os_window_with_cwd

      # Toggle key-table equivalents (Ctrl+Space t ...)
      map ctrl+space>t>f toggle_fullscreen
      map ctrl+space>t>z toggle_layout stack

      # Open key-table equivalents (Ctrl+Space o ...)
      map ctrl+space>o>l select_tab
      map ctrl+space>o>t new_tab
      map ctrl+space>o>s launch --location=vsplit --cwd=current
      map ctrl+space>o>v launch --location=hsplit --cwd=current
    '';
  };
}
