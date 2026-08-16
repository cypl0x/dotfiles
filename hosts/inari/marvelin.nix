_: {
  # Reverse proxy for the marvelin app on 127.0.0.1:9079. The app itself is not
  # managed here; nginx only fronts whatever listens on that port.
  services.nginx.virtualHosts."marvelin.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9079";
      proxyWebsockets = true;
    };
  };
}
