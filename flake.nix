{
  description = "nix flake dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
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
      };

      checks.${system}.statix = pkgs.runCommand "statix-check" {
        nativeBuildInputs = [ pkgs.statix ];
        src = ./.;
      } ''
        cp -r $src source
        cd source
        statix check
        touch $out
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.gnumake ];
      };
    };
}