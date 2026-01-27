_: {
  # SSH with ShellFish Support
  services.openssh = {
    enable = true;
    settings = {
      # Allow LC_TERMINAL for ShellFish
      AcceptEnv = ["LANG" "LC_*"];

      # Security Hardening
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Basic firewall configuration
  # Individual services will open their required ports
  networking.firewall = {
    enable = true;
    # Ports will be opened by service modules:
    # - nginx.nix: 80, 443
    # - tor.nix: 9001
  };
}
