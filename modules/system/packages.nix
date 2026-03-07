{pkgs, ...}: {
  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;

  environment = {
    # Global packages available to all users
    systemPackages = with pkgs; [
      # aider-chat-full
      alejandra # Nix code formatter
      bat
      cheat
      # AI
      gemini-cli
      codex # OpenAI ChatGPT
      claude-code
      deadnix # Find unused Nix code
      devilspie2 # resize and position x11 windows
      eza # Modern replacement for ls (formerly exa)
      felix-fm # Tui file manager with vim-like key mapping
      fd # Fast file finder (used in Makefile)
      fzf
      git
      gnumake
      glow # cli to preview markdown files
      navi
      ollama
      pandoc
      ripgrep
      statix # Nix linter
      starship
      sxhkd
      tabby
      tailscale
      tealdeer
      tmux
      vim
      wl-clipboard
      xclip
      zsh-autosuggestions
      zsh-completions
    ];

    # Environment variables
    sessionVariables = {
      PAGER = "bat";
      BAT_PAGER = "less -R";
      BAT_THEME = "Doom Vibrant";
    };

    variables = {
      EDITOR = "emacsclient -nw -a ''";
    };
  };

  # Git is configured per-user in home-manager (see home/common.nix)
  # This ensures each user can have their own git identity
  programs.git.enable = true;
}
