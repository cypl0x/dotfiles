_: {
  imports = [./common.nix];

  home.username = "proxy";

  programs.openclaw = {
    enable = true;
    documents = ./proxy-documents;
    config = {
      gateway = {
        mode = "local";
        auth.mode = "none";
      };
      channels.telegram = {
        tokenFile = "/home/proxy/.secrets/telegram.token";
        allowFrom = [7295501323];
      };
    };
  };
}
