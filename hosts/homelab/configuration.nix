{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./vultr.nix
    ./users.nix
    ./nginx.nix
  ];

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
    tailscale
    tealdeer
    tmux
    vim
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
      # Source ShellFish integration
      if [ -f /etc/dotfiles/shellfishrc ]; then
        source /etc/dotfiles/shellfishrc
      fi

      # Source shell aliases and functions
      if [ -f /etc/dotfiles/shell-aliases.sh ]; then
        source /etc/dotfiles/shell-aliases.sh
      fi

      # Source shell completions
      if [ -f /etc/dotfiles/shell-completions.sh ]; then
        source /etc/dotfiles/shell-completions.sh
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
      alias nrs='sudo nixos-rebuild switch --flake /root/dotfiles#homelab'
      alias nrb='sudo nixos-rebuild boot --flake /root/dotfiles#homelab'
      alias nrt='sudo nixos-rebuild test --flake /root/dotfiles#homelab'
      alias nrsv='sudo nixos-rebuild switch --flake /root/dotfiles#homelab --show-trace'
      alias nrbs='sudo nixos-rebuild build --flake /root/dotfiles#homelab'

      # NixOS update function
      nixup() {
        cd /root/dotfiles
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
        cd /root/dotfiles
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
        cd /root/dotfiles
        nix flake check
      }

      # Show flake outputs
      nixshow() {
        cd /root/dotfiles
        nix flake show
      }
    '';
  };

  # Install dotfiles to /etc/dotfiles
  environment.etc."dotfiles/shellfishrc".source = ../../home/shellfishrc;
  environment.etc."dotfiles/shell-aliases.sh".source = ../../home/shell-aliases.sh;
  environment.etc."dotfiles/shell-completions.sh".source = ../../home/shell-completions.sh;

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "homelab";
  networking.domain = "";

  # SSH with ShellFish Support
  services.openssh = {
    enable = true;
    settings = {
      # Allow LC_TERMINAL for ShellFish
      AcceptEnv = [ "LANG" "LC_*" ];

      # Security Hardening
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Tailscale Exit Node
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };

  # Tor Relay (non-exit)
  services.tor = {
    enable = true;
    relay = {
      enable = true;
      role = "relay";
    };
    settings = {
      Nickname = "cypl0x";
      ContactInfo = "tor-relay@homelab";
      ORPort = 9001;
      ControlPort = 9051;
      # Bandwidth limits (adjust as needed)
      # RelayBandwidthRate = "1 MBytes";
      # RelayBandwidthBurst = "2 MBytes";
      # Explicitly reject exit traffic
      ExitPolicy = "reject *:*";
    };
  };

  # Open firewall for Tor relay
  networking.firewall.allowedTCPPorts = [ 9001 ];

  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDHOc2Af91XVXmUxuCiKeELkM6b+zVK1ob9ciicNcyIdew4MdSkA1M4GkZQ5TRigqCV8245DHTzgQcHD5/+WCv4X6NC7nihxFDpGXt1ywnjtwoZH8U0c2BdhU7pAmHMJCeiZaBkuaEVdTtR/7NBLtFHeDx+rnGB9Ghp4As2tJi+Ds1GBqHBww7kCmGxxku5uqLal6QIGb8M9TfcXzWObOj6sZQPpOsUHwuDVB7TGFNItworFLO0QgRzndGhjMF/cDxktbDPfq4Bsf3fk8G/r/t920syGswToZwNTIeTgw4qOQTpwu6g0NgnqRFtSLU2xmFSRvtKaR1pf7lbQu79wNNqEs/Fu03QwmVfuhWfK+R+DQw4e3m3K6hwv4EfVspe72jAoQPSWU+d++CEutVeLb3CLNPCEWID34YcDyQxSH5dr0++XE1qRz05WMyzt9PkDV4RU8Wf4awIJA7lEnvF/2tZU1AIOqo8JKWja6JawN0OkWohTlDfiHs2pz9pFQgy4VXxI543SeehVB0tPNFTb5Si4jX8n4X9+834wqlVFwFqFZL+3ZGmxpXvMVwMFr28unzq7/bS+p2Cj5dwNUtmt9Ac+7D38db0/yCj1rBOfmMOfOhuYw4HYcBp65z2c6ZHMI4FeWp9ApHl3Fn519pixhnZNw2igFitnHoBnomUNmbeNQ== homelab'' ];
  };

  system.stateVersion = "23.11";
}
