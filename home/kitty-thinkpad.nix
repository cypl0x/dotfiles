_: {
  programs.kitty = {
    enable = true;
    settings = {
      # Primary font — Maple Mono Nerd Font
      font_family = "Maple Mono NF";
      font_size = 12;

      # Tab bar layout (tmux-like). kitty 0.48 is installed, so the left edge
      # really is a vertical tab strip now — the thing ghostty, wezterm and
      # zellij all lack.
      tab_bar_edge = "left";
      # "custom" loads ~/.config/kitty/tab_bar.py (home/terminals/kitty-tab-bar.py),
      # which adds a per-process Nerd Font icon and then delegates to kitty's
      # own powerline renderer — so this is still powerline styling, with the
      # icons the declarative template cannot express.
      tab_bar_style = "custom";
      tab_powerline_style = "slanted";
      # Width of the vertical strip, in cells.
      tab_bar_min_tabs = 1;
      tab_bar_background = "#242730";
      active_tab_foreground = "#1c1f24";
      active_tab_background = "#51afef";
      active_tab_font_style = "bold";
      inactive_tab_foreground = "#62686E";
      inactive_tab_background = "#242730";
      # The icon is prepended by tab_bar.py, so the template only owns the rest.
      tab_title_template = "{index}:{title}";
      active_tab_title_template = "{index}:{title}";
      # Layouts: "splits" must be enabled (and listed first, so it is the
      # startup layout) for `launch --location=vsplit/hsplit` to work at all.
      # Note: "startup_layout" is NOT a kitty option — kitty ignores it and
      # falls back to the default layout ("fat"), in which the split
      # keybindings below silently lose their direction. "stack" is kept for
      # the zoom toggles (toggle_layout stack).
      enabled_layouts = "splits,stack";

      # Doom Vibrant theme (Henrik Lissner)
      foreground = "#bbc2cf";
      background = "#242730";
      selection_foreground = "#bbc2cf";
      selection_background = "#6A8FBF";

      cursor = "#bbc2cf";
      cursor_text_color = "#242730";
      cursor_shape = "beam"; # line cursor at the shell prompt

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

      # Enable kitty remote control (kitten @ ...). "yes" lets programs running
      # inside kitty drive it over the tty; listen_on additionally opens a unix
      # socket so *other* processes — a script, or the kitty on tty6 — can too.
      # The socket lives in XDG_RUNTIME_DIR, which is mode 0700, so this does
      # not widen access beyond the user.
      allow_remote_control = "yes";
      listen_on = "unix:/run/user/1000/kitty-{kitty_pid}";
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

      # Pane resize.
      #
      # These MUST be spelled shift+h, not H. kitty normalises a bare uppercase
      # letter to its lowercase key with no shift modifier, so `map ctrl+space>H`
      # parsed to exactly the same trigger as `map ctrl+space>h` and silently
      # replaced it — which is why ctrl+space>h used to resize the window
      # instead of focusing the split to its left.
      map ctrl+space>shift+h resize_window narrower 5
      map ctrl+space>shift+j resize_window shorter 3
      map ctrl+space>shift+k resize_window taller 3
      map ctrl+space>shift+l resize_window wider 5

      # Window key-table equivalents (Ctrl+Space w ...)
      map ctrl+space>w>w focus_visible_window
      # hjkl again under the w table, for when the leader is already half-typed.
      map ctrl+space>w>h neighboring_window left
      map ctrl+space>w>j neighboring_window bottom
      map ctrl+space>w>k neighboring_window top
      map ctrl+space>w>l neighboring_window right
      # vim convention: v = vertical split = side-by-side (kitty "vsplit"),
      # s = horizontal split = stacked (kitty "hsplit"). These used to be
      # swapped, so "v" produced a top/bottom split.
      map ctrl+space>w>v launch --location=vsplit --cwd=current
      map ctrl+space>w>s launch --location=hsplit --cwd=current
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
      map ctrl+space>o>v launch --location=vsplit --cwd=current
      map ctrl+space>o>s launch --location=hsplit --cwd=current

      # Scroll / search key-table (Ctrl+Space s ...) — mirrors the s table in
      # home/terminals/ghostty.config.
      #
      # s>g is kitty's killer feature: it pulls JUST the previous command's
      # output into the pager, using the OSC 133 marks that kitty's shell
      # integration emits. It is empty inside tmux or zellij — the multiplexer
      # renders the screen itself and never forwards those marks.
      map ctrl+space>s>s show_scrollback
      map ctrl+space>s>g show_last_command_output
      map ctrl+space>s>k scroll_line_up
      map ctrl+space>s>j scroll_line_down
      map ctrl+space>s>u scroll_page_up
      map ctrl+space>s>d scroll_page_down
      map ctrl+space>s>t scroll_home
      map ctrl+space>s>b scroll_end

      # Yank key-table (Ctrl+Space y ...) — the hints kitten, i.e. kitty's
      # native equivalent of tmux-thumbs/extrakto. `--program -` pastes the
      # match onto the command line; `--program @` copies it to the clipboard.
      # Works without any multiplexer, which is the whole point.
      map ctrl+space>y>y kitten hints --type word --program -
      map ctrl+space>y>l kitten hints --type line --program -
      map ctrl+space>y>p kitten hints --type path --program -
      map ctrl+space>y>h kitten hints --type hash --program -
      map ctrl+space>y>n kitten hints --type linenum
      map ctrl+space>y>u kitten hints --type url --program @
      map ctrl+space>y>o kitten hints --type url
    '';
  };
}
