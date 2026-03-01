{
  pkgs,
  datapass,
  ...
}: {
  # ThinkPad-specific packages not included in base system

  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["wap" "cypl0x"];
  };

  environment.systemPackages = with pkgs; [
    # Browsers
    vivaldi

    gnome-boxes

    # Privacy and VPN
    protonvpn-gui

    # Email
    fastmail-desktop
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
    datapass.packages.${pkgs.stdenv.hostPlatform.system}.default

    # X11 tools for Emacs and window management
    xdotool
    # kdotool  # Disabled: fails to compile in nixpkgs unstable (Rust compatibility issue)
    xprop
    xwininfo
    dotool

    # Webcam tools
    v4l-utils

    # Calculator
    bc

    # GitHub CLI tool
    gh

    # Git Tui
    tig

    # Git GUI
    #gitbutler # turbo-unwrapped broken

    # node(js) npm, npx, etc.
    nodejs_24

    # Telegram Desktop Client
    telegram-desktop

    # Bitwarden Password Manager
    bitwarden-desktop
    bitwarden-cli
    # _1password-gui
    # _1password-cli

    # Notion
    notion-app-enhanced
    anytype
    appflowy
    planify
    rambox
    ferdium
    franz
    todoist-electron
    obsidian
    logseq

    # opera
    chromium
    google-chrome

    # AI
    gemini-cli

    # vim mode for Firefox
    tridactyl-native

    # In order to get AnyType login key visible
    # https://github.com/anyproto/anytype-ts/issues/729#issuecomment-2799841750
    # gnome-keyring
    # gcr

    cmake

    # mu # mue doesn't contain mu4e
    # Fix it with:
    # (pkgs.mu.override { emacs = pkgs.emacs; })
    mu
    mu.mu4e
    isync
    offlineimap

    # application launcher
    rofi
    rofimoji
    rofi-vpn
    rofi-top
    rofi-calc
    rofi-file-browser
    rofi-systemd
    rofi-bluetooth
    rofi-power-menu
    rofi-pulse-select
    rofi-network-manager
    rofi-screenshot

    wezterm
    ghostty
  ];
}
