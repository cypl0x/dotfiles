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
  # and ly's PAM stack substacks/includes `login`. Store secrets in the login
  # keyring — a separate named keyring is not covered by this and prompts on
  # every session.
  services.gnome.gnome-keyring.enable = true;

  # Do not reach for security.pam.services.ly.enableGnomeKeyring — nixpkgs' ly
  # module sets useDefaultRules = false, so that option generates no rules and
  # silently does nothing. ly inherits pam_gnome_keyring through its
  # `substack login` / `include login` rules instead.
  #
  # The other half is on disk, not in Nix: ~/.local/share/keyrings/default must
  # name `login`, and login.keyring must exist with the login password as its
  # passphrase. pam_gnome_keyring unlocks the keyring named `login` and nothing
  # else. If the pointer names a keyring the daemon does not load, the default
  # collection resolves to a D-Bus path that does not exist, and clients which
  # create items there fail — Proton Mail Bridge aborts with "could not create
  # keychain: no keychain" and then reports finding no password manager.
  # gnome-keyring 50 no longer loads the old plaintext `[keyring]` ini format,
  # which is one way to end up with such a dangling pointer.

  # Keyring GUI, for when the login and keyring passwords drift apart and the
  # login keyring has to be reset. gcr provides the unlock prompter itself.
  programs.seahorse.enable = true;
}
