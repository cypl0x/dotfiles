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
