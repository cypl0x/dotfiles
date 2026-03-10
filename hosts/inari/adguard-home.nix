_: {
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      # Keep the UI private behind nginx.
      http.address = "127.0.0.1:3000";

      users = [
        {
          name = "admin";
          password = "$2y$10$e/8oAAzngXwgPAUUjlpdxuHBV71AZV9jwCisQOqh6Nfre3fJicLKa";
        }
      ];

      # Avoid clashing with systemd-resolved on port 53.
      dns = {
        bind_hosts = [
          "127.0.0.1"
          "::1"
        ];
        port = 5353;
        bootstrap_dns = [
          "1.1.1.1"
          "9.9.9.9"
        ];
        upstream_dns = [
          "https://dns.cloudflare.com/dns-query"
          "https://dns.quad9.net/dns-query"
        ];
      };

      dhcp.enabled = false;
    };
  };

  services.nginx.virtualHosts."adguard.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
    };
  };
}
