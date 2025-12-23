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

    # Security headers and hardening
    appendHttpConfig = ''
      # Security headers
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self';" always;

      # Buffer sizes and timeouts
      client_body_buffer_size 10K;
      client_header_buffer_size 1k;
      large_client_header_buffers 2 1k;
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
