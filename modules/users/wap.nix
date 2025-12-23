{pkgs, ...}: {
  users.users.wap = {
    isNormalUser = true;
    description = "Work Account";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
    ];
  };
}
