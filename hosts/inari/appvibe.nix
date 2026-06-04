_: {
  # Reverse proxy for the local appvibe Node.js app on 127.0.0.1:9000.
  services.nginx.virtualHosts."appvibe-store.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
    };
    # APK uploads need larger bodies and longer timeouts than the global
    # defaults in modules/services/nginx.nix (1m body, 12s body timeout).
    extraConfig = ''
      client_max_body_size 512m;
      client_body_timeout 300s;
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
    '';
  };
}
