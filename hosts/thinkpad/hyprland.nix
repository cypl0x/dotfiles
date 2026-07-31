{pkgs, ...}: {
  # Hyprland Wayland compositor — the only desktop session on this host.
  # The greeter is ly (see modules/system/desktop.nix); it lists every
  # wayland-session desktop file, so "Hyprland" appears automatically.
  programs = {
    hyprland = {
      enable = true;
      withUWSM = true; # proper systemd session management (recommended)
      xwayland.enable = true;
    };

    # SSH passphrase prompt GUI. Previously provided implicitly by Plasma 6;
    # set explicitly now that plasma6 is gone. Qt-based, fits the Hyprland/KDE
    # polkit-agent stack below.
    ssh.askPassword = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

    # Required for dconf settings (color-scheme=prefer-dark) and for
    # xdg-desktop-portal-gtk to read them for Flatpak "system appearance".
    dconf.enable = true;
  };

  # Hyprland-specific XDG portal (for screenshot, screen-share, file-picker)
  # The generic xdg.portal.enable is already set in modules/system/desktop.nix.
  #
  # gtk MUST be in extraPortals (not only named in config.default): otherwise
  # xdg-desktop-portal logs "Requested gtk.portal is unrecognized", never
  # exposes org.freedesktop.portal.Settings, and Flatpak apps that follow
  # "system appearance" (Zen Browser, libadwaita, etc.) fall back to light.
  xdg.portal = {
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      # Preferred backends: hyprland for screencast/screenshot/shortcuts;
      # gtk for Settings (color-scheme), FileChooser, etc.
      hyprland = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.Settings" = ["gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      };
      common = {
        default = ["gtk"];
        "org.freedesktop.impl.portal.Settings" = ["gtk"];
      };
    };
  };

  # Polkit authentication agent — polkit-kde-agent (launched via exec-once in
  # hyprland.conf) handles privilege-elevation dialogs.
  security.polkit.enable = true;

  # gvfs — trash, MTP/sftp mounts, "eject", volume monitor for GUI file
  # managers (pcmanfm). Without this, Trash and removable media feel broken.
  services.gvfs.enable = true;
  # Disk mounts / USB (usually on already; pin it next to gvfs for clarity).
  services.udisks2.enable = true;

  # System packages for the full Hyprland ecosystem
  environment.systemPackages = with pkgs; [
    # Wallpaper / idle / lock
    hyprpaper
    hypridle
    hyprlock
    hyprsunset # blue-light filter (like redshift/f.lux)

    # Screenshot / screen recording
    grimblast # grim + slurp convenience wrapper
    grim # raw wayland screenshot
    slurp # region selector
    swappy # screenshot annotation tool
    wf-recorder # screen recording

    # Status bar
    waybar

    # Notifications — SwayNotificationCenter (KDE-Plasma-style control center
    # with history / DND / MPRIS widgets; config in home/hyprland/swaync/).
    # Drop swaync's D-Bus activation file so it is NOT auto-started as
    # org.freedesktop.Notifications under KDE/GNOME — there Plasma's native
    # notification server must own that name. Under Hyprland, exec-once launches
    # swaync explicitly (see hyprland.conf), so on-demand D-Bus activation is
    # unneeded. The shipped systemd user unit is left as-is: NixOS never enables
    # package-provided user units, so it stays inert.
    (swaynotificationcenter.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          rm -f "$out/share/dbus-1/services/org.erikreider.swaync.service"
        '';
    }))
    libnotify # notify-send

    # Application launcher (Wayland-native build required under Hyprland)
    rofi

    # Clipboard
    wl-clipboard # wl-copy, wl-paste
    cliphist # clipboard history daemon

    # Network / Bluetooth tray
    networkmanagerapplet # nm-applet
    blueman # blueman-applet

    # Audio control
    pavucontrol
    playerctl

    # Power / session menu
    wlogout

    # Wayland utilities
    wlr-randr # display management
    kanshi # display profile autoswitch
    brightnessctl # backlight
    swayosd # on-screen display for volume/brightness

    # System monitor — modern htop; waybar cpu/memory modules click through to it
    btop

    # eww — the nerdy conky-style desktop system overlay (home/hyprland/eww)
    eww

    # Image viewer
    swayimg

    # Polkit agent (Qt-based, fits alongside KDE)
    kdePackages.polkit-kde-agent-1

    # ── GUI file manager (secondary to yazi; drag-and-drop / USB / Trash) ──
    # Super+E stays kitty+yazi; Super+CTRL+E launches pcmanfm (see hyprland.conf).
    pcmanfm
    # Classic lightweight archive GUI (open / extract / create). PCManFM has no
    # thunar-style archive plugin; double-click + context "Open with" go here.
    xarchiver
    # CLI backends xarchiver / shell "Extract here" custom actions shell out to.
    zip
    unzip
    p7zip
    # "Create New → …" menu templates in pcmanfm / other LXDE-ish apps.
    lxmenu-data
  ];
}
