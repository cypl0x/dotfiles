_: {
  # Base Tailscale service. Host-specific routing flags live in host modules.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

# Required for subnet router - without this the firewall drops
# packets that don't match the expected reverse path
networking.firewall.checkReversePath = "loose";
}
