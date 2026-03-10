_: {
  services.linkwarden = {
    enable = true;
    host = "127.0.0.1";
    port = 3001;
    database.createLocally = true;

    # Secret file — create on the server before first deploy:
    #   install -m 600 /dev/null /etc/linkwarden.env
    #   echo "NEXTAUTH_SECRET=$(openssl rand -base64 32)" >> /etc/linkwarden.env
    environmentFile = "/etc/linkwarden.env";
  };

  services.nginx.virtualHosts."linkwarden.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
    };
  };
}
