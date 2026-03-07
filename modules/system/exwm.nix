{pkgs, ...}: let
  # Install eat's terminfo entries system-wide so that programs running inside
  # an eat terminal (including over SSH) can resolve the eat-* TERM types.
  # eat.el auto-sets eat-term-terminfo-directory to this same store path at
  # load time, but having entries in the system terminfo DB is needed for
  # processes that inherit TERM=eat-* without the eat-managed TERMINFO var.
  eatTerminfo = pkgs.runCommand "eat-terminfo" {} ''
    mkdir -p "$out/share/terminfo"
    cp -r "${pkgs.emacsPackages.eat}"/share/emacs/site-lisp/elpa/eat-*/terminfo/. \
      "$out/share/terminfo/"
  '';

  # Startup script sourcing the user profile so the home-manager Emacs
  # wrapper (with vterm, etc.) is found in PATH rather than the bare system Emacs.
  exwmStartScript = pkgs.writeShellScript "start-exwm" ''
    # Source system and user profiles so home-manager packages are in PATH
    . /etc/profile
    [ -f "$HOME/.profile" ] && . "$HOME/.profile"

    # Required for Java apps (AWT) and Firefox touch input
    export _JAVA_AWT_WM_NONREPARENTING=1
    export MOZ_USE_XINPUT2=1

    # Ensure XDG_RUNTIME_DIR is set — SDDM xsessions don't inherit it from PAM
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    exec emacs
  '';

  # SDDM xsession desktop entry — shows up alongside "Plasma" at login.
  # services.displayManager.sessionPackages requires passthru.providedSessions.
  exwmSession =
    pkgs.runCommand "exwm-session" {
      passthru.providedSessions = ["exwm"];
    } ''
      mkdir -p "$out/share/xsessions"
      cat > "$out/share/xsessions/exwm.desktop" <<EOF
      [Desktop Entry]
      Name=EXWM
      Comment=Emacs X Window Manager
      Exec=${exwmStartScript}
      Type=XSession
      DesktopNames=EXWM
      EOF
    '';
in {
  # Register EXWM as a selectable session in SDDM (Plasma remains available)
  services.displayManager.sessionPackages = [exwmSession];

  # Companion packages for a comfortable EXWM environment
  environment.systemPackages =
    [eatTerminfo]
    ++ (with pkgs; [
      picom # Compositor: transparency, shadows, vsync
      feh # Wallpaper setter
      brightnessctl # Screen brightness keys
      playerctl # Media keys (play/pause/next/prev)
      flameshot # Screenshot tool
      networkmanagerapplet # Network Manager tray icon
      pasystray # PipeWire/PulseAudio volume tray
      xss-lock # Lock screen on suspend / idle
      xsecurelock # Screen locker called by xss-lock
      cbatticon
      blueman
      udiskie
      redshift
      flameshot
    ]);
}
