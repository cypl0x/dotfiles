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
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    treefmt-nix,
    datapass,
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
        alejandra.enable = true;
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
              sharedModules = [
                ./home/kitty-thinkpad.nix
              ];
              users = hmBaseUsers;
            };
          }
        ];
      };

      # Hetzner Dedicated AX41-NVMe (Finnland, HEL1)
      inari = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
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
