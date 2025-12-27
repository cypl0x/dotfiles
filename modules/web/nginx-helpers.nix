{lib}: let
  # Common security headers that should be included in all responses
  # These need to be re-added when using add_header in nested location blocks
  commonSecurityHeaders = ''
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';

  # Strict CSP without unsafe-inline (recommended for static sites)
  strictCSP = ''
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: https:; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self';" always;
  '';

  # Permissive CSP with unsafe-inline (only use if required for service workers or inline scripts)
  permissiveCSP = ''
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self';" always;
  '';

  # Combined security headers with strict CSP
  securityHeadersStrict = commonSecurityHeaders + strictCSP;

  # Combined security headers with permissive CSP
  securityHeadersPermissive = commonSecurityHeaders + permissiveCSP;

  # Static asset caching configuration
  staticAssetCache = {useStrictCSP ? true}: ''
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
      expires 1y;
      add_header Cache-Control "public, immutable";
      # Re-add security headers (required when using add_header in nested location)
      ${
      if useStrictCSP
      then securityHeadersStrict
      else securityHeadersPermissive
    }
    }
  '';

  # HTML caching configuration for documentation sites
  htmlCache = {useStrictCSP ? true}: ''
    location ~* \.html$ {
      expires 1h;
      add_header Cache-Control "public, must-revalidate";
      # Re-add security headers (required when using add_header in nested location)
      ${
      if useStrictCSP
      then securityHeadersStrict
      else securityHeadersPermissive
    }
    }
  '';

  # Deny access to hidden files
  denyHiddenFiles = ''
    location ~ /\. {
      deny all;
    }
  '';

  # Helper function to create a basic virtualhost configuration
  mkVirtualHost = {
    domain,
    root,
    serverAliases ? [],
    enableACME ? true,
    forceSSL ? true,
    enableCaching ? true,
    enableHtmlCache ? false,
    useStrictCSP ? true,
    extraConfig ? "",
    extraLocationConfig ? "",
  }: {
    inherit enableACME forceSSL root serverAliases;

    locations."/" = {
      index = "index.html";
      tryFiles = "$uri $uri/ =404";

      extraConfig =
        # Add security headers to main location block
        (
          if useStrictCSP
          then securityHeadersStrict
          else securityHeadersPermissive
        )
        + (lib.optionalString enableCaching (staticAssetCache {inherit useStrictCSP;}))
        + (lib.optionalString enableHtmlCache (htmlCache {inherit useStrictCSP;}))
        + denyHiddenFiles
        + extraLocationConfig;
    };

    extraConfig =
      ''
        access_log /var/log/nginx/${domain}.access.log;
        error_log /var/log/nginx/${domain}.error.log;
        charset utf-8;

        # Custom error pages
        error_page 404 /404.html;
        error_page 500 502 503 504 /50x.html;
      ''
      + extraConfig;
  };

  # Helper to create multiple virtualhosts for different TLDs
  mkMultiDomainVirtualHosts = {
    name,
    tlds ? ["net" "dev" "tech"],
    subdomain ? null,
    root,
    enableCaching ? true,
    enableHtmlCache ? false,
    useStrictCSP ? true,
    extraConfig ? "",
  }: let
    # Generate domain name
    mkDomain = tld:
      if subdomain != null
      then "${subdomain}.${name}.${tld}"
      else "${name}.${tld}";

    # Generate www alias
    mkWwwAlias = domain: "www.${domain}";

    # Create virtualhost entries
    mkEntries = tld: let
      domain = mkDomain tld;
    in
      lib.nameValuePair domain (mkVirtualHost {
        inherit domain root enableCaching enableHtmlCache useStrictCSP extraConfig;
        serverAliases =
          if subdomain == null
          then [
            (mkWwwAlias domain)
          ]
          else [];
      });
  in
    lib.listToAttrs (map mkEntries tlds);
in {
  inherit
    commonSecurityHeaders
    strictCSP
    permissiveCSP
    securityHeadersStrict
    securityHeadersPermissive
    staticAssetCache
    htmlCache
    denyHiddenFiles
    mkVirtualHost
    mkMultiDomainVirtualHosts
    ;
}
