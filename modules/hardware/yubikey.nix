{pkgs, ...}: {
  # YubiKey support for use *inside applications* (Firefox WebAuthn/FIDO2,
  # Proton VPN, PIV/CCID smartcard) — NOT as a laptop login/PAM factor.
  #
  # This is session-agnostic: the udev rules and pcscd socket work the same
  # under KDE Plasma, GNOME, and Hyprland, so behaviour matches KDE "out of
  # the box".

  # Smartcard daemon — needed for the PIV / CCID applet (resident credentials,
  # the "disk"/smartcard side of the YubiKey 5C).
  services.pcscd.enable = true;

  # udev rules:
  #   libfido2                → 70-u2f rules: grants the logged-in user hidraw
  #                             access so browser/app WebAuthn + U2F works.
  #   yubikey-personalization → OTP / challenge-response device access.
  services.udev.packages = [
    pkgs.libfido2
    pkgs.yubikey-personalization
  ];

  # libfido2's 70-u2f.rules also set GROUP="plugdev", a Debian group NixOS
  # doesn't have: udev logged "Failed to resolve group 'plugdev'" ~1,700 times
  # per boot.  Access comes from uaccess either way; the group only makes the
  # rules apply as written.  Nobody needs to be in it.
  users.groups.plugdev = {};

  # CLI / GUI management tools.
  environment.systemPackages = with pkgs; [
    yubikey-manager # `ykman` — configure FIDO2/PIV/OATH applets
    yubico-piv-tool # PIV certificate management
    libfido2 # `fido2-token` diagnostics
  ];
}
