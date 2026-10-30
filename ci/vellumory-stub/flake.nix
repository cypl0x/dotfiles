# Stand-in for the vellumory input in CI. The real input is a local checkout
# of a private repository, which no runner can fetch. CI overrides it with:
#
#   --override-input vellumory path:./ci/vellumory-stub
#   --override-input vellumory/nixpkgs nixpkgs
#
# Same interface as home/vellumory.nix uses: a callPackage'd `vellumory`
# (so `.override { tesseractLanguages = ...; }` works) and doom/tools/vellumory.
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.vellumory = pkgs.callPackage ({
      runCommand,
      tesseractLanguages ? [],
    }:
      runCommand "vellumory-stub" {passthru = {inherit tesseractLanguages;};} ''
        mkdir -p $out/bin
      '') {};
  };
}
