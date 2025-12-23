{pkgs, ...}: {
  # Monitoring and observability tools

  environment.systemPackages = with pkgs; [
    # Tor monitoring
    nyx # Interactive Tor relay monitor (formerly arm)

    # Network monitoring
    vnstat # Network traffic statistics
    bandwhich # Terminal bandwidth utilization tool
    nethogs # Per-process network usage
    iftop # Network bandwidth monitoring

    # System monitoring
    htop # Interactive process viewer
    btop # Resource monitor (modern htop alternative)

    # Log analysis
    goaccess # Real-time web log analyzer
    lnav # Advanced log file viewer
    multitail # Monitor multiple log files

    # Metrics and observability
    prometheus-node-exporter # System metrics exporter
  ];

  # Enable vnstat service for persistent network statistics
  services.vnstat.enable = true;

  # Enable Prometheus Node Exporter for metrics
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
    port = 9100;
    # Only listen on localhost for security
    listenAddress = "127.0.0.1";
  };
}
