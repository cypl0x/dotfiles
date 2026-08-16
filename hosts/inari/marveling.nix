_: {
  # Reverse proxy for the marveling app on 127.0.0.1:9079. The app itself is not
  # managed here; nginx only fronts whatever listens on that port.
  services.nginx.virtualHosts."marveling.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9079";
      proxyWebsockets = true;
    };
  };
}
