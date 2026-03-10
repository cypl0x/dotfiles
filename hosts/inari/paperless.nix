_: {
  services = {
    paperless = {
      enable = true;
      domain = "paperless.wolfhard.net";

      # Let the module wire up nginx; ACME is added below.
      configureNginx = true;

      # PostgreSQL (recommended over SQLite)
      database.createLocally = true;

      # Enable Tika + Gotenberg for Office documents and e-mail OCR
      configureTika = true;

      # Admin password file — create on the server before first deploy:
      #   echo -n "your-password" | sudo install -m 600 /dev/stdin /etc/paperless-admin-pass
      passwordFile = "/etc/paperless-admin-pass";

      settings = {
        # OCR languages (German + English — adjust as needed)
        PAPERLESS_OCR_LANGUAGE = "deu+eng";

        # Timezone for document date parsing
        PAPERLESS_TIME_ZONE = "UTC";

        # Consumer polling interval in seconds (0 = inotify, more efficient)
        PAPERLESS_CONSUMER_POLLING = 0;

        # Point to gotenberg on non-default port (3000 is taken by AdGuard Home)
        PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://localhost:3002";
      };
    };

    # Move gotenberg off port 3000 (conflict with AdGuard Home)
    gotenberg.port = 3002;

    # Add ACME/SSL on top of the vhost the paperless module creates
    nginx.virtualHosts."paperless.wolfhard.net" = {
      enableACME = true;
      forceSSL = true;
    };
  };
}
