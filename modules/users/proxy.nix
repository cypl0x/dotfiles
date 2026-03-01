{pkgs, ...}: {
  users.users.proxy = {
    isNormalUser = true;
    description = "Proxy User";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
  };
}
