{
  pkgs,
  llm-agents,
  ...
}: let
  # Fresh agent harnesses from numtide/llm-agents.nix (binary cache:
  # cache.numtide.com). Keep nixpkgs.follows unset on that input so these
  # store paths match their CI builds.
  agents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in {
  # Allow unfree packages (e.g., claude-code, antigravity-cli, grok)
  nixpkgs.config.allowUnfree = true;

  environment = {
    # Global packages available to all users
    systemPackages =
      (with pkgs; [
        aider-chat-full # CLI backing aider.el (home/doom/config.el); not in llm-agents
        alejandra # Nix code formatter
        bat
        cheat
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
        ollama # local models; not an llm-agents harness
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
      ])
      ++ (with agents; [
        # AI coding agents / harnesses (llm-agents.nix — not nixpkgs)
        antigravity-cli # Google agent CLI (gemini-cli successor; not nixpkgs antigravity)
        claude-code
        claude-desktop
        codex # OpenAI Codex CLI
        grok # xAI Grok Build (agent-shell ACP: grok agent stdio)
        kilocode-cli
        opencode
        pi
      ]);

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
