{pkgs, ...}: {
  environment.systemPackages = with pkgs; [mosh];

  # Mosh uses UDP ports 60000-61000 by default.
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 60000;
      to = 61000;
    }
  ];
}
