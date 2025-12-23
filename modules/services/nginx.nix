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
      # Core Security Headers
      add_header X-Frame-Options "DENY" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;

      # Strict Transport Security (HSTS)
      # Enforce HTTPS for 1 year including subdomains
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

      # Content Security Policy
      # Allows inline scripts/styles (for service worker registration), restricts everything else
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; worker-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests;" always;

      # Permissions Policy (formerly Feature-Policy)
      # Disable unnecessary browser features
      add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=(), ambient-light-sensor=(), autoplay=(), display-capture=(), document-domain=(), encrypted-media=(), fullscreen=(self), midi=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), xr-spatial-tracking=()" always;

      # Cross-Origin Policies
      add_header Cross-Origin-Embedder-Policy "require-corp" always;
      add_header Cross-Origin-Opener-Policy "same-origin" always;
      add_header Cross-Origin-Resource-Policy "same-origin" always;

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
