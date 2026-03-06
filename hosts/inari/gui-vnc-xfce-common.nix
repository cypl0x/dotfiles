{pkgs}:
{
  user,
  port,
  display ? 1,
}: let
  displayStr = toString display;
  vncPortStr = toString port;
  homeDir = "/home/${user}";
in {
  # Headless XFCE desktop over Xvfb + x11vnc (localhost only).
  environment.systemPackages = with pkgs; [
    # VNC and X11 tools
    x11vnc
    scrot
    xdotool
    xclip
    imagemagick
    wmctrl

    # XFCE core desktop
    xfce4-session
    xfwm4
    xfdesktop
    xfce4-panel
    xfce4-settings
    xfconf
    garcon
    libxfce4ui
    libxfce4util
    tumbler

    # File management
    thunar
    thunar-volman
    thunar-archive-plugin
    thunar-media-tags-plugin
    xfce4-volumed-pulse

    # Terminal, editor, viewers
    xfce4-appfinder
    xfce4-terminal
    mousepad
    ristretto
    evince
    xarchiver

    # Browser and media
    firefox
    vlc

    # Panel plugins
    xfce4-whiskermenu-plugin
    xfce4-battery-plugin
    xfce4-clipman-plugin
    xfce4-notifyd
    xfce4-screenshooter
    xfce4-taskmanager
    xfce4-pulseaudio-plugin
    xfce4-systemload-plugin
    xfce4-netload-plugin

    # System utilities
    gvfs
    udisks2
    polkit_gnome
    networkmanagerapplet
    pavucontrol
    lxappearance

    # Fonts
    noto-fonts
    noto-fonts-color-emoji
    liberation_ttf
  ];

  fonts.packages = with pkgs; [
    cascadia-code
  ];

  environment.etc = {
    "xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="xsettings" version="1.0">
        <property name="Net" type="empty">
          <property name="ThemeName" type="string" value="Adwaita"/>
          <property name="IconThemeName" type="string" value="Adwaita"/>
          <property name="CursorThemeName" type="string" value="Adwaita"/>
          <property name="FontName" type="string" value="Noto Sans 10"/>
          <property name="MonospaceFontName" type="string" value="Noto Sans Mono 10"/>
        </property>
        <property name="Xft" type="empty">
          <property name="Antialias" type="int" value="1"/>
          <property name="Hinting" type="int" value="1"/>
          <property name="HintStyle" type="string" value="hintslight"/>
          <property name="RGBA" type="string" value="rgb"/>
          <property name="DPI" type="int" value="96"/>
        </property>
      </channel>
    '';

    "xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="xfwm4" version="1.0">
        <property name="general" type="empty">
          <property name="theme" type="string" value="Default"/>
          <property name="button_layout" type="string" value="O|HMC"/>
          <property name="title_alignment" type="string" value="center"/>
          <property name="use_compositing" type="bool" value="true"/>
        </property>
      </channel>
    '';

    "xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="xfce4-panel" version="1.0">
        <property name="configver" type="int" value="2"/>
        <property name="panels" type="array">
          <value type="int" value="1"/>
          <value type="int" value="2"/>
          <property name="panel-1" type="empty">
            <property name="position" type="string" value="p=6;x=0;y=0"/>
            <property name="size" type="uint" value="28"/>
            <property name="length" type="uint" value="100"/>
            <property name="length-adjust" type="bool" value="true"/>
            <property name="mode" type="uint" value="0"/>
            <property name="plugin-ids" type="array">
              <value type="int" value="1"/>
              <value type="int" value="2"/>
              <value type="int" value="3"/>
              <value type="int" value="4"/>
              <value type="int" value="5"/>
              <value type="int" value="6"/>
              <value type="int" value="7"/>
              <value type="int" value="8"/>
              <value type="int" value="9"/>
            </property>
          </property>
          <property name="panel-2" type="empty">
            <property name="position" type="string" value="p=10;x=0;y=0"/>
            <property name="size" type="uint" value="36"/>
            <property name="length" type="uint" value="100"/>
            <property name="length-adjust" type="bool" value="true"/>
            <property name="mode" type="uint" value="0"/>
            <property name="plugin-ids" type="array">
              <value type="int" value="10"/>
            </property>
          </property>
        </property>

        <property name="plugins" type="empty">
          <property name="plugin-1" type="string" value="whiskermenu"/>
          <property name="plugin-2" type="string" value="separator"/>
          <property name="plugin-3" type="string" value="tasklist"/>
          <property name="plugin-4" type="string" value="separator"/>
          <property name="plugin-5" type="string" value="systray"/>
          <property name="plugin-6" type="string" value="pulseaudio"/>
          <property name="plugin-7" type="string" value="clipman"/>
          <property name="plugin-8" type="string" value="clock"/>
          <property name="plugin-9" type="string" value="actions"/>
          <property name="plugin-10" type="string" value="launcher"/>

          <property name="plugin-2" type="empty">
            <property name="expand" type="bool" value="false"/>
          </property>
          <property name="plugin-4" type="empty">
            <property name="expand" type="bool" value="true"/>
          </property>
          <property name="plugin-8" type="empty">
            <property name="digital-format" type="string" value="%a %b %d  %H:%M"/>
          </property>
          <property name="plugin-10" type="empty">
            <property name="items" type="array">
              <value type="string" value="launcher-10/xfce4-terminal.desktop"/>
              <value type="string" value="launcher-10/xfce4-file-manager.desktop"/>
              <value type="string" value="launcher-10/firefox.desktop"/>
              <value type="string" value="launcher-10/mousepad.desktop"/>
              <value type="string" value="launcher-10/xfce4-appfinder.desktop"/>
              <value type="string" value="launcher-10/ristretto.desktop"/>
              <value type="string" value="launcher-10/pavucontrol.desktop"/>
            </property>
          </property>
        </property>
      </channel>
    '';

    "xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="xfce4-desktop" version="1.0">
        <property name="backdrop" type="empty">
          <property name="screen0" type="empty">
            <property name="monitor0" type="empty">
              <property name="image-style" type="int" value="0"/>
              <property name="color-style" type="int" value="0"/>
              <property name="color1" type="string" value="#1d1f21"/>
            </property>
          </property>
        </property>
        <property name="desktop-icons" type="empty">
          <property name="style" type="int" value="2"/>
          <property name="icon-size" type="int" value="48"/>
        </property>
      </channel>
    '';

    "xdg/xfce4/terminal/terminalrc".text = ''
      [Configuration]
      FontName=Cascadia Code 11
      UseSystemFont=FALSE
    '';

    "xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="xfce4-keyboard-shortcuts" version="1.0">
        <property name="commands" type="empty">
          <property name="custom" type="empty">
            <property name="<Alt>space" type="string" value="xfce4-appfinder --collapsed"/>
            <property name="<Alt>r" type="string" value="rofi -show run"/>
          </property>
        </property>
      </channel>
    '';

    "xdg/xfce4/panel/launcher-10/xfce4-terminal.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Terminal
      Exec=xfce4-terminal
      Icon=utilities-terminal
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/xfce4-file-manager.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Files
      Exec=thunar
      Icon=system-file-manager
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/firefox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Firefox
      Exec=firefox
      Icon=firefox
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/mousepad.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Mousepad
      Exec=mousepad
      Icon=accessories-text-editor
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/xfce4-appfinder.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=App Finder
      Exec=xfce4-appfinder
      Icon=system-search
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/ristretto.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Ristretto
      Exec=ristretto
      Icon=ristretto
      Terminal=false
      StartupNotify=true
    '';

    "xdg/xfce4/panel/launcher-10/pavucontrol.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Sound
      Exec=pavucontrol
      Icon=multimedia-volume-control
      Terminal=false
      StartupNotify=true
    '';
  };

  systemd.services = {
    "${user}-xvfb" = {
      description = "Headless Xvfb display for ${user} (:${displayStr})";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        User = user;
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = ["HOME=${homeDir}"];
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'rm -f /tmp/.X${displayStr}-lock /tmp/.X11-unix/X${displayStr}; true'";
        ExecStart = "${pkgs.xorg-server}/bin/Xvfb :${displayStr} -screen 0 1920x1080x24 -nolisten tcp -ac";
      };
    };

    "${user}-xfce" = {
      description = "XFCE session on :${displayStr} for ${user}";
      wantedBy = ["multi-user.target"];
      after = ["${user}-xvfb.service"];
      requires = ["${user}-xvfb.service"];
      serviceConfig = {
        User = user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "3s";
        Environment = [
          "HOME=${homeDir}"
          "DISPLAY=:${displayStr}"
          "XDG_SESSION_TYPE=x11"
          "XDG_CURRENT_DESKTOP=XFCE"
          "DESKTOP_SESSION=xfce"
          "XDG_DATA_DIRS=/run/current-system/sw/share"
          "XDG_CONFIG_DIRS=${pkgs.xfce4-session}/etc:${pkgs.xfconf}/etc:/run/current-system/sw/etc/xdg"
          "PATH=${pkgs.dbus}/bin:${pkgs.xfce4-session}/bin:${pkgs.xfwm4}/bin:${pkgs.xfdesktop}/bin:/run/current-system/sw/bin"
        ];
        ExecStart = "${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon ${pkgs.xfce4-session}/bin/xfce4-session";
      };
    };

    "${user}-x11vnc" = {
      description = "x11vnc bridge for ${user} display :${displayStr} (localhost only, port ${vncPortStr})";
      wantedBy = ["multi-user.target"];
      after = ["${user}-xvfb.service" "${user}-xfce.service"];
      requires = ["${user}-xvfb.service"];
      serviceConfig = {
        User = user;
        Group = "users";
        Restart = "always";
        RestartSec = "2s";
        Environment = ["HOME=${homeDir}"];
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :${displayStr} -forever -shared -localhost -nopw -rfbport ${vncPortStr}";
      };
    };
  };
}
