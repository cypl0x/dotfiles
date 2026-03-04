{pkgs, ...}: {
  imports = [./common.nix];

  home = {
    username = "proxy";

    sessionVariables = {
      OLLAMA_API_KEY = "ollama-local";
      DISPLAY = ":1";
    };

    packages = [
      # GUI tools used by OpenClaw in the shared Xvfb/VNC session
      pkgs.firefox
      pkgs.scrot
    ];
  };

  home.file.".config/sxhkd/sxhkdrc".text = ''
    # Launch app launcher in VNC/X session
    super + space
      rofi -show drun

    alt + space
      rofi -show drun
  '';

  systemd.user.services.openclaw-gateway = {
    Service.Environment = "OLLAMA_API_KEY=ollama-local";
  };

  programs.openclaw = {
    enable = true;
    documents = ./proxy-documents;
    config = {
      gateway = {
        mode = "local";
        auth.mode = "none";
      };
      channels.telegram = {
        tokenFile = "/home/proxy/.secrets/telegram.token";
        allowFrom = [7295501323];
      };
      agents.defaults.model.primary = "ollama/qwen2.5-coder:3b";
    };
  };
}
