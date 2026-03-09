_: {
  # Base Tailscale service. Host-specific routing flags live in host modules.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
