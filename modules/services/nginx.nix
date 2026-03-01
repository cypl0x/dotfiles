_: {
  # Base nginx configuration with security hardening
  # Virtual hosts should be defined in host-specific configuration

  services.nginx = {
    enable = true;

    # Use recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Server-level hardening (no add_header here — headers are set per-vhost
    # to avoid nginx inheritance issues where server-level add_header drops
    # http-level add_header for any vhost that defines its own headers)
    appendHttpConfig = ''
      # Buffer sizes and timeouts
      client_body_buffer_size 10K;
      client_header_buffer_size 1k;
      large_client_header_buffers 4 8k;
      client_body_timeout 12;
      client_header_timeout 12;
      send_timeout 10;
    '';
  };

  # Open firewall for nginx (HTTP and HTTPS)
  networking.firewall.allowedTCPPorts = [80 443];

  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "mail@wolfhard.net";
      # Use Let's Encrypt staging for testing, switch to production when ready
      # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };
  };
}
