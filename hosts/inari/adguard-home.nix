{config, ...}: {
  services = {
    # AdGuard Home should own DNS on :53 for Tailscale clients.
    # Disable systemd-resolved stub listener to avoid port conflicts.
    resolved.enable = false;

    adguardhome = {
      enable = true;
      openFirewall = false;
      mutableSettings = false;
      host = "127.0.0.1";
      port = 3000;
      settings = {
        users = [
          {
            name = "admin";
            password = "$2y$10$e/8oAAzngXwgPAUUjlpdxuHBV71AZV9jwCisQOqh6Nfre3fJicLKa";
          }
        ];

        # Bind DNS broadly and constrain reachability in the firewall.
        # This avoids brittle pinning to a potentially changing Tailscale IP,
        # while still preventing any public open resolver exposure.
        # Note: AdGuard's setup guide lists all listen addresses (including
        # public IPs), which can look scary; actual exposure is controlled by
        # firewall rules below that allow DNS only on tailscale0.
        dns = {
          bind_hosts = [
            "0.0.0.0"
            "::"
          ];
          port = 53;
          bootstrap_dns = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          upstream_dns = [
            "https://dns.cloudflare.com/dns-query"
            "https://dns.quad9.net/dns-query"
          ];
        };

        # Keep Cachix reachable for Nix substituters on this host.
        user_rules = [
          "@@||cachix.org^"
          "@@||cypl0x.cachix.org^"
        ];

        dhcp.enabled = false;
      };
    };

    nginx.virtualHosts."adguard.wolfhard.net" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
    };
  };

  # DNS should be reachable via Tailscale only.
  networking.firewall.interfaces."${config.services.tailscale.interfaceName}" = {
    allowedTCPPorts = [53];
    allowedUDPPorts = [53];
  };
}
