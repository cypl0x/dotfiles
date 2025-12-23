{config, ...}: {
  # Home Manager needs a bit of information about you and the paths it should manage.
  home = {
    # username is set by the importing module
    homeDirectory = "/home/${config.home.username}";

    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    stateVersion = "23.11"; # Please read the comment before changing.

    # The home.packages option allows you to install Nix packages into your
    # environment.
    packages = [
      # Packages are managed globally in modules/system/packages.nix
      # but we can add user-specific ones here if needed.
    ];

    # Home Manager is pretty good at managing dotfiles. The primary way to manage
    # plain files is through 'home.file'.
    file = {
      # ".zshrc".source = ./zshrc;

      # Aider configuration
      ".aider.conf.yml".text = ''
        model: ollama/deepseek-coder:1.3b

        # Use local ollama instance
        # ollama-api-base: http://localhost:11434

        # Editor settings
        # editor: vim

        # Auto-commit changes
        auto-commits: false

        # Show diffs before committing
        show-diffs: true
      '';
    };

    sessionVariables = {
      EDITOR = "vim";
    };
  };

  # Let Home Manager install and manage itself.
  programs = {
    home-manager.enable = true;

    git = {
      enable = true;
      settings = {
        user.name = "Wolfhard Prell"; # Can be overridden in user specific files
        user.email = "mail@wolfhard.net";
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    tmux = {
      enable = true;
      clock24 = true;
      keyMode = "vi";
      # Use the existing tmux.conf
      extraConfig = builtins.readFile ./shell/tmux.conf;
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      # Load settings from existing toml
      settings = builtins.fromTOML (builtins.readFile ./shell/starship.toml);
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      oh-my-zsh = {
        enable = true;
        plugins = ["git" "fzf" "tmux"];
        theme = "robbyrussell"; # Overridden by starship anyway
      };

      initContent = ''
        # Source existing aliases and functions
        if [ -f ${./shell/zsh/aliases.sh} ]; then
          source ${./shell/zsh/aliases.sh}
        fi

        # Source shell completions
        if [ -f ${./shell/zsh/completions.sh} ]; then
          source ${./shell/zsh/completions.sh}
        fi

        # Shellfish integration
        if [ -f ${./shell/shellfishrc} ]; then
          source ${./shell/shellfishrc}
        fi

        # Custom functions that were previously in modules/system/shell.nix
        # Detect dotfiles directory (default to ~/dotfiles if DOTFILES_DIR not set)
        export DOTFILES_DIR="''${DOTFILES_DIR:-$HOME/dotfiles}"

        # NixOS update function
        nixup() {
          local hostname=$(hostname)
          cd "$DOTFILES_DIR"
          nix flake update
          sudo nixos-rebuild switch --flake ".#$hostname"
        }

        # Update specific flake input
        nixup-input() {
          if [ -z "$1" ]; then
            echo "Usage: nixup-input <input-name>"
            echo "Example: nixup-input nixpkgs"
            return 1
          fi
          local hostname=$(hostname)
          cd "$DOTFILES_DIR"
          nix flake lock --update-input "$1"
          sudo nixos-rebuild switch --flake ".#$hostname"
        }

        # Quick flake check
        nixcheck() {
          cd "$DOTFILES_DIR"
          echo "Running flake check..."
          nix flake check
          echo "Running statix check..."
          statix check
        }

        nixshow() {
          cd "$DOTFILES_DIR"
          nix flake show
        }

        # Quick rebuild shortcuts (using dynamic hostname and dotfiles path)
        nrs() {
          statix check "$DOTFILES_DIR" && sudo nixos-rebuild switch --flake "$DOTFILES_DIR#$(hostname)"
        }

        nrb() {
          statix check "$DOTFILES_DIR" && sudo nixos-rebuild boot --flake "$DOTFILES_DIR#$(hostname)"
        }

        nrt() {
          statix check "$DOTFILES_DIR" && sudo nixos-rebuild test --flake "$DOTFILES_DIR#$(hostname)"
        }

        nrsv() {
          statix check "$DOTFILES_DIR" && sudo nixos-rebuild switch --flake "$DOTFILES_DIR#$(hostname)" --show-trace
        }

        nrbs() {
          statix check "$DOTFILES_DIR" && sudo nixos-rebuild build --flake "$DOTFILES_DIR#$(hostname)"
        }

        nixlint() {
          statix check "$DOTFILES_DIR"
        }
      '';
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      tmux.enableShellIntegration = true;
    };
  };
}
