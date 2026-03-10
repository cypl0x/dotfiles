_: {
  services.n8n = {
    enable = true;
    environment = {
      N8N_HOST = "127.0.0.1";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "http";
      WEBHOOK_URL = "https://n8n.wolfhard.net";
      N8N_EDITOR_BASE_URL = "https://n8n.wolfhard.net";
    };
  };

  services.nginx.virtualHosts."n8n.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5678";
      proxyWebsockets = true;
    };
  };
}
