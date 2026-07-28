{
  config,
  pkgs,
  lib,
  ...
}: let
  # Doom Vibrant again, this time as kmscon's decimal-RGB triples. Same hues as
  # console.colors in modules/system/console.nix.
  kmsconPalette = {
    palette = "custom";
    palette-background = "36, 39, 48"; #  bg      #242730
    palette-foreground = "187, 194, 207"; #  fg      #bbc2cf
    palette-black = "28, 31, 36"; #  #1c1f24
    palette-red = "255, 102, 92"; #  #ff665c
    palette-green = "123, 194, 117"; #  #7bc275
    palette-yellow = "252, 206, 123"; #  #fcce7b
    palette-blue = "81, 175, 239"; #  #51afef
    palette-magenta = "197, 123, 219"; #  #c57bdb
    palette-cyan = "92, 239, 255"; #  #5cefff
    palette-light-grey = "187, 194, 207"; #  #bbc2cf
    palette-dark-grey = "91, 98, 104"; #  #5b6268
    palette-light-red = "255, 123, 112"; #  #ff7b70
    palette-light-green = "146, 207, 140"; #  #92cf8c
    palette-light-yellow = "255, 217, 143"; #  #ffd98f
    palette-light-blue = "108, 192, 255"; #  #6cc0ff
    palette-light-magenta = "212, 148, 232"; #  #d494e8
    palette-light-cyan = "125, 245, 255"; #  #7df5ff
    palette-white = "223, 223, 223"; #  #dfdfdf
  };

  kmsconSettings =
    kmsconPalette
    // {
      # pango + freetype, so this is a real outline font at any size — the
      # thing the kernel VT structurally cannot do.
      font-engine = "pango";
      font-name = "Maple Mono NF";
      font-size = 20; # ~174x45 cells at 1920x1080, close to spleen-12x24

      # kmscon has its own scrollback, unlike the kernel VT (which lost it
      # entirely in Linux 5.9). Shift+Up/Down and Shift+PgUp/PgDn scroll it.
      sb-size = 20000;

      # kmscon's own TERM default is "kmscon", whose terminfo entry is not in
      # ncurses. Advertising xterm-256color is what the NixOS module does too.
      term = "xterm-256color";

      # Two GPUs are present. "primary" pins kmscon to the boot VGA device
      # (the Intel iGPU, which owns every connector); "all" would have it also
      # probe the Quadro, which drives no displays here.
      gpus = "primary";

      hwaccel = true;

      # Match the VT and Hyprland: de layout, Caps Lock as Escape.
      xkb-layout = config.services.xserver.xkb.layout;
      xkb-options = config.services.xserver.xkb.options;

      dpms-timeout = 300; # same as consoleblank on the kernel VTs
    };

  kmsconConfigDir = pkgs.writeTextFile {
    name = "kmscon-config";
    destination = "/kmscon.conf";
    text = lib.generators.toKeyValue {
      mkKeyValue = k: v:
        if lib.isBool v
        then (lib.optionalString (!v) "no-") + k
        else "${k}=${toString v}";
    } kmsconSettings;
  };
in {
  # Two non-default consoles, each replacing agetty on one VT.
  #
  #   tty1      ly -> Hyprland
  #   tty2-4    agetty on the kernel VT (modules/system/console.nix)
  #   tty5      kmscon
  #   tty6      cage + ghostty
  #
  # services.kmscon.enable is deliberately NOT used: that module sets
  # aliases = [ "autovt@.service" ] and suppresses getty@.service outright, so
  # it takes over every VT at once. Driving the package's own kmsconvt@ template
  # for a single instance keeps tty2-4 on the kernel VT.

  # logind would otherwise auto-spawn a getty on tty5/tty6 the moment either is
  # switched to, and ReserveVT defaults to 6 — both would fight the units below.
  services.logind.settings.Login = {
    NAutoVTs = 4;
    ReserveVT = 0;
  };

  systemd = {
    # Provides kmsconvt@.service. NixOS never runs `systemctl enable` on
    # package units, so the template's [Install] Alias=autovt@.service stays
    # inert and only the instance wanted below is started.
    packages = [pkgs.kmscon];

    # Drop-in over the shipped template. The upstream ExecStart defaults to
    # `/bin/login`, which does not exist on NixOS, so the login program has to
    # be passed explicitly.
    services."kmsconvt@" = {
      restartIfChanged = false;
      serviceConfig.ExecStart = [
        "" # reset the packaged ExecStart before appending our own
        (lib.concatStringsSep " " [
          "${pkgs.kmscon}/bin/kmscon"
          "--configdir ${kmsconConfigDir}"
          "--vt=%I"
          "--no-switchvt"
          "--login"
          "--"
          "${config.services.getty.loginProgram} -p"
        ])
      ];
    };

    # The shipped unit already carries Conflicts=getty@%i and
    # OnFailure=getty@%i, so tty5 falls back to a plain agetty if kmscon fails.
    targets.getty.wants = ["kmsconvt@tty5.service"];
  };

  security.pam.services.kmscon = {
    startSession = true;
    allowNullPassword = true;
  };
}
