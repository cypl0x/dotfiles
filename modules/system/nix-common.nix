_: {
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    builders-use-substitutes = true;
    substituters = [
      "https://cache.nixos.org"
      "https://cypl0x.cachix.org"
    ];
    trusted-public-keys = [
      "cypl0x.cachix.org-1:WMLmCcn2gTAZyWZDD6N2rghvpPn0rU9Gr5Cc2OTEdow="
    ];
    download-buffer-size = 524288000; # B instead of  32 MB
  };

  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];
}
