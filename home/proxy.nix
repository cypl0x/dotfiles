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

      models.providers.ollama-local = {
        api = "ollama";
        baseUrl = "http://127.0.0.1:11434";
        models = [
          {
            id = "qwen2.5-coder:3b";
            name = "ollama/qwen2.5-coder:3b";
          }
          {
            id = "qwen2.5-coder:7b";
            name = "ollama/qwen2.5-coder:7b";
          }
          {
            id = "qwen2.5:1.5b";
            name = "ollama/qwen2.5:1.5b";
          }
        ];
      };
    };
  };
}
