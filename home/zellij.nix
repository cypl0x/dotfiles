_: {
  # Zellij — Doom Vibrant theme + sensible defaults.
  #
  # NOTE on "vertical tabs": zellij has no vertical tab bar. Its tab bar is a
  # horizontal plugin (top or bottom via `pane_frames`/`default_layout`), and
  # there is no built-in left-edge tab strip. The closest equivalents are
  # side-by-side panes or the "stacked panes" feature. So this file themes and
  # configures zellij; a true vertical tab bar is not offered upstream.
  programs.zellij = {
    enable = true;
    # Don't auto-inject into the shell rc — start it explicitly with `zellij`.
    enableZshIntegration = false;

    settings = {
      theme = "doom-vibrant";

      # Match tmux's history-limit of 50000 (home/shell/tmux.conf). zellij
      # defaults to 10000, which is already five times tmux's own default, but
      # the two should not disagree — the split is zellij locally, tmux over
      # SSH, and scrollback depth should not depend on which one you landed in.
      scroll_buffer_size = 50000;

      pane_frames = true;
      default_layout = "compact";
      simplified_ui = false;
      ui.pane_frames = {
        rounded_corners = true;
        hide_session_name = false;
      };

      themes.doom-vibrant = {
        fg = "#bbc2cf";
        bg = "#242730";
        black = "#1c1f24";
        red = "#ff665c";
        green = "#7bc275";
        yellow = "#fcce7b";
        blue = "#51afef";
        magenta = "#c57bdb";
        cyan = "#5cefff";
        white = "#bbc2cf";
        orange = "#fcce7b";
      };
    };
  };
}
