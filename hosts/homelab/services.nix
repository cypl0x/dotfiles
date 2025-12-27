{
  pkgs,
  lib,
  ...
}: let
  # Build documentation from markdown
  docs = import ../../web/docs.nix {inherit pkgs;};

  # Import nginx helper functions
  nginxHelpers = import ../../modules/web/nginx-helpers.nix {inherit lib;};
in {
  # Host-specific service configurations
  # Base nginx configuration is in ../../modules/services/nginx.nix

  # Nginx virtual hosts for this server
  services.nginx.virtualHosts =
    # Main domain across all TLDs (wolfhard.{net,dev,tech})
    (nginxHelpers.mkMultiDomainVirtualHosts {
      name = "wolfhard";
      tlds = ["net" "dev" "tech"];
      root = "/var/www/wolfhard";
      enableCaching = true;
      useStrictCSP = false; # Using permissive CSP for service worker support
    })
    # Documentation subdomains across all TLDs (docs.wolfhard.{net,dev,tech})
    // (nginxHelpers.mkMultiDomainVirtualHosts {
      name = "wolfhard";
      subdomain = "docs";
      tlds = ["net" "dev" "tech"];
      root = "${docs}";
      enableCaching = true;
      enableHtmlCache = true;
      useStrictCSP = true; # Documentation can use strict CSP
    })
    # Default catch-all server (returns 444 - close connection)
    # Catches requests to unknown domains
    // {
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
  environment.etc = {
    "nginx/www/index.html" = {
      source = ../../web/static/index.html;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };

    "nginx/www/404.html" = {
      source = ../../web/static/404.html;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };

    "nginx/www/logo.svg" = {
      source = ../../web/static/logo.svg;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };

    "nginx/www/favicon.svg" = {
      source = ../../web/static/favicon.svg;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };

    "nginx/www/robots.txt" = {
      source = ../../web/static/robots.txt;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };

    "nginx/www/sitemap.xml" = {
      source = ../../web/static/sitemap.xml;
      mode = "0644";
      user = "nginx";
      group = "nginx";
    };
  };

  # Create symlink from /var/www/wolfhard to /etc/nginx/www
  systemd.services.nginx-www-setup = {
    description = "Setup nginx www directory";
    wantedBy = ["nginx.service"];
    before = ["nginx.service"];
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
