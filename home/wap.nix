{lib, ...}: {
  imports = [./common.nix];

  home.username = "wap";

  # Work specific git config
  # NOTE: Update user.email with your actual work email address
  programs.git = {
    settings = {
      user.name = lib.mkForce "Work Account";
      user.email = lib.mkForce "wap@work.com";
    };
  };
}
