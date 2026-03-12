{
  blog,
  pkgs,
  ...
}: {
  # blog's build uses org-publish, which writes under $HOME.
  # In Nix sandbox HOME defaults to /homeless-shelter, so force a writable HOME.
  services.nginx.virtualHosts."blog.wolfhard.net" = {
    root =
      blog.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      (_: {
        HOME = "$TMPDIR";
      });
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      index = "index.html";
      tryFiles = "$uri $uri/ =404";
    };
  };
}
