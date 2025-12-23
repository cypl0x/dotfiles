{
  description = "NixOS configuration flake for homelab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
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
          ];
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.gnumake ];
      };
    };
}
