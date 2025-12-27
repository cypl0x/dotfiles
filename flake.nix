{
  description = "nix flake dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
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
    };

    # Formatting
    formatter.${system} = pkgs.alejandra;

    # Checks and lints
    checks.${system} = {
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

      formatting =
        pkgs.runCommand "formatting-check" {
          nativeBuildInputs = [pkgs.alejandra pkgs.fd];
          src = ./.;
        } ''
          cp -r $src source
          cd source
          fd -e nix -x alejandra --check {}
          touch $out
        '';

      shellcheck =
        pkgs.runCommand "shellcheck-check" {
          nativeBuildInputs = [pkgs.shellcheck pkgs.fd];
          src = ./.;
        } ''
          cp -r $src source
          cd source
          # Exclude zsh files as shellcheck doesn't support zsh
          fd -e sh --exclude 'home/shell/zsh' -x shellcheck {}
          touch $out
        '';
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        gnumake
        alejandra
        deadnix
        statix
        fd
        shellcheck
      ];
    };
  };
}
