{...}: {
  imports = [
    ./common.nix
    ./doom.nix
  ];

  home = {
    username = "proxy";
  };
}
