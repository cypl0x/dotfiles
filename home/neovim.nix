{pkgs, ...}: {
  # Neovim runs LazyVim (https://lazyvim.org) — a Doom-Emacs-shaped distro:
  # Space leader, which-key menus, the usual SPC f / SPC b / SPC g chords.
  #
  # Split of responsibilities:
  #   Nix         → neovim, lazy.nvim, and every external binary (LSP servers,
  #                 formatters, compilers, pickers' fd/rg).
  #   lazy.nvim   → the ~40 Lua plugins of the LazyVim spec, cloned from GitHub
  #                 into ~/.local/share/nvim/lazy and pinned by
  #                 ~/.local/share/nvim/lazy-lock.json. `:Lazy update` bumps
  #                 them; `nrs` does not.
  # mason is disabled (see neovim/lua/plugins/nixos.lua) because its prebuilt
  # binaries cannot run on NixOS — hence the long extraPackages list.
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = false; # adopt the new 26.05 default; silences the eval warning

    extraPackages = with pkgs; [
      # lazy.nvim + treesitter's :TSUpdate need these at runtime
      git
      gcc
      tree-sitter

      # pickers, clipboard, git UI
      fd
      ripgrep
      wl-clipboard
      xclip
      lazygit

      # language servers (mason's job upstream)
      bash-language-server
      lua-language-server
      marksman
      nil

      # formatters LazyVim reaches for
      shfmt
      stylua
    ];

    # Only lazy.nvim itself — everything else is managed by lazy.nvim at runtime.
    # Adding plugins here as well would shadow lazy's copies.
    plugins = [pkgs.vimPlugins.lazy-nvim];
  };

  xdg.configFile = {
    "nvim/init.lua".source = ./neovim/init.lua;
    "nvim/lua".source = ./neovim/lua;
    "nvim/colors".source = ./neovim/colors;
  };
}
