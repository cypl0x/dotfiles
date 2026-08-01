_: {
  # Reverse proxy for fabian's app on 127.0.0.1:5903. The app itself is started
  # by fabian (not managed here); nginx only fronts whatever listens there.
  services.nginx.virtualHosts."fabinixos.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5903";
      proxyWebsockets = true;
    };
  };
}
