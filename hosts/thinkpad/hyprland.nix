{pkgs, ...}: {
  # Hyprland Wayland compositor — adds "Hyprland" to SDDM alongside
  # KDE Plasma, GNOME, Pantheon, and EXWM. SDDM remains the shared DM.
  programs.hyprland = {
    enable = true;
    withUWSM = true; # proper systemd session management (recommended)
    xwayland.enable = true;
  };

  # Hyprland-specific XDG portal (for screenshot, screen-share, file-picker)
  # The generic xdg.portal.enable is already set in modules/system/desktop.nix
  xdg.portal = {
    extraPortals = [pkgs.xdg-desktop-portal-hyprland];
    config.hyprland.default = ["hyprland" "gtk"];
  };

  # SSH passphrase prompt GUI. Previously provided implicitly by Plasma 6;
  # set explicitly now that plasma6 is gone. Qt-based, fits the Hyprland/KDE
  # polkit-agent stack below.
  programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

  # Polkit authentication agent — polkit-kde-agent (launched via exec-once in
  # hyprland.conf) handles privilege-elevation dialogs.
  security.polkit.enable = true;

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
  ];
}
