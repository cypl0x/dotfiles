{lib, ...}: {
  imports = [./common.nix];

  home.username = "wap";

  # Work account git config (using same email as cypl0x)
  programs.git = {
    settings = {
      user.name = lib.mkForce "Work Account";
      user.email = lib.mkForce "mail@wolfhard.net";
    };
  };
}
