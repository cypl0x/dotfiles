{ pkgs, ... }: {
  users.users.cypl0x = {
    isNormalUser = true;
    description = "Wolfhard Prell";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../ssh-keys/homelab.pub
    ];
  };
}
