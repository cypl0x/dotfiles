{pkgs, ...}: {
  users.users.proxy = {
    isNormalUser = true;
    description = "Proxy User";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
  };

  systemd.services.openclaw = {
    description = "OpenClaw Gateway";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      User = "proxy";
      WorkingDirectory = "/home/proxy";
      ExecStart = "/home/proxy/.npm-global/bin/openclaw gateway";
      Restart = "always";
      RestartSec = "10s";
      Environment = [
        "HOME=/home/proxy"
        "PATH=/home/proxy/.npm-global/bin:/run/current-system/sw/bin"
      ];
    };
  };
}
