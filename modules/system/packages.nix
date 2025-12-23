{ pkgs, ... }: {
  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;

  # Global packages available to all users
  environment.systemPackages = with pkgs; [
    bat
    cheat
    claude-code
    emacs
    eza  # Modern replacement for ls (formerly exa)
    fzf
    git
    navi
    ripgrep
    starship
    tailscale
    tealdeer
    tmux
    vim
    xclip
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
