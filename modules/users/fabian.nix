{
  lib,
  pkgs,
  ...
}: {
  users.users.fabian = {
    isNormalUser = true;
    description = "Fabian";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
      ../ssh-keys/fabian.pub
    ];
  };

  # Allow password authentication for fabian only.
  # NixOS strips pam_unix from sshd's PAM stack when the global
  # services.openssh.settings.PasswordAuthentication is false, so the
  # Match block alone isn't enough — sshd would prompt and PAM would
  # then deny via pam_deny. Force pam_unix back in.
  services.openssh.extraConfig = ''
    Match User fabian
      PasswordAuthentication yes
  '';
  security.pam.services.sshd.unixAuth = lib.mkForce true;
}
