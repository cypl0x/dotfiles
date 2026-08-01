{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./neovim.nix
  ];

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
    file = {
      # ".zshrc".source = ./zshrc;

      # Disable KDE Plasma's Baloo file indexer — it is a persistent CPU/RAM
      # hog (baloo_file + baloorunner) and the biggest steady-state slowdown
      # on this machine. No-op on hosts without Plasma.
      ".config/baloofilerc".text = ''
        [Basic Settings]
        Indexing-Enabled=false
      '';

      ".local/bin/e" = {
        source = ./bin/e;
        executable = true;
      };

      ".local/bin/emacsmail" = {
        source = ./bin/emacsmail;
        executable = true;
      };

      ".local/bin/elisp-qa.el" = {
        source = ./bin/elisp-qa.el;
      };

      ".local/bin/elisp-qa" = {
        source = ./bin/elisp-qa;
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
        # fzf-tmux-url — fzf picker over the URLs in the pane. Its default
        # binding is `prefix + u`, which shell/tmux.conf overrides with
        # clear-history, so until now the plugin was loaded but unreachable.
        # Same load-order rule as tmux-thumbs below: fzf-url.tmux reads
        # @fzf-url-bind at load time, so the option rides with the plugin.
        {
          plugin = fzf-tmux-url;
          extraConfig = ''
            set -g @fzf-url-bind U
            # Default 'screen' only scans the visible rows; a number scans that
            # many lines of scrollback instead, so a URL that scrolled past is
            # still reachable.
            set -g @fzf-url-history-limit 5000
          '';
        }
        # tmux-thumbs — vimium-style hint labels over every match in the pane
        # (paths, hashes, UUIDs, IPs, URLs); press the label to grab it. This
        # is the "point at a thing already on screen" half of the problem;
        # extrakto (prefix + Tab) is the "fuzzy-search the scrollback" half.
        #
        # Options MUST be set before the plugin's own run-shell, because
        # tmux-thumbs.tmux reads @thumbs-key at load time to create its
        # binding. home-manager emits a plugin's `extraConfig` immediately
        # before its run-shell line, whereas programs.tmux.extraConfig lands
        # after every plugin — which is why this is attached to the plugin.
        {
          plugin = tmux-thumbs;
          extraConfig = ''
            # Default key is `space`, which shell/tmux.conf already binds to
            # send-prefix. `g` = grab, and is free in the prefix table.
            set -g @thumbs-key g
            # -w copies to the *system* clipboard via OSC52 as well as the tmux
            # buffer. Works over SSH and under any OSC52-capable terminal
            # (ghostty has clipboard-write = allow), unlike a wl-copy call,
            # which is dead on the kernel VT and on the remote end of an SSH
            # session.
            set -g @thumbs-command 'tmux set-buffer -w -- {}'
            # Upcase (Shift+label) types the match into the pane instead.
            set -g @thumbs-upcase-command 'tmux set-buffer -- {} && tmux paste-buffer'
            # Collapse duplicate matches onto one hint, and hand out the short
            # hints starting from the bottom of the screen — the newest output
            # is what you almost always want.
            set -g @thumbs-unique enabled
            set -g @thumbs-reverse enabled
            # Doom Vibrant.
            set -g @thumbs-fg-color '#7bc275'
            set -g @thumbs-bg-color '#242730'
            set -g @thumbs-hint-fg-color '#fcce7b'
            set -g @thumbs-hint-bg-color '#1c1f24'
            set -g @thumbs-select-fg-color '#51afef'
            set -g @thumbs-select-bg-color '#242730'
          '';
        }
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

      # Faster startup: only rebuild the completion dump (and re-run compinit's
      # security check) when the cached dump is >24h old; otherwise take the
      # trusted fast path (compinit -C). Dump lives under ~/.cache/zsh.
      completionInit = ''
        autoload -Uz compinit
        _zcompdump="$HOME/.cache/zsh/zcompdump"
        [[ -d "$HOME/.cache/zsh" ]] || mkdir -p "$HOME/.cache/zsh"
        if [[ -n $_zcompdump(#qN.mh+24) ]]; then
          compinit -d "$_zcompdump"
        else
          compinit -C -d "$_zcompdump"
        fi
        unset _zcompdump
      '';

      envExtra = ''
        source ${./shell/zsh/env.sh}
      '';

      # oh-my-zsh removed: its git/tmux plugins only added aliases already
      # defined in shell/zsh/aliases.sh, and its fzf plugin duplicated the
      # keybindings from programs.fzf.enableZshIntegration. Dropping it removes a
      # second compinit and a chunk of startup. The sane defaults it used to set
      # (emacs keys, history opts, auto_cd) are declared explicitly below.
      history = {
        size = 100000;
        save = 100000;
        ignoreDups = true;
        ignoreSpace = true;
        expireDuplicatesFirst = true;
        share = true;
        extended = true;
      };

      # fzf-tab — replace zsh's plain tab menu with an fzf picker (fuzzy, with
      # previews). Must load after compinit (oh-my-zsh runs it) and before
      # syntax-highlighting; home-manager sources plugins in that window.
      plugins = [
        {
          name = "fzf-tab";
          src = pkgs.zsh-fzf-tab;
          file = "share/fzf-tab/fzf-tab.plugin.zsh";
        }
      ];

      initContent = ''
        # Baseline interactive options previously provided by oh-my-zsh.
        bindkey -e                                  # emacs keymap
        setopt auto_cd auto_pushd pushd_ignore_dups pushd_silent
        setopt hist_verify hist_reduce_blanks interactive_comments

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

    # zoxide — frecency-ranked `cd`. `z foo` jumps to the best-matching dir,
    # `zi` opens an fzf picker. Complements (does not replace) the dl/doc/dt
    # aliases in shell/zsh/aliases.sh.
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # atuin — SQLite-backed shell history with fuzzy search (rebinds Ctrl-R and
    # Up). Local-only by default; no sync server configured here.
    atuin = {
      enable = true;
      enableZshIntegration = true;
      flags = ["--disable-up-arrow"]; # keep Up = literal previous line; Ctrl-R = atuin
      settings = {
        style = "compact";
        inline_height = 20;
        show_preview = true;
        # AI assistant on `?` at an empty prompt. Must be declared here: the
        # `atuin config set ai.enabled true` the TUI suggests writes to
        # config.toml, which HM symlinks read-only out of /nix/store.
        # Auth token stays out of the store — export ATUIN_AI__API_TOKEN.
        ai.enabled = true;
      };
    };

    # direnv + nix-direnv — per-project environments auto-load on `cd` from a
    # .envrc (`use flake` / `use nix`). nix-direnv adds fast, GC-safe caching.
    # This is the shell-level counterpart to the emacs direnv already wired in
    # home/emacs-deps.nix.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };

    emacs = {
      enable = true;
      package = pkgs.emacs-git-pgtk;
      extraPackages = epkgs: [
        epkgs.vterm
        epkgs.eat
        epkgs.ghostel
      ];
    };
  };
}
