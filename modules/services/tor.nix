{
  config,
  lib,
  ...
}: {
  options.torRelay = {
    nickname = lib.mkOption {
      type = lib.types.str;
      default = "cypl0x";
      description = "Tor relay nickname";
    };
    bandwidthRate = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Sustained bandwidth rate in KBytes/s (0 = unlimited)";
    };
    bandwidthBurst = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Peak bandwidth burst in KBytes/s (0 = unlimited)";
    };
  };

  config = {
    # Tor Relay (non-exit)
    services.tor = {
      enable = true;
      relay = {
        enable = true;
        role = "relay";
      };
      settings = {
        Nickname = config.torRelay.nickname;
        ContactInfo = "tor-relay@${config.networking.hostName}";
        ORPort = 9001;
        ControlPort = 9051;
        RelayBandwidthRate = config.torRelay.bandwidthRate;
        RelayBandwidthBurst = config.torRelay.bandwidthBurst;
        # Explicitly reject exit traffic
        ExitPolicy = ["reject *:*"];
      };
    };

    # Open firewall for Tor relay
    networking.firewall.allowedTCPPorts = [9001];
  };
}
