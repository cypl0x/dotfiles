{
  lib,
  pkgs,
  ...
}: let
  pantheonX11Session =
    pkgs.runCommand "pantheon-x11-session" {
      passthru.providedSessions = ["pantheon-x11"];
    } ''
      mkdir -p "$out/share/xsessions"
      cat > "$out/share/xsessions/pantheon-x11.desktop" <<EOF
      [Desktop Entry]
      Name=Pantheon (X11)
      Comment=Pantheon on X11
      Exec=${pkgs.gnome-session}/bin/gnome-session --session=pantheon
      TryExec=${pkgs.pantheon.wingpanel}/bin/io.elementary.wingpanel
      Type=Application
      DesktopNames=Pantheon
      EOF
    '';
  pantheonWaylandSession =
    pkgs.runCommand "pantheon-wayland-session" {
      passthru.providedSessions = ["pantheon-wayland"];
    } ''
      mkdir -p "$out/share/wayland-sessions"
      cat > "$out/share/wayland-sessions/pantheon-wayland.desktop" <<EOF
      [Desktop Entry]
      Name=Pantheon
      Comment=Pantheon on Wayland
      Exec=${pkgs.gnome-session}/bin/gnome-session --session=pantheon-wayland
      TryExec=${pkgs.pantheon.wingpanel}/bin/io.elementary.wingpanel
      Type=Application
      DesktopNames=Pantheon
      EOF
    '';
in {
  # Pantheon desktop (Elementary OS) alongside Plasma and EXWM via SDDM.
  services = {
    desktopManager.pantheon.enable = true;
    pantheon.apps.enable = true;
    pantheon.contractor.enable = true;

    # Expose Pantheon session to SDDM (services.displayManager.*)
    displayManager.sessionPackages = lib.mkAfter [
      pkgs.pantheon.elementary-session-settings
      pantheonX11Session
      pantheonWaylandSession
    ];
  };

  services.displayManager.defaultSession = "pantheon-x11";
}
