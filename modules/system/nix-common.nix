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
    # Hardlink byte-identical files in /nix/store after each build. Reclaims GB
    # over time (shared libs/docs duplicated across derivations) — the automatic
    # equivalent of a manual `nix-store --optimise`.
    auto-optimise-store = true;
  };

  # nh — the modern nix helper. Nicer build/switch UI with a package diff, and
  # `nh clean` for generation-based GC. clean.enable installs a weekly timer, so
  # do NOT also set nix.gc.automatic (two competing GC timers). Per-host flake
  # path is set in each host (thinkpad: hosts/thinkpad/default.nix); `nh clean`
  # needs no flake, so it works everywhere regardless.
  programs = {
    nh = {
      enable = true;
      clean = {
        enable = true;
        extraArgs = "--keep 5 --keep-since 7d";
      };
    };

    # nix-index — locate which package provides a binary/file
    # (`nix-locate bin/htop`) and back `comma`. Replaces the channel-based
    # command-not-found handler (needs programs.command-not-found, useless on a
    # pure-flake system). The prebuilt DB comes from the nix-index-database
    # module (wired per-host in flake.nix) — no local `nix-index` run needed.
    nix-index.enable = true;
    nix-index-database.comma.enable = true; # `, foo` runs foo without installing
    command-not-found.enable = false;
  };

  services.openssh.settings.AcceptEnv = ["LANG" "LC_*"];
}
