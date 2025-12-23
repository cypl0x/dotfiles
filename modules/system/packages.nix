{ pkgs, ... }: {
  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;

  # Global packages available to all users
  environment.systemPackages = with pkgs; [
    aider-chat-full
    bat
    cheat
    claude-code
    emacs
    eza  # Modern replacement for ls (formerly exa)
    fzf
    git
    gnumake
    navi
    ollama
    pandoc
    ripgrep
    statix
    starship
    tabby
    tailscale
    tealdeer
    tmux
    vim
    xclip
    zsh-autosuggestions
    zsh-completions
  ];

  # Environment variables
  environment.sessionVariables = {
    PAGER = "bat";
    BAT_PAGER = "less -R";
  };

  # Git configuration
  programs.git = {
    enable = true;
    config = {
      user = {
        name = "Wolfhard Prell";
        email = "mail@wolfhard.net";
      };
      init = {
        defaultBranch = "main";
      };
    };
  };
}
