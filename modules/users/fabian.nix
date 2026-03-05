{pkgs, ...}: {
  users.users.fabian = {
    isNormalUser = true;
    description = "Fabian";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
      ../ssh-keys/fabian.pub
    ];
  };

  # Allow password authentication for fabian only
  services.openssh.extraConfig = ''
    Match User fabian
      PasswordAuthentication yes
  '';
}
