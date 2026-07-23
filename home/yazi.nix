{pkgs, ...}: {
  # Yazi — modern, Rust, async TUI file manager. Doom-Vibrant-themed to match
  # the rest of the Hyprland desktop (zellij / wezterm / ghostty / waybar), with
  # an hlissner-Doom SPC-leader keymap. Config lives as raw files in home/yazi/
  # so it reviews like the terminal configs in home/terminals.nix; only the
  # package, plugins and previewer deps are wired through Nix here.
  #
  # Shell integration (`y` wrapper that cd's to yazi's last dir on quit) is in
  # home/shell/zsh/functions.sh.

  programs.yazi = {
    enable = true;
    # We start it explicitly (`yazi` / `y`), no rc auto-injection.
    enableZshIntegration = false;

    # Symlinked into ~/.config/yazi/plugins. Curated for productivity:
    plugins = {
      inherit
        (pkgs.yaziPlugins)
        full-border # rounded UI border
        git # VCS status flags in the list
        githead # branch/status segment in the header
        smart-enter # dir → enter, file → open
        close-and-restore-tab # close current tab, undo-able
        smart-filter # live fuzzy filter
        jump-to-char # vim f/F over filenames
        relative-motions # 5j / 3k with gutter numbers
        chmod # chmod on the selection
        compress # create archives
        diff # diff selected vs hovered
        toggle-pane # show/hide/max preview pane
        bookmarks # harpoon-style quick jumps
        lazygit # SPC g g → lazygit
        ;
    };
  };

  # Raw config files (managed by us, not generated from Nix attrsets) so the
  # TOML/Lua reviews cleanly and tracks upstream yazi 26.x schema directly.
  xdg.configFile = {
    "yazi/yazi.toml".source = ./yazi/yazi.toml;
    "yazi/keymap.toml".source = ./yazi/keymap.toml;
    "yazi/theme.toml".source = ./yazi/theme.toml;
    "yazi/init.lua".source = ./yazi/init.lua;
  };

  # Previewers / helpers yazi shells out to. Already-present system tools
  # (bat, eza, fd, ripgrep, fzf, zoxide, jq, imagemagick, exiftool) are not
  # repeated here.
  home.packages = with pkgs; [
    poppler-utils # PDF text/'pdftoppm' page previews
    ffmpegthumbnailer # video thumbnails
    p7zip # archive listing/preview
    ouch # painless (de)compress, used by opener + previewer
    chafa # image fallback where kitty-graphics is unavailable
    mediainfo # rich media metadata in the preview
    lazygit # SPC g g target
    wl-clipboard # `y` yank-to-clipboard binding (wl-copy)
  ];
}
