{
  lib,
  pkgs,
  ...
}: let
  pantheonWaylandSession = pkgs.runCommand "pantheon-wayland-session" {} ''
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
      pantheonWaylandSession
    ];
  };

  # Don't let Pantheon become the default session.
  services.displayManager.defaultSession = lib.mkForce "plasma";
}
