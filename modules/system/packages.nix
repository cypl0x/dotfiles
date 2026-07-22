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
      opencode
      deadnix # Find unused Nix code
      eza # Modern replacement for ls (formerly exa)
      felix-fm # Tui file manager with vim-like key mapping
      fd # Fast file finder (used in Makefile)
      fzf
      git
      gnumake
      glow # cli to preview markdown files
      bc # Calculator
      gh # GitHub CLI tool
      tig # Git Tui
      navi
      ollama
      pandoc
      ripgrep
      statix # Nix linter
      starship
      sxhkd
      # tabby # disabled 2026-06-04: nixpkgs unstable's rustc rejects vendored metrics-0.22.3 (rust-lang/rust#141402). Re-enable once nixpkgs ships a fix.
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
      # Without this, man falls back to PAGER=bat, which renders man pages
      # with bat's grid/line-numbers/"STDIN" header. The zsh man() wrapper
      # (home/shell/zsh/aliases.sh) overrides MANPAGER for pretty bat output
      # in interactive shells; this is the sane default everywhere else.
      MANPAGER = "less";
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

  virtualisation.docker.enable = true;
}
