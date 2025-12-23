{ config, pkgs, ... }: {
  # Hardened Nginx configuration for static site hosting with HTTPS

  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "mail@wolfhard.net";
      # Use Let's Encrypt staging for testing, switch to production when ready
      # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };
  };

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

    # Virtual hosts
    virtualHosts = {
      # Main site - wolfhard.net
      "wolfhard.net" = {
        # Enable ACME (Let's Encrypt) for this domain
        enableACME = true;
        # Force SSL and redirect HTTP to HTTPS
        forceSSL = true;
        # Also handle www subdomain
        serverAliases = [ "www.wolfhard.net" ];

        root = "/var/www/wolfhard";

        locations."/" = {
          index = "index.html";
          tryFiles = "$uri $uri/ =404";

          extraConfig = ''
            # Cache static assets
            location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
              expires 1y;
              add_header Cache-Control "public, immutable";
              # Re-add security headers (required when using add_header in nested location)
              add_header X-Frame-Options "SAMEORIGIN" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-XSS-Protection "1; mode=block" always;
              add_header Referrer-Policy "strict-origin-when-cross-origin" always;
              add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self';" always;
            }

            # Deny access to hidden files
            location ~ /\. {
              deny all;
            }
          '';
        };

        extraConfig = ''
          # Access logging
          access_log /var/log/nginx/wolfhard.net.access.log;
          error_log /var/log/nginx/wolfhard.net.error.log;

          # Charset
          charset utf-8;

          # Custom error pages
          error_page 404 /404.html;
          error_page 500 502 503 504 /50x.html;
        '';
      };

      # wolfhard.dev
      "wolfhard.dev" = {
        enableACME = true;
        forceSSL = true;
        serverAliases = [ "www.wolfhard.dev" ];

        root = "/var/www/wolfhard";

        locations."/" = {
          index = "index.html";
          tryFiles = "$uri $uri/ =404";
        };

        extraConfig = ''
          access_log /var/log/nginx/wolfhard.dev.access.log;
          error_log /var/log/nginx/wolfhard.dev.error.log;
          charset utf-8;
        '';
      };

      # wolfhard.tech
      "wolfhard.tech" = {
        enableACME = true;
        forceSSL = true;
        serverAliases = [ "www.wolfhard.tech" ];

        root = "/var/www/wolfhard";

        locations."/" = {
          index = "index.html";
          tryFiles = "$uri $uri/ =404";
        };

        extraConfig = ''
          access_log /var/log/nginx/wolfhard.tech.access.log;
          error_log /var/log/nginx/wolfhard.tech.error.log;
          charset utf-8;
        '';
      };

      # Default catch-all server (returns 444 - close connection)
      # Catches requests to unknown domains
      "_" = {
        default = true;

        extraConfig = ''
          return 444;
        '';
      };
    };
  };

  # Open firewall for nginx (HTTP and HTTPS)
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Create web directory
  systemd.tmpfiles.rules = [
    "d /var/www 0755 nginx nginx -"
    "d /var/www/wolfhard 0755 nginx nginx -"
  ];

  # Copy static website files
  environment.etc."nginx/www/index.html" = {
    source = ../../web/static/index.html;
    mode = "0644";
    user = "nginx";
    group = "nginx";
  };

  environment.etc."nginx/www/404.html" = {
    source = ../../web/static/404.html;
    mode = "0644";
    user = "nginx";
    group = "nginx";
  };

  # Create symlink from /var/www/wolfhard to /etc/nginx/www
  systemd.services.nginx-www-setup = {
    description = "Setup nginx www directory";
    wantedBy = [ "nginx.service" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Ensure /var/www exists
      mkdir -p /var/www

      # Remove old symlink/directory if exists
      rm -rf /var/www/wolfhard

      # Create symlink to /etc/nginx/www
      ln -sf /etc/nginx/www /var/www/wolfhard

      # Set permissions
      chown -R nginx:nginx /var/www
    '';
  };
}
