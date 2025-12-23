{ pkgs, ... }: {
  users.users.wap = {
    isNormalUser = true;
    description = "Work Account";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
    # Add key if needed, for now reusing the known one or leaving empty if not available
  };
}
