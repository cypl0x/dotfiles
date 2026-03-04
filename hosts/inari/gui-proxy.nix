{pkgs, ...}: {
  # GUI stack for proxy user, shared between OpenClaw and VNC.
  # Display :1 is local-only (no TCP listener) and exported over SSH tunnel via x11vnc.

  environment.systemPackages = with pkgs; [
    x11vnc
    openbox
    xorg-server
    xorg.xsetroot
    xdotool
    scrot
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

    proxy-openbox = {
      description = "Openbox session on :1 for proxy";
      wantedBy = ["multi-user.target"];
      after = ["proxy-xvfb.service"];
      requires = ["proxy-xvfb.service"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = [
          "HOME=/home/proxy"
          "DISPLAY=:1"
        ];
        ExecStart = "${pkgs.openbox}/bin/openbox";
      };
    };

    proxy-x11vnc = {
      description = "x11vnc bridge for proxy display :1 (localhost only)";
      wantedBy = ["multi-user.target"];
      after = ["proxy-xvfb.service" "proxy-openbox.service"];
      requires = ["proxy-xvfb.service" "proxy-openbox.service"];
      serviceConfig = {
        User = "proxy";
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = ["HOME=/home/proxy"];
        ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :1 -forever -shared -localhost -nopw";
      };
    };
  };
}
