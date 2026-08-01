_: {
  # Secret Service (org.freedesktop.secrets) for the Hyprland session.
  #
  # Neither Hyprland nor ly ships a credential store, so libsecret consumers
  # (Field Monitor, AnyType, Chromium/Electron) had nothing to talk to and
  # aborted at startup. Flatpaks are hit twice: sandboxed apps without an
  # explicit --talk-name=org.freedesktop.secrets go through the Secret portal
  # instead, and gtk.portal/hyprland.portal implement no Secret backend.
  #
  # gnome-keyring covers both paths from a single switch — its module adds the
  # daemon to services.dbus.packages (D-Bus activation via the shipped
  # org.freedesktop.secrets.service; no systemd user unit involved) and to
  # xdg.portal.extraPortals (org.freedesktop.impl.portal.Secret). It runs as a
  # plain daemon, so no GNOME session is pulled in.
  #
  # Unlocking: the module sets security.pam.services.login.enableGnomeKeyring,
  # and ly's PAM stack substacks/includes `login`, so the login keyring is
  # unlocked with the ly password without any extra PAM rules. Store secrets in
  # the login keyring — a separate named keyring is not covered by this and
  # prompts on every session.
  services.gnome.gnome-keyring.enable = true;

  # Keyring GUI, for when the login and keyring passwords drift apart and the
  # login keyring has to be reset. gcr provides the unlock prompter itself.
  programs.seahorse.enable = true;
}
