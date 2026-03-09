_: {
  services.home-assistant = {
    enable = true;
    config = {
      default_config = {};

      http = {
        server_host = "127.0.0.1";
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };

  services.nginx.virtualHosts."home-assistant.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
    };
  };
}
