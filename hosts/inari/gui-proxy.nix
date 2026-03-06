{pkgs, ...}: {
  # GUI stack for proxy user, shared between OpenClaw and VNC.
  # Display :1 is local-only (no TCP listener) and exported over SSH tunnel via x11vnc.

  # Enable full GNOME desktop stack (inari-only via this host module).
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    x11vnc
    sxhkd
    rofi
    xorg-server
    xsetroot
    xdotool
    scrot
    gnome-session
    gnome-shell
    gnome-terminal
    nautilus
  ];

  systemd.services = {
    proxy-xvfb = {
      description = "Headless Xvfb display for proxy (:1)";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = ["HOME=/home/proxy"];
        ExecStart = "${pkgs.xorg-server}/bin/Xvfb :1 -screen 0 1920x1080x24 -nolisten tcp -ac";
      };
    };

    proxy-gnome = {
      description = "GNOME session on :1 for proxy";
      wantedBy = ["multi-user.target"];
      after = ["proxy-xvfb.service" "dbus.service"];
      requires = ["proxy-xvfb.service" "dbus.service"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = [
          "HOME=/home/proxy"
          "DISPLAY=:1"
          "XDG_SESSION_TYPE=x11"
          "XDG_CURRENT_DESKTOP=GNOME"
          "DESKTOP_SESSION=gnome"
        ];
        ExecStart = "${pkgs.dbus}/bin/dbus-run-session ${pkgs.gnome-session}/bin/gnome-session";
      };
    };

    proxy-x11vnc = {
      description = "x11vnc bridge for proxy display :1 (localhost only)";
      wantedBy = ["multi-user.target"];
      after = ["proxy-xvfb.service" "proxy-gnome.service"];
      requires = ["proxy-xvfb.service" "proxy-gnome.service"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = ["HOME=/home/proxy"];
        ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :1 -forever -shared -localhost -nopw";
      };
    };

    proxy-sxhkd = {
      description = "Hotkeys for proxy X session (:1)";
      wantedBy = ["multi-user.target"];
      after = ["proxy-xvfb.service" "proxy-gnome.service" "home-manager-proxy.service"];
      requires = ["proxy-xvfb.service" "proxy-gnome.service"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = [
          "HOME=/home/proxy"
          "DISPLAY=:1"
        ];
        ExecStart = "${pkgs.sxhkd}/bin/sxhkd -c /home/proxy/.config/sxhkd/sxhkdrc";
      };
    };
  };
}
