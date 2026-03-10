{pkgs, ...}: {
  services.home-assistant = {
    enable = true;
    # Discovery-focused core integrations without the huge all-components closure.
    extraComponents = [
      "tailscale"
      "tuya"
      "adguard"
      "ssdp"
      "zeroconf"
      "upnp"
      "dhcp"
      "homekit_controller"
      "onvif"
      "dlna_dmr"
      "dlna_dms"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      localtuya
      tuya_local
      adaptive_lighting
      scheduler
    ];

    config = {
      default_config = {};

      http = {
        server_host = "127.0.0.1";
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };

  services.nginx.virtualHosts."home-assistant.wolfhard.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
    };
  };
}
