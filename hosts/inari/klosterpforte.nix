{lib, ...}: let
  nginxHelpers = import ../../modules/web/nginx-helpers.nix {inherit lib;};

  # Staging domain (not indexed) and the public production domain. Both serve
  # the exact same build; only their robots.txt handling differs.
  stagingDomain = "klosterpforte.wolfhard.net";
  publicDomain = "klosterpforte.org";

  # Where the deployed files live. They are uploaded to cypl0x's home directory,
  # but /home/cypl0x is 0700, so nginx cannot traverse into it. A read-only bind
  # mount exposes just this one directory under /var/www, which resolves without
  # touching the home directory's permissions — no chmod on $HOME required.
  source = "/home/cypl0x/klosterpforte";
  served = "/var/www/klosterpforte";

  # Common virtual-host settings shared by both domains. The site ships no inline
  # scripts and loads nothing cross-origin, so it runs under the strict CSP.
  mkKlosterpforte = domain:
    nginxHelpers.mkVirtualHost {
      inherit domain;
      root = served;
      enableACME = true;
      forceSSL = true;
      enableCaching = true;
      enableHtmlCache = true;
      useStrictCSP = true;
    };
in {
  services.nginx.virtualHosts = {
    # Staging must not be indexed: a second crawlable copy would compete with the
    # production domain in search results. This shadows the robots.txt from the
    # build (which permits crawling) and blocks every crawler instead.
    ${stagingDomain} =
      lib.recursiveUpdate (mkKlosterpforte stagingDomain) {
        locations."= /robots.txt".extraConfig = ''
          add_header Content-Type text/plain always;
          return 200 "User-agent: *\nDisallow: /\n";
        '';
      };

    # Production domain: identical serving, but the build's own robots.txt is left
    # in place so search engines may index it (needed for a clean SEO audit).
    ${publicDomain} = mkKlosterpforte publicDomain;
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
