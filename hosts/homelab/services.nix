{ config, pkgs, ... }:

let
  # Build documentation from markdown
  docs = import ../../web/docs.nix { inherit pkgs; };
in

{
  # Host-specific service configurations
  # Base nginx configuration is in ../../modules/services/nginx.nix

  # Nginx virtual hosts for this server
  services.nginx.virtualHosts = {
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

    # Documentation subdomain - docs.wolfhard.net
    "docs.wolfhard.net" = {
      enableACME = true;
      forceSSL = true;

      root = "${docs}";

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

          # Cache HTML files for shorter duration
          location ~* \.html$ {
            expires 1h;
            add_header Cache-Control "public, must-revalidate";
            # Re-add security headers (required when using add_header in nested location)
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header X-XSS-Protection "1; mode=block" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
            add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self';" always;
          }
        '';
      };

      extraConfig = ''
        access_log /var/log/nginx/docs.wolfhard.net.access.log;
        error_log /var/log/nginx/docs.wolfhard.net.error.log;
        charset utf-8;
      '';
    };

    # Documentation subdomain - docs.wolfhard.dev
    "docs.wolfhard.dev" = {
      enableACME = true;
      forceSSL = true;

      root = "${docs}";

      locations."/" = {
        index = "index.html";
        tryFiles = "$uri $uri/ =404";
      };

      extraConfig = ''
        access_log /var/log/nginx/docs.wolfhard.dev.access.log;
        error_log /var/log/nginx/docs.wolfhard.dev.error.log;
        charset utf-8;
      '';
    };

    # Documentation subdomain - docs.wolfhard.tech
    "docs.wolfhard.tech" = {
      enableACME = true;
      forceSSL = true;

      root = "${docs}";

      locations."/" = {
        index = "index.html";
        tryFiles = "$uri $uri/ =404";
      };

      extraConfig = ''
        access_log /var/log/nginx/docs.wolfhard.tech.access.log;
        error_log /var/log/nginx/docs.wolfhard.tech.error.log;
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

  environment.etc."nginx/www/logo.svg" = {
    source = ../../web/static/logo.svg;
    mode = "0644";
    user = "nginx";
    group = "nginx";
  };

  environment.etc."nginx/www/favicon.svg" = {
    source = ../../web/static/favicon.svg;
    mode = "0644";
    user = "nginx";
    group = "nginx";
  };

  environment.etc."nginx/www/robots.txt" = {
    source = ../../web/static/robots.txt;
    mode = "0644";
    user = "nginx";
    group = "nginx";
  };

  environment.etc."nginx/www/sitemap.xml" = {
    source = ../../web/static/sitemap.xml;
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
