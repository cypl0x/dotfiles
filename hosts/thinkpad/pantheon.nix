{lib, ...}: {
  # Pantheon desktop (Elementary OS) alongside Plasma and EXWM via SDDM.
  services.xserver.desktopManager.pantheon.enable = true;
  services.pantheon.apps.enable = true;
  services.pantheon.contractor.enable = true;

  # Keep SDDM as the display manager and avoid LightDM conflicts.
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;
  services.xserver.displayManager.lightdm.greeters.pantheon.enable = lib.mkForce false;

  # Don't let Pantheon become the default session.
  services.xserver.displayManager.defaultSession = lib.mkDefault "plasma";
}
