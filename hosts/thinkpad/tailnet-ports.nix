{config, ...}: {
  # Ports reachable from the tailnet only, not from any LAN this host joins.
  #
  # Scoped to the tailscale0 interface rather than adding it to
  # networking.firewall.trustedInterfaces, which would expose every listening
  # port on the host to the whole tailnet.
  networking.firewall.interfaces."${config.services.tailscale.interfaceName}" = {
    allowedTCPPortRanges = [
      # KDE Connect. Peers on the tailnet must be paired by IP: discovery is a
      # UDP broadcast to 255.255.255.255:1716, which does not cross Tailscale.
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedTCPPorts = [
      1234
      8443
    ];
  };
}
