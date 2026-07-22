{pkgs, ...}: let
  # Doom Vibrant (Henrik Lissner) palette mapped onto the libadwaita named
  # colours. GTK4/libadwaita apps ignore the classic theme engine, so the only
  # reliable way to recolour them is to redefine these @define-color tokens.
  doomVibrantCss = ''
    @define-color accent_color        #51afef;
    @define-color accent_bg_color     #51afef;
    @define-color accent_fg_color     #1c1f24;

    @define-color window_bg_color     #1c1f24;
    @define-color window_fg_color     #bbc2cf;
    @define-color view_bg_color       #21242b;
    @define-color view_fg_color       #bbc2cf;
    @define-color headerbar_bg_color  #242730;
    @define-color headerbar_fg_color  #bbc2cf;
    @define-color card_bg_color       #242730;
    @define-color card_fg_color       #bbc2cf;
    @define-color popover_bg_color    #242730;
    @define-color popover_fg_color    #bbc2cf;
    @define-color sidebar_bg_color    #21242b;

    @define-color destructive_color   #ff665c;
    @define-color success_color       #7bc275;
    @define-color warning_color       #fcce7b;
    @define-color error_color         #ff665c;
  '';
in {
  # Doom Vibrant GTK theme (thinkpad desktop). adw-gtk3-dark is the dark base
  # for GTK3 apps; the gtk.css accent overrides carry the Doom Vibrant palette
  # into GTK4/libadwaita apps that otherwise ignore the theme.
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    # Don't let the theme module install adw-gtk3's own gtk-4.0/gtk.css — we
    # ship our own Doom Vibrant accent css there instead (would otherwise be a
    # "Conflicting managed target files" error). libadwaita reads our css.
    gtk4.theme = null;
  };

  home.file = {
    ".config/gtk-4.0/gtk.css".text = doomVibrantCss;
    ".config/gtk-3.0/gtk.css".text = doomVibrantCss;
  };
}
