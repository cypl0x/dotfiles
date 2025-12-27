{pkgs, ...}: {
  # ThinkPad-specific packages not included in base system

  environment.systemPackages = with pkgs; [
    # Privacy and VPN
    protonvpn-gui

    # Email bridge tools
    hydroxide

    # LaTeX full suite
    texlive.combined.scheme-full

    # Partitioning tools
    parted
    gparted

    # Network analysis
    wireshark

    # iOS device management (additional tools beyond usbmuxd)
    libimobiledevice
    ifuse

    # Rust development
    rustup

    # Process viewer
    procs
  ];
}
