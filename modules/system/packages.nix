{pkgs, ...}: {
  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;

  # Global packages available to all users
  environment.systemPackages = with pkgs; [
    aider-chat-full
    alejandra # Nix code formatter
    bat
    cheat
    claude-code
    deadnix # Find unused Nix code
    emacs
    eza # Modern replacement for ls (formerly exa)
    fd # Fast file finder (used in Makefile)
    fzf
    git
    gnumake
    navi
    ollama
    pandoc
    ripgrep
    statix # Nix linter
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

  # Git is configured per-user in home-manager (see home/common.nix)
  # This ensures each user can have their own git identity
  programs.git.enable = true;
}
