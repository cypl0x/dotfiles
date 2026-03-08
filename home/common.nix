{
  config,
  lib,
  pkgs,
  ...
}: {
  # Home Manager needs a bit of information about you and the paths it should manage.
  home = {
    # username is set by the importing module
    homeDirectory = "/home/${config.home.username}";

    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    # Review release notes before changing: https://github.com/nix-community/home-manager/releases
    stateVersion = "24.11";

    # The home.packages option allows you to install Nix packages into your
    # environment.
    packages = [
      # Packages are managed globally in modules/system/packages.nix
      # but we can add user-specific ones here if needed.
    ];

    # Home Manager is pretty good at managing dotfiles. The primary way to manage
    # plain files is through 'home.file'.
    file =
      {
        # ".zshrc".source = ./zshrc;

        ".local/bin/e" = {
          source = ./bin/e;
          executable = true;
        };

        ".local/bin/emacsmail" = {
          source = ./bin/emacsmail;
          executable = true;
        };

        ".local/share/applications/emacsmail.desktop".text = ''
          [Desktop Entry]
          Name=Emacs Mail
          GenericName=Email Client
          Comment=Compose mail in mu4e via Emacs daemon
          Exec=emacsmail %u
          Terminal=false
          Type=Application
          Categories=Network;Email;
          MimeType=x-scheme-handler/mailto;
        '';

        ".local/bin/sudo-askpass" = {
          source = ./bin/sudo-askpass;
          executable = true;
        };

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

        ".config/wezterm/wezterm.lua".source = ./wezterm/wezterm.lua;
        ".config/emacs/eshell/alias".source = ./shell/eshell/alias;
        ".config/doom/eshell/functions.el".source = ./shell/eshell/functions.el;
      }
      // lib.optionalAttrs (config.home.username != "proxy") {
        ".config/sxhkd/sxhkdrc".text = ''
          # Universal application launcher (Doom Emacs + Consult)
          super + space
            emacsclient --no-wait -e "(app-launcher)"
        '';
      };

    sessionVariables = {
      VISUAL = "emacsclient -c -a ''";
      COLORTERM = "truecolor";
      BAT_THEME = "Doom Vibrant";
    };

    sessionPath = [
      "$HOME/.local/bin"
    ];

    activation = {
      setMailtoHandler = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.xdg-utils}/bin/xdg-mime default emacsmail.desktop x-scheme-handler/mailto || true
      '';
    };
  };

  # Let Home Manager install and manage itself.
  programs = {
    home-manager.enable = true;

    gh = {
      enable = true;
      extensions = [
        pkgs.gh-notify
        pkgs.gh-dash
        pkgs.gh-poi
        pkgs.gh-actions-cache
      ];
    };

    bat = {
      enable = true;
      themes = {
        "Doom Vibrant" = {
          src = ./bat/themes;
          file = "doom-vibrant.tmTheme";
        };
      };
    };

    delta = {
      enable = true;
      # config can be found in programs.git.settings.delta
    };

    git = {
      enable = true;
      includes = [
        {path = ./shell/doom-vibrant-delta.gitconfig;}
      ];
      settings = {
        user.name = "Wolfhard Prell"; # Can be overridden in user specific files
        user.email = "mail@wolfhard.net";
        init.defaultBranch = "main";
        pull.rebase = true;
        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
        merge.conflictStyle = "diff3";
        delta = {
          navigate = true;
          features = "doom-vibrant";
          syntax-theme = "Doom Vibrant";
          line-numbers = true;
        };
      };
    };

    tmux = {
      enable = true;
      clock24 = true;
      keyMode = "vi";
      # Use the existing tmux.conf
      extraConfig = builtins.readFile ./shell/tmux.conf;
      plugins = with pkgs.tmuxPlugins; [
        extrakto
        fzf-tmux-url
      ];
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

      envExtra = ''
        source ${./shell/zsh/env.sh}
      '';

      oh-my-zsh = {
        enable = true;
        plugins = ["git" "fzf" "tmux"];
      };

      initContent = ''
        source ${./shell/zsh/aliases.sh}
        source ${./shell/zsh/completions.sh}
        source ${./shell/zsh/functions.sh}

        # Shellfish integration
        if [ -f ${./shell/shellfishrc} ]; then
          source ${./shell/shellfishrc}
        fi
      '';
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      tmux.enableShellIntegration = true;
    };

    emacs = {
      enable = true;
      package = pkgs.emacs-gtk;
      extraPackages = epkgs: [
        epkgs.vterm
        epkgs.eat
      ];
    };
  };

  systemd = {
    user = {
      services = {
        # Run sxhkd as a user service (X11 only)
        sxhkd = {
          Unit = {
            Description = "Simple X hotkey daemon";
            ConditionEnvironment = "XDG_SESSION_TYPE=x11";
            After = ["graphical-session.target"];
            PartOf = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${pkgs.sxhkd}/bin/sxhkd -c %h/.config/sxhkd/sxhkdrc";
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install = {
            WantedBy = ["graphical-session.target"];
          };
        };
      };

      targets = {
        "gnome-session@pantheon" = {
          Unit.Description = "GNOME Session (Pantheon)";
        };
        "gnome-session-x11@pantheon" = {
          Unit = {
            Description = "GNOME Session (X11) (session: pantheon)";
            After = ["gnome-session-pre.target"];
            Wants = [
              "gnome-session@pantheon.target"
              "gnome-session-x11-services.target"
              "gnome-session-x11-services-ready.target"
            ];
            BindsTo = ["gnome-session@pantheon.target"];
          };
        };
        "gnome-session-x11-services" = {
          Unit.Description = "GNOME Session X11 Services";
        };
        "gnome-session-x11-services-ready" = {
          Unit.Description = "GNOME Session X11 Services Ready";
        };
      };
    };
  };
}
