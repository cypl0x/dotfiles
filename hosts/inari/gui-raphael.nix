{pkgs, ...}: let
  mkXfceVnc = import ./gui-vnc-xfce-common.nix {inherit pkgs;};
in
  # Port 5903 is taken by fabian's app behind fabinixos.wolfhard.net, so this
  # display uses 5904 instead of the usual 5900 + display number.
  mkXfceVnc {
    user = "raphael";
    display = 3;
    port = 5904;
  }
