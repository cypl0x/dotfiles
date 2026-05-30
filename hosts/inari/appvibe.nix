_: {
  # Reverse proxy for the local appvibe Node.js app on 127.0.0.1:9000.
  services.nginx.virtualHosts."appvibe-store.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
    };
  };
}
