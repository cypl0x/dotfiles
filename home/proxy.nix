_: {
  imports = [./common.nix];

  home.username = "proxy";

  home.sessionVariables = {
    OLLAMA_API_KEY = "ollama-local";
  };

  systemd.user.services.openclaw-gateway = {
    Service.Environment = "OLLAMA_API_KEY=ollama-local";
  };

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
      agents.defaults.model.primary = "ollama/qwen2.5-coder:3b";
    };
  };
}
