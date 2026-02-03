{
  pkgs,
  datapass,
  ...
}: {
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

    # Password manager
    datapass.packages.${pkgs.system}.default

    # X11 tools for Emacs and window management
    xdotool
    # kdotool  # Disabled: fails to compile in nixpkgs unstable (Rust compatibility issue)
    xorg.xprop
    xorg.xwininfo
    dotool

    # Calculator
    bc

    # GitHub CLI tool
    gh

    # node(js) npm, npx, etc.
    nodejs_24
  ];
}
