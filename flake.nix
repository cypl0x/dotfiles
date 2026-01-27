{
  description = "nix flake dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    datapass.url = "github:cypl0x/datapass";
  };

  outputs = {
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    home-manager-stable,
    treefmt-nix,
    datapass,
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
  in {
    nixosConfigurations = {
      homelab = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/homelab
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users = {
                cypl0x = import ./home/cypl0x.nix;
                wap = import ./home/wap.nix;
                root = import ./home/root.nix;
              };
            };
          }
        ];
      };

      # VM configuration for testing
      homelab-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/homelab-vm
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users = {
                cypl0x = import ./home/cypl0x.nix;
                wap = import ./home/wap.nix;
                root = import ./home/root.nix;
              };
            };
          }
        ];
      };

      # ThinkPad laptop configuration (using stable 25.11)
      thinkpad = nixpkgs-stable.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit datapass;};
        modules = [
          ./hosts/thinkpad
          home-manager-stable.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users = {
                cypl0x = import ./home/cypl0x.nix;
                wap = import ./home/wap.nix;
                root = import ./home/root.nix;
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
      # treefmt check
      formatting =
        pkgs.runCommand "treefmt-check" {
          nativeBuildInputs = [treefmtEval.config.build.wrapper];
          src = ./.;
        } ''
          cd $src
          treefmt --no-cache --fail-on-change
          touch $out
        '';

      statix =
        pkgs.runCommand "statix-check" {
          nativeBuildInputs = [pkgs.statix];
          src = ./.;
        } ''
          cp -r $src source
          cd source
          statix check
          touch $out
        '';

      deadnix =
        pkgs.runCommand "deadnix-check" {
          nativeBuildInputs = [pkgs.deadnix];
          src = ./.;
        } ''
          cp -r $src source
          cd source
          deadnix --fail
          touch $out
        '';

      shellcheck =
        pkgs.runCommand "shellcheck-check" {
          nativeBuildInputs = [pkgs.shellcheck pkgs.fd];
          src = ./.;
        } ''
          cp -r $src source
          cd source
          # Exclude completions.sh as it uses zsh-specific syntax (shellcheck doesn't support zsh)
          fd -e sh --exclude 'home/shell/zsh/completions.sh' -x shellcheck {}
          touch $out
        '';
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
        ]);
    };
  };
}
