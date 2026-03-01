{pkgs, ...}: let
  # Startup script sourcing the user profile so the home-manager Emacs
  # wrapper (with vterm, etc.) is found in PATH rather than the bare system Emacs.
  exwmStartScript = pkgs.writeShellScript "start-exwm" ''
    # Source system and user profiles so home-manager packages are in PATH
    . /etc/profile
    [ -f "$HOME/.profile" ] && . "$HOME/.profile"

    # Required for Java apps (AWT) and Firefox touch input
    export _JAVA_AWT_WM_NONREPARENTING=1
    export MOZ_USE_XINPUT2=1

    exec emacs
  '';

  # SDDM xsession desktop entry — shows up alongside "Plasma" at login
  exwmSession = pkgs.writeTextDir "share/xsessions/exwm.desktop" ''
    [Desktop Entry]
    Name=EXWM
    Comment=Emacs X Window Manager
    Exec=${exwmStartScript}
    Type=Application
    DesktopNames=EXWM
  '';
in {
  # Register EXWM as a selectable session in SDDM (Plasma remains available)
  services.displayManager.sessionPackages = [exwmSession];

  # Companion packages for a comfortable EXWM environment
  environment.systemPackages = with pkgs; [
    picom # Compositor: transparency, shadows, vsync
    dunst # Notification daemon
    feh # Wallpaper setter
    brightnessctl # Screen brightness keys
    playerctl # Media keys (play/pause/next/prev)
    flameshot # Screenshot tool
    networkmanagerapplet # Network Manager tray icon
    pasystray # PipeWire/PulseAudio volume tray
    xss-lock # Lock screen on suspend / idle
    i3lock # Screen locker called by xss-lock
  ];
}
