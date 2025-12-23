{pkgs, ...}: {
  # Root user configuration
  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
    ];
  };

  # Sudo configuration
  security.sudo.wheelNeedsPassword = true;
}
