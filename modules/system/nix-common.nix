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

  # nh — the modern nix helper. Nicer build/switch UI with a package diff, and
  # `nh clean` for generation-based GC. clean.enable installs a weekly timer, so
  # do NOT also set nix.gc.automatic (two competing GC timers). Per-host flake
  # path is set in each host (thinkpad: hosts/thinkpad/default.nix); `nh clean`
  # needs no flake, so it works everywhere regardless.
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };

  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];
}
