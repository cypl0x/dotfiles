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
        docker-compose # podman's compose provider — see virtualisation.podman below
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

  # Containers: podman, not docker. Rootless by default, so a normal user's
  # containers no longer run as a root daemon's children.
  #
  # dockerCompat aliases `docker` -> podman, and dockerSocket serves
  # /run/docker.sock from podman for tools that hardcode it (testcontainers,
  # devcontainers, DOCKER_HOST). Both assert against virtualisation.docker.enable
  # — only one engine can own the name and the socket, so docker is off.
  #
  # Caveat worth knowing: the *socket* half is rootful, and the podman group that
  # guards it is root-equivalent exactly like the docker group was. Rootless
  # `podman`/`docker` CLI use does not touch it — it goes to the per-user socket
  # under $XDG_RUNTIME_DIR instead.
  #
  # docker-compose (the v2 Go binary) is podman's compose provider: podman finds
  # it on PATH, so `docker compose up` keeps working against the podman socket.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    # Container-name DNS on the default network (pulls in aardvark-dns).
    defaultNetwork.settings.dns_enabled = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
