{lib, ...}: let
  nginxHelpers = import ../../modules/web/nginx-helpers.nix {inherit lib;};

  domain = "klosterpforte.wolfhard.net";

  # Where the deployed files live. They are uploaded to cypl0x's home directory,
  # but /home/cypl0x is 0700, so nginx cannot traverse into it. A read-only bind
  # mount exposes just this one directory under /var/www, which resolves without
  # touching the home directory's permissions — no chmod on $HOME required.
  source = "/home/cypl0x/klosterpforte";
  served = "/var/www/klosterpforte";
in {
  services.nginx.virtualHosts.${domain} =
    lib.recursiveUpdate
    (nginxHelpers.mkVirtualHost {
      inherit domain;
      root = served;
      enableACME = true;
      forceSSL = true;
      enableCaching = true;
      enableHtmlCache = true;

      # The site ships no inline scripts and loads nothing cross-origin, so it
      # runs under the strict policy.
      useStrictCSP = true;
    })
    {
      # Staging must not be indexed: the association's content belongs to
      # klosterpforte-kleve.de, and a second crawlable copy would compete with
      # it in search results. This shadows the robots.txt from the build, which
      # is written for the production domain.
      locations."= /robots.txt".extraConfig = ''
        add_header Content-Type text/plain always;
        return 200 "User-agent: *\nDisallow: /\n";
      '';
    };

  systemd.tmpfiles.rules = [
    "d ${source} 0755 cypl0x users -"
    "d ${served} 0755 root root -"
  ];

  fileSystems.${served} = {
    device = source;
    fsType = "none";
    options = ["bind" "ro" "nofail"];
  };
}
