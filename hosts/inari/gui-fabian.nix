{pkgs, ...}: let
  mkXfceVnc = import ./gui-vnc-xfce-common.nix {inherit pkgs;};
in
  mkXfceVnc {
    user = "fabian";
    display = 2;
    port = 5902;
  }
