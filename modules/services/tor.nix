_: {
  # Tor Relay (non-exit)
  services.tor = {
    enable = true;
    relay = {
      enable = true;
      role = "relay";
    };
    settings = {
      Nickname = "cypl0x";
      ContactInfo = "tor-relay@homelab";
      ORPort = 9001;
      ControlPort = 9051;
      # Bandwidth limits (adjust as needed)
      RelayBandwidthRate = "55 KBytes";
      RelayBandwidthBurst = "110 KBytes";
      # Explicitly reject exit traffic
      ExitPolicy = ["reject *:*"];
    };
  };

  # Open firewall for Tor relay
  networking.firewall.allowedTCPPorts = [9001];
}
