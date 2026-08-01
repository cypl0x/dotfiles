{pkgs, ...}: {
  services = {
    redis.servers.authentik = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
    };

    authentik = {
      enable = true;
      createDatabase = true;

      # Create on server before first deploy:
      #   install -d -m 700 /etc/authentik
      #   install -m 600 /dev/null /etc/authentik/secrets.env
      #   echo "AUTHENTIK_SECRET_KEY=<openssl rand -base64 50 | tr -d '\n='>" | tee -a /etc/authentik/secrets.env
      #   echo "AUTHENTIK_BOOTSTRAP_PASSWORD=<strong-password>" | tee -a /etc/authentik/secrets.env
      #   echo "AUTHENTIK_BOOTSTRAP_EMAIL=wolfhard@wolfhard.net" | tee -a /etc/authentik/secrets.env
      environmentFile = "/etc/authentik/secrets.env";

      settings.redis = {
        host = "127.0.0.1";
        port = 6379;
      };

      # authentik 2026.5 runs an HTTP server in the worker too; its default
      # [::1]:9001 collides with the tor relay's ORPort (modules/services/tor.nix).
      worker.listenHTTP = "[::1]:9011";
    };

    authentik-ldap = {
      enable = true;

      # Create on server after LDAP outpost token exists in Authentik UI:
      #   install -m 600 /dev/null /etc/authentik/ldap.env
      #   echo "AUTHENTIK_TOKEN=<ldap-outpost-token>" >> /etc/authentik/ldap.env
      environmentFile = "/etc/authentik/ldap.env";
    };

    nginx.virtualHosts."authentik.wolfhard.net" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "https://127.0.0.1:9443";
        proxyWebsockets = true;
      };
      locations."/outpost.goauthentik.io/" = {
        proxyPass = "https://127.0.0.1:9443/outpost.goauthentik.io/";
        proxyWebsockets = true;
      };
    };
  };

  systemd.services = {
    # Keep the Authentik web server internal-only. Port 9000 belongs to appvibe
    # (hosts/inari/appvibe.nix); nginx reaches authentik over 9443 either way.
    authentik.environment.AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9010";
    authentik.environment.AUTHENTIK_BLUEPRINTS_DIR = "${pkgs.authentik.src}/blueprints";
    authentik-worker.environment.AUTHENTIK_BLUEPRINTS_DIR = "${pkgs.authentik.src}/blueprints";
    authentik-migrate.environment.AUTHENTIK_BLUEPRINTS_DIR = "${pkgs.authentik.src}/blueprints";

    # Keep LDAP internal-only for local consumers.
    authentik-ldap.environment.AUTHENTIK_LISTEN__LDAP = "127.0.0.1:389";
  };
}
