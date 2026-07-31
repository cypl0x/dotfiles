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

      # No pointer on tty5.
      #
      # kmscon has no "hide while typing" setting — that is a libinput feature,
      # and kmscon does not use libinput. It reads evdev directly through its
      # own uterm_input layer, which is also why two-finger scrolling does
      # nothing here: a touchpad reports absolute multitouch, and turning that
      # into wheel events is precisely the gesture interpretation libinput
      # performs and kmscon lacks. No kmscon setting can produce it.
      #
      # Off is therefore the only way to get rid of the cursor. The cost is
      # mouse text selection; scrollback is unaffected and stays on
      # Shift+Up/Down and Shift+PgUp/PgDn.
      #
      # tty6 has none of this problem: cage/wlroots does use libinput, so
      # scrolling works there and kitty hides the pointer while typing on its
      # own (kitty defaults mouse_hide_wait to 3s).
      mouse = false;
    };

  kmsconConfigDir = pkgs.writeTextFile {
    name = "kmscon-config";
    destination = "/kmscon.conf";
    text =
      lib.generators.toKeyValue {
        mkKeyValue = k: v:
          if lib.isBool v
          then (lib.optionalString (!v) "no-") + k
          else "${k}=${toString v}";
      }
      kmsconSettings;
  };
in {
  # Two non-default consoles, each replacing agetty on one VT.
  #
  #   tty1      ly -> Hyprland
  #   tty2-4    agetty on the kernel VT (modules/system/console.nix)
  #   tty5      kmscon
  #   tty6      cage + kitty
  #
  # services.kmscon.enable is deliberately NOT used: that module sets
  # aliases = [ "autovt@.service" ] and suppresses getty@.service outright, so
  # it converts every VT at once. Claiming two specific autovt instances keeps
  # tty2-4 on the kernel VT.

  # Both consoles start on demand, via logind's autovt mechanism: on a switch
  # to an idle ttyN, logind starts autovt@ttyN.service. That name normally
  # resolves through the autovt@.service -> getty@.service symlink, but systemd
  # prefers a unit file matching the instance name exactly, so defining
  # autovt@tty5 / autovt@tty6 claims just those two VTs and leaves tty2-4 on
  # the generic template.
  #
  # On demand rather than at boot is not a stylistic choice for cage: wlroots
  # waits ~10s for its logind session to become active and then aborts with
  # "Failed to start a DRM session". A VT in the background never activates, so
  # an eagerly started cage crash-loops forever. Deferring to the switch means
  # the VT is foreground by the time it runs.
  #
  # ReserveVT defaults to 6, which would keep a getty pinned to tty6.
  services.logind.settings.Login.ReserveVT = 0;

  systemd.services = {
    # tty5: kmscon. Config is via --configdir; the upstream ExecStart defaults
    # to /bin/login, which does not exist on NixOS, hence the explicit path.
    "autovt@tty5" = {
      description = "KMS System Console on tty5";
      after = ["systemd-user-sessions.service"];
      restartIfChanged = false;

      unitConfig = {
        # Same safety net the packaged kmsconvt@ template carries: never share
        # the VT with agetty, and fall back to one if kmscon cannot start.
        Conflicts = "getty@tty5.service";
        OnFailure = "getty@tty5.service";
        IgnoreOnIsolate = true;
        ConditionPathExists = "/dev/tty0";
      };

      serviceConfig = {
        User = "root";
        PAMName = "kmscon";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.kmscon}/bin/kmscon"
          "--configdir ${kmsconConfigDir}"
          "--vt=tty5"
          "--no-switchvt"
          "--login"
          "--"
          "${config.services.getty.loginProgram} -p"
        ];
        UtmpIdentifier = "tty5";
        TTYPath = "/dev/tty5";
        TTYReset = "yes";
        TTYVHangup = "yes";
        TTYVTDisallocate = "yes";
      };
    };

    # tty6: cage (wlroots kiosk compositor) running a single kitty.
    #
    # services.cage is unusable here — that module hardcodes tty1, which ly
    # already owns, down to the unit name. This is its unit re-pointed at tty6.
    #
    # Unlike kmscon this is a full Wayland stack, so kitty gets true colour,
    # the same config it uses under Hyprland, and — the reason it earns a VT —
    # the kitty keyboard protocol, which is what makes shift+Enter
    # distinguishable from Enter in Claude Code. Neither the kernel VT nor
    # kmscon can do that; both drop the modifier and send a bare CR.
    "autovt@tty6" = {
      description = "Cage + kitty on tty6";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
      ];
      wants = [
        "dbus.socket"
        "systemd-logind.service"
      ];
      restartIfChanged = false;

      unitConfig = {
        Conflicts = "getty@tty6.service";
        OnFailure = "getty@tty6.service";
        IgnoreOnIsolate = true;
        ConditionPathExists = "/dev/tty6";
      };

      environment = {
        # cage is wlroots, so it reads WLR_DRM_DEVICES rather than the
        # AQ_DRM_DEVICES that aquamarine/Hyprland uses. Same target, same
        # reason, and the same colon trap: both parse the value as a
        # colon-separated list, so this must be the udev symlink from
        # graphics.nix and never a /dev/dri/by-path/ name.
        WLR_DRM_DEVICES = "/dev/dri/intel-gpu";

        # No display manager sits in this path to set the keymap, so
        # libinput/xkbcommon have to be told directly.
        XKB_DEFAULT_LAYOUT = config.services.xserver.xkb.layout;
        XKB_DEFAULT_OPTIONS = config.services.xserver.xkb.options;
      };

      serviceConfig = {
        # -s allows VT switching, without which ctrl+alt+F<n> would be trapped
        # inside cage. -d drops client-side decorations, so kitty fills the
        # screen instead of drawing a titlebar nothing can move.
        #
        # No single-instance guard is needed here: kitty only joins an existing
        # process when explicitly started with --single-instance. ghostty was
        # the opposite — it defaulted to joining the Hyprland session's
        # instance over D-Bus and exiting immediately, taking cage and the
        # whole tty6 console with it.
        #
        # --listen-on gives this console its own remote-control socket, so a
        # kitty under Hyprland can drive it with `kitten @ --to`.
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.cage}/bin/cage"
          "-s"
          "-d"
          "--"
          "${pkgs.kitty}/bin/kitty"
          "--listen-on=unix:/run/user/1000/kitty-tty6"
        ];
        User = "wap";

        # on-success, not always: quitting kitty exits cage 0 and should give
        # a fresh terminal, but a failure to acquire the VT exits 1 and must
        # not be retried, or an accidental start off-VT loops forever.
        Restart = "on-success";

        IgnoreSIGPIPE = "no";

        # This replaces agetty on tty6, so it registers in utmp itself for `w`
        # and `who` to show the session.
        UtmpIdentifier = "tty6";
        UtmpMode = "user";

        TTYPath = "/dev/tty6";
        TTYReset = "yes";
        TTYVHangup = "yes";
        TTYVTDisallocate = "yes";
        StandardInput = "tty-fail"; # refuse to start without the VT
        StandardOutput = "journal";
        StandardError = "journal";

        PAMName = "cage";
      };
    };
  };

  security.pam.services = {
    kmscon = {
      startSession = true;
      allowNullPassword = true;
    };
    # cage needs a logind session of its own to acquire the seat and DRM master.
    cage = {
      startSession = true;
      allowNullPassword = true;
    };
  };
}
