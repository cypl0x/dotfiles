{ pkgs, ... }: {
  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      plugins = [ "git" "fzf" "tmux" ];
    };

    interactiveShellInit = ''
      # Initialize Starship prompt
      eval "$(${pkgs.starship}/bin/starship init zsh)"
      export STARSHIP_CONFIG=/etc/dotfiles/starship.toml

      # Source ShellFish integration
      if [ -f /etc/dotfiles/shellfishrc ]; then
        source /etc/dotfiles/shellfishrc
      fi

      # Source shell aliases and functions
      if [ -f /etc/dotfiles/zsh-aliases.sh ]; then
        source /etc/dotfiles/zsh-aliases.sh
      fi

      # Source shell completions
      if [ -f /etc/dotfiles/zsh-completions.sh ]; then
        source /etc/dotfiles/zsh-completions.sh
      fi

      # FZF configuration
      export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
      export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
      export FZF_ALT_C_OPTS="--preview 'ls -la {}'"

      # FZF key bindings and completion
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh

      # Additional completions
      fpath+=${pkgs.zsh-completions}/share/zsh/site-functions

      # NixOS rebuild aliases
      # Runs statix check before rebuilding to ensure code quality
      alias nrs='statix check ~/dotfiles && sudo nixos-rebuild switch --flake ~/dotfiles#homelab'
      alias nrb='statix check ~/dotfiles && sudo nixos-rebuild boot --flake ~/dotfiles#homelab'
      alias nrt='statix check ~/dotfiles && sudo nixos-rebuild test --flake ~/dotfiles#homelab'
      alias nrsv='statix check ~/dotfiles && sudo nixos-rebuild switch --flake ~/dotfiles#homelab --show-trace'
      alias nrbs='statix check ~/dotfiles && sudo nixos-rebuild build --flake ~/dotfiles#homelab'

      # NixOS update function
      nixup() {
        cd ~/dotfiles
        nix flake update
        sudo nixos-rebuild switch --flake .#homelab
      }

      # Update specific flake input
      nixup-input() {
        if [ -z "$1" ]; then
          echo "Usage: nixup-input <input-name>"
          echo "Example: nixup-input nixpkgs"
          return 1
        fi
        cd ~/dotfiles
        nix flake lock --update-input "$1"
        sudo nixos-rebuild switch --flake .#homelab
      }

      # Clean old generations
      nixclean() {
        local days=''${1:-30}
        echo "Deleting generations older than $days days..."
        sudo nix-collect-garbage --delete-older-than ''${days}d
        echo "Optimizing store..."
        sudo nix-store --optimise
      }

      # Full cleanup
      nixclean-all() {
        echo "Warning: This will delete all old generations!"
        read -q "REPLY?Continue? (y/N) "
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          sudo nix-collect-garbage -d
          sudo nix-store --optimise
        fi
      }

      # Show generations
      nixgen() {
        sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
      }

      # Show disk usage
      nixdu() {
        echo "=== Nix Store Usage ==="
        du -sh /nix/store
        echo ""
        echo "=== Generation Sizes ==="
        sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | \
          while read -r gen _; do
            if [[ $gen =~ ^[0-9]+$ ]]; then
              du -sh "/nix/var/nix/profiles/system-''${gen}-link" 2>/dev/null
            fi
          done
      }

      # Diff between generations
      nixdiff() {
        local gen1=''${1:-$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -2 | head -1 | awk '{print $1}')}
        local gen2=''${2:-$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -1 | awk '{print $1}')}
        nix store diff-closures \
          /nix/var/nix/profiles/system-''${gen1}-link \
          /nix/var/nix/profiles/system-''${gen2}-link
      }

      # Search packages
      nixsearch() {
        if [ -z "$1" ]; then
          echo "Usage: nixsearch <package-name>"
          return 1
        fi
        nix search nixpkgs "$1"
      }

      # Show package info
      nixinfo() {
        if [ -z "$1" ]; then
          echo "Usage: nixinfo <package-name>"
          return 1
        fi
        nix eval nixpkgs#$1.meta.description
        nix eval nixpkgs#$1.meta.homepage
      }

      # List installed packages
      nixlist() {
        nix-store -q --references /run/current-system/sw | \
          grep -v '\.drv$' | \
          sed 's|/nix/store/[a-z0-9]\{32\}-||' | \
          sort | \
          bat
      }

      # Enter nix-shell with packages
      nixshell() {
        nix-shell -p "$@"
      }

      # Run package without installing
      nixrun() {
        if [ -z "$1" ]; then
          echo "Usage: nixrun <package> [command]"
          echo "Example: nixrun hello hello"
          return 1
        fi
        local pkg=$1
        shift
        nix run nixpkgs#$pkg -- "$@"
      }

      # Try package temporarily
      nixtry() {
        if [ -z "$1" ]; then
          echo "Usage: nixtry <package>"
          return 1
        fi
        nix shell nixpkgs#$1
      }

      # Flake check
      nixcheck() {
        cd ~/dotfiles
        echo "Running flake check..."
        nix flake check
        echo "Running statix check..."
        statix check
      }
      
      # Lint nix files
      alias nixlint='statix check ~/dotfiles'

      # Show flake outputs
      nixshow() {
        cd ~/dotfiles
        nix flake show
      }
    '';
  };

  # Install dotfiles to /etc/dotfiles
  environment.etc = {
    "dotfiles/shellfishrc".source = ../../home/shell/shellfishrc;
    "dotfiles/zsh-aliases.sh".source = ../../home/shell/zsh/aliases.sh;
    "dotfiles/zsh-completions.sh".source = ../../home/shell/zsh/completions.sh;
    "dotfiles/starship.toml".source = ../../home/shell/starship.toml;
  };
}
