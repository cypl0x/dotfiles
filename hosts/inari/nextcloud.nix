{pkgs, ...}: {
  # Enable ACME for the nextcloud vhost (the nextcloud module sets forceSSL
  # but doesn't wire up ACME automatically)
  services.nginx.virtualHosts."nextcloud.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
  };

  services.nextcloud = {
    enable = true;
    hostName = "nextcloud.wolfhard.net";
    https = true;
    package = pkgs.nextcloud32;

    # Use local PostgreSQL (recommended over SQLite for production)
    database.createLocally = true;

    # Redis for APCu caching and distributed file locking
    configureRedis = true;

    # Allow large file uploads (calendars, contacts, documents, photos)
    maxUploadSize = "10G";

    # PHP optimizations recommended by Nextcloud
    phpOptions = {
      "opcache.interned_strings_buffer" = "23";
    };

    settings = {
      # Phone number formatting
      default_phone_region = "DE";

      # Run background maintenance jobs at 1 AM UTC (low traffic)
      maintenance_window_start = 1;

      # Ensure HTTPS URLs are generated correctly behind nginx reverse proxy
      overwriteprotocol = "https";
    };

    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      # Password file — set on the server before first deploy:
      # echo -n "your-password" > /etc/nextcloud-admin-pass && chmod 600 /etc/nextcloud-admin-pass
      adminpassFile = "/etc/nextcloud-admin-pass";
    };
  };
}
