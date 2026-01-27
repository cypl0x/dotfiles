{pkgs, ...}: {
  users.users.wap = {
    isNormalUser = true;
    description = "Wolfhard Prell";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
    ];
  };
}
