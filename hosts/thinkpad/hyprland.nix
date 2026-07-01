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

  # Polkit authentication agent (KDE's ksshaskpass already handles SSH;
  # kde-polkit-agent handles elevation dialogs in all sessions on this host).
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

    # Notifications
    # Drop mako's D-Bus activation file so it is NOT auto-started as
    # org.freedesktop.Notifications under KDE/GNOME — there Plasma's native
    # notification server must own that name (mako winning the activation race
    # made popups render in mako's top-right style instead of Plasma-native).
    # Under Hyprland, exec-once launches mako explicitly (see hyprland.conf),
    # so on-demand D-Bus activation is unneeded. The shipped systemd user unit
    # is left as-is: NixOS never enables package-provided user units, so it
    # stays inert and is not an activation vector.
    (mako.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          rm -f "$out/share/dbus-1/services/fr.emersion.mako.service"
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

    # Image viewer
    swayimg

    # Polkit agent (Qt-based, fits alongside KDE)
    kdePackages.polkit-kde-agent-1
  ];
}
