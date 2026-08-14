{pkgs, ...}: {
  users.users.raphael = {
    isNormalUser = true;
    description = "Raphael";
    extraGroups = ["networkmanager" "wheel" "podman"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
    ];
  };

  # Allow password authentication for raphael too. The matching
  # security.pam.services.sshd.unixAuth = mkForce true lives in fabian.nix
  # (see the comment there); it is global to sshd, so it must not be repeated
  # here — two mkForce definitions of the same option conflict.
  services.openssh.extraConfig = ''
    Match User raphael
      PasswordAuthentication yes
  '';
}
