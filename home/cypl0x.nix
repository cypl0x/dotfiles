{ config, pkgs, ... }:

{
  imports = [ ./common.nix ];

  home.username = "cypl0x";
  
  # Override git config if needed (though it matches the common default)
  programs.git = {
    userName = "Wolfhard Prell";
    userEmail = "mail@wolfhard.net";
  };
}
