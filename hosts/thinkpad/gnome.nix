{
  lib,
  pkgs,
  ...
}: {
  # GNOME Desktop Environment
  # Adds "GNOME" (Wayland, recommended) and "GNOME on Xorg" sessions to the
  # SDDM login screen alongside KDE Plasma 6, Pantheon, and EXWM.
  # GDM is intentionally NOT enabled — SDDM remains the shared display manager.
  # GNOME 45+ defaults to the Wayland session; Xorg remains available via
  # "GNOME on Xorg". XWayland handles X11 apps transparently in both sessions.

  programs = {
    # programs.ssh.askPassword conflict: plasma6 sets ksshaskpass, GNOME seahorse sets its own.
    # Keep KDE's ksshaskpass — it works fine across all sessions on this multi-DE host.
    ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

    evolution = {
      enable = true; # also auto-enables services.gnome.evolution-data-server
      plugins = [
        pkgs.evolution-ews # Microsoft Exchange / Office 365 (EWS) connector
      ];
    };

    # Sensible system-wide dconf defaults for Evolution.
    # Users can override any of these via dconf-editor or gsettings.
    dconf.profiles.user.databases = [
      {
        settings = {
          # ── Mail ──────────────────────────────────────────────────────────
          "org/gnome/evolution/mail" = {
            # Vertical split (reading pane on the right) — optimal for widescreen
            layout = lib.gvariant.mkInt32 1;
            # Show message preview pane by default
            show-preview = true;
            # Mark messages as read after 1.5 s of preview
            mark-seen-timeout = lib.gvariant.mkInt32 1500;
            # Newest message in a thread appears at the top
            thread-latest-first = true;
            # HTML composer — renders rich content and inline images
            composer-mode = "html";
            # Standard quoted reply style
            reply-style = "quoted";
            # Forward as inline body text rather than attachment
            forward-style = "inline";
          };

          # ── Calendar ──────────────────────────────────────────────────────
          "org/gnome/evolution/calendar" = {
            # Week starts on Monday (ISO 8601)
            week-start-day = lib.gvariant.mkInt32 1;
            # Show ISO week numbers in the month view
            show-week-numbers = true;
            # Working hours: 08:00 – 17:00 (minutes from midnight)
            working-day-start = lib.gvariant.mkInt32 480;
            working-day-end = lib.gvariant.mkInt32 1020;
            # Default event reminder: 15 minutes before
            default-reminder-interval = lib.gvariant.mkInt32 15;
            default-reminder-units = "minutes";
          };
        };
      }
    ];
  };

  services = {
    desktopManager.gnome.enable = true;

    gnome = {
      # Allow installing extensions directly from extensions.gnome.org via browser
      gnome-browser-connector.enable = true;
    };

    # fwupd — firmware update daemon; surfaces device updates in GNOME Software
    fwupd.enable = true;
  };

  environment = {
    # Strip heavyweight / redundant packages from the default GNOME set.
    gnome.excludePackages = with pkgs; [
      gnome-tour # First-run tutorial overlay — not needed
      gnome-user-docs # Large offline help documentation
      epiphany # GNOME Web browser — Firefox / Vivaldi already installed
    ];

    systemPackages = with pkgs; [
      # ── Customisation & tweaking ──────────────────────────────────────────
      gnome-tweaks # Font hinting, title-bar buttons, desktop icons, extensions UI
      dconf-editor # Low-level dconf / gsettings browser and editor
      gnome-extension-manager # Install, enable, and configure shell extensions

      # ── Shell extensions (installed but disabled by default) ──────────────
      # Enable them in Extension Manager or GNOME Tweaks → Extensions.
      gnomeExtensions.dash-to-dock # Persistent dock — Ubuntu-style launcher
      gnomeExtensions.appindicator # Legacy system-tray / AppIndicator support
      gnomeExtensions.caffeine # Inhibit screen-lock and auto-suspend
      gnomeExtensions.clipboard-indicator # Clipboard history with search
      gnomeExtensions.blur-my-shell # Frosted-glass blur on overview and panel
      gnomeExtensions.just-perfection # Fine-tune shell visibility and layout
      gnomeExtensions.gsconnect # KDE Connect integration: phone ↔ desktop sync

      # ── Additional GTK4 GNOME apps ────────────────────────────────────────
      # These complement the large default app set included automatically.
      celluloid # GTK4 mpv front-end — polished video player
      shortwave # Internet radio client (GTK4, follows GNOME HIG)
      newsflash # RSS / Atom feed reader (GTK4)
      gnome-firmware # Firmware update GUI wrapping fwupd
      bottles # Wine prefix manager — run Windows applications
      resources # Modern system resource and process monitor (GTK4)

      # ── Fonts for broad Unicode and emoji coverage ────────────────────────
      noto-fonts # Wide Unicode script coverage
      noto-fonts-color-emoji # Colour emoji (system-wide, all apps)
      noto-fonts-cjk-sans # CJK glyphs: Chinese, Japanese, Korean
    ];
  };
}
