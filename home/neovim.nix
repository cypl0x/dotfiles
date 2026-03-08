{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;

    extraPackages = with pkgs; [
      fd
      ripgrep
      wl-clipboard
      xclip
    ];

    plugins = with pkgs.vimPlugins; [
      plenary-nvim
      telescope-nvim
      telescope-fzf-native-nvim
      which-key-nvim
      project-nvim
      gitsigns-nvim
      nvim-treesitter.withAllGrammars
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      luasnip
      cmp_luasnip
      friendly-snippets
      nvim-autopairs
      comment-nvim
      lualine-nvim
      nvim-web-devicons
      vim-fugitive
      vim-surround
      vim-repeat
    ];
  };

  xdg.configFile = {
    "nvim/init.lua".source = ./neovim/init.lua;
    "nvim/lua/core/theme.lua".source = ./neovim/lua/core/theme.lua;
    "nvim/lua/core/options.lua".source = ./neovim/lua/core/options.lua;
    "nvim/lua/core/keymaps.lua".source = ./neovim/lua/core/keymaps.lua;
    "nvim/lua/core/autocmds.lua".source = ./neovim/lua/core/autocmds.lua;
    "nvim/lua/plugins/init.lua".source = ./neovim/lua/plugins/init.lua;
    "nvim/colors/doom-vibrant.lua".source = ./neovim/colors/doom-vibrant.lua;
  };
}
