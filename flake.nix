{
  description = "nix flake dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    datapass.url = "github:cypl0x/datapass";
    blog = {
      url = "github:cypl0x/blog";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    authentik-nix = {
      url = "github:nix-community/authentik-nix/bf3c780157449d75ac8dfc184963d57d23f59e8c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    treefmt-nix,
    datapass,
    blog,
    nix-openclaw,
    disko,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # treefmt configuration
    treefmtEval = treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true; # nix formatter
        deadnix.enable = true; # nix: remove dead code
        statix.enable = true; # nix: anti-pattern linter
        stylua.enable = true; # lua formatter (wezterm.lua etc.)
        shellcheck = {
          enable = true;
        };
        shfmt = {
          enable = true;
          indent_size = 2;
        };
      };
      settings.formatter = {
        shellcheck = {
          includes = ["*.sh"];
          excludes = ["home/shell/zsh/completions.sh"];
        };
        shfmt = {
          includes = ["*.sh"];
          excludes = ["home/shell/zsh/completions.sh"];
        };
      };
    };

    mkRepoCheck = {
      name,
      nativeBuildInputs,
      script,
      writable ? false,
    }:
      pkgs.runCommand name {
        inherit nativeBuildInputs;
        src = ./.;
      } ''
        cp -r $src source
        ${
          if writable
          then "chmod -R u+w source"
          else ""
        }
        cd source
        ${script}
        touch $out
      '';

    hmBaseUsers = {
      cypl0x = import ./home/cypl0x.nix;
      wap = import ./home/wap.nix;
      root = import ./home/root.nix;
      proxy = import ./home/proxy.nix;
    };
  in {
    nixosConfigurations = {
      # ThinkPad laptop configuration (using unstable)
      thinkpad = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit datapass;};
        modules = [
          ./hosts/thinkpad
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # Move pre-existing unmanaged dotfiles aside instead of aborting
              # activation when a home.file target already exists on disk.
              backupFileExtension = "bak";
              sharedModules = [
                ./home/kitty-thinkpad.nix
                ./home/terminals.nix
                ./home/launchers.nix
                ./home/hyprland.nix
              ];
              users = hmBaseUsers;
            };
          }
        ];
      };

      # Hetzner Dedicated AX41-NVMe (Finnland, HEL1)
      inari = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit blog;};
        modules = [
          inputs."authentik-nix".nixosModules.default
          ./hosts/inari
          {nixpkgs.overlays = [nix-openclaw.overlays.default];}
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "bak";
              users =
                hmBaseUsers
                // {
                  proxy = {
                    imports = [
                      ./home/proxy.nix
                      ./home/proxy-openclaw.nix
                      nix-openclaw.homeManagerModules.openclaw
                    ];
                  };
                  fabian = import ./home/fabian.nix;
                };
            };
          }
        ];
      };
    };

    # Formatting with treefmt
    formatter.${system} = treefmtEval.config.build.wrapper;

    # Checks and lints
    checks.${system} = {
      formatting = mkRepoCheck {
        name = "treefmt-check";
        nativeBuildInputs = [treefmtEval.config.build.wrapper];
        writable = true;
        script = ''
          treefmt --no-cache --fail-on-change
        '';
      };

      statix = mkRepoCheck {
        name = "statix-check";
        nativeBuildInputs = [pkgs.statix];
        script = ''
          statix check
        '';
      };

      deadnix = mkRepoCheck {
        name = "deadnix-check";
        nativeBuildInputs = [pkgs.deadnix];
        script = ''
          deadnix --fail
        '';
      };

      shellcheck = mkRepoCheck {
        name = "shellcheck-check";
        nativeBuildInputs = [pkgs.shellcheck pkgs.fd];
        script = ''
          # Exclude completions.sh as it uses zsh-specific syntax (shellcheck doesn't support zsh)
          fd -e sh --exclude 'home/shell/zsh/completions.sh' -x shellcheck {}
        '';
      };

      elisp-format = mkRepoCheck {
        name = "elisp-format-check";
        nativeBuildInputs = [pkgs.emacs];
        script = ''
          ./home/bin/elisp-qa format-check
        '';
      };

      elisp-lint = mkRepoCheck {
        name = "elisp-lint-check";
        nativeBuildInputs = [pkgs.emacs];
        script = ''
          ./home/bin/elisp-qa lint
        '';
      };

      elisp-no-anon = mkRepoCheck {
        name = "elisp-no-anon-check";
        nativeBuildInputs = [pkgs.emacs];
        script = ''
          ./home/bin/elisp-qa lint-no-anon
        '';
      };

      markdownlint = mkRepoCheck {
        name = "markdownlint-check";
        nativeBuildInputs = [pkgs.markdownlint-cli pkgs.fd];
        script = ''
          fd -e md -x markdownlint {}
        '';
      };

      # Desktop configs — catch the runtime-only breakages that a normal Nix
      # build never sees (Hyprland rejects an option at load; waybar refuses
      # GTK-invalid CSS or bad Pango markup). Runs on `nix flake check`.
      desktop-configs = mkRepoCheck {
        name = "desktop-configs-check";
        nativeBuildInputs = [pkgs.hyprland pkgs.jq];
        script = ''
          export XDG_RUNTIME_DIR="$TMPDIR" HOME="$TMPDIR"

          echo "→ Hyprland --verify-config"
          Hyprland --verify-config -c home/hyprland/hyprland.conf 2>&1 | tee hypr.log || true
          if grep -qiE "config error|invalid dispatcher|does not exist" hypr.log; then
            echo "✗ Hyprland config has errors"; exit 1
          fi

          echo "→ waybar config.jsonc is valid JSON"
          # strip // line comments, then parse with jq
          sed 's://.*$::' home/hyprland/waybar/config.jsonc | jq empty

          echo "→ waybar: no GTK-invalid 8-digit hex in CSS"
          if grep -RnE '#[0-9a-fA-F]{8}\b' home/hyprland/waybar/*.css; then
            echo "✗ GTK CSS cannot parse #RRGGBBAA — use rgba()"; exit 1
          fi

          echo "→ waybar: no double-hash Pango colours in JSONC"
          if grep -RnE "color='##" home/hyprland/waybar/config.jsonc; then
            echo "✗ Pango markup color needs a single # (##51afef → #51afef)"; exit 1
          fi

          echo "✓ desktop configs OK"
        '';
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      packages =
        [
          treefmtEval.config.build.wrapper
        ]
        ++ (with pkgs; [
          gnumake
          alejandra
          deadnix
          statix
          fd
          shellcheck
          shfmt
          emacs
          markdownlint-cli
        ]);
    };
  };
}
