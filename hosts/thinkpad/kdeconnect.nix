_: {
  # KDE Connect. The NixOS module opens TCP+UDP 1714-1764, which the base
  # firewall in modules/system/security.nix otherwise drops.
  #
  # The default package is kdePackages.kdeconnect-kde (Qt 6); the top-level
  # kdeconnect-kde alias and libsForQt5.kdeconnect-kde were removed with the
  # Plasma 5 / KDE Gear 5 EOL, so no `package` override is wanted here.
  programs.kdeconnect.enable = true;
}
