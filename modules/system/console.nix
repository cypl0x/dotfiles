{pkgs, ...}: {
  # Linux virtual-terminal (kernel VT) tuning — applies to every tty that runs
  # a plain agetty. tty1 is ly/Hyprland and is unaffected.
  #
  # These settings go through systemd-vconsole-setup, which is global: the
  # kernel keeps font/palette/cursor per virtual console, but NixOS has no
  # per-VT option. Per-VT overrides need a unit of their own.

  console = {
    # spleen 12x24 -> a 160x45 grid at this panel's 1920x1080.
    #
    # Chosen over terminus (last release 2020, maintenance only) because spleen
    # is actively developed and reads better at this size. The VT can only load
    # PSF bitmaps, so outline fonts — Maple Mono, Iosevka — are not candidates
    # here regardless of Nerd Font patching.
    font = "spleen-12x24";
    packages = [pkgs.spleen];

    # Load the font from the initrd instead of after stage-2. Without this the
    # console spends early boot in the kernel's built-in 8x16 and visibly
    # snaps to spleen partway through.
    earlySetup = true;

    # Derive the console keymap from services.xserver.xkb (de layout,
    # caps:escape) instead of leaving the VT on the us default.
    #
    # xkb settings apply to Wayland and X clients only — the VT uses loadkeys
    # and never saw them, so Caps Lock was still Caps Lock and the layout was
    # still us on every tty.
    useXkbConfig = true;

    # Doom Vibrant, matching home/zellij.nix so the VT, zellij and kitty all
    # agree. Slots 0-7 are the base hues taken verbatim from that theme; 8-15
    # are brightened derivations, since the theme only defines eight.
    #
    # Sixteen is the hard ceiling: the kernel VT parses no 256-colour or 24-bit
    # SGR at all. What it does allow is remapping each of the sixteen to an
    # arbitrary RGB, which is what this is.
    colors = [
      "1c1f24" #  0 black         (base0)
      "ff665c" #  1 red
      "7bc275" #  2 green
      "fcce7b" #  3 yellow
      "51afef" #  4 blue
      "c57bdb" #  5 magenta
      "5cefff" #  6 cyan
      "bbc2cf" #  7 white         (fg)
      "5b6268" #  8 bright black  (fg-alt — comments, dim UI)
      "ff7b70" #  9 bright red
      "92cf8c" # 10 bright green
      "ffd98f" # 11 bright yellow
      "6cc0ff" # 12 bright blue
      "d494e8" # 13 bright magenta
      "7df5ff" # 14 bright cyan
      "dfdfdf" # 15 bright white
    ];
  };

  boot.kernelParams = [
    # Block cursor instead of the default underscore.
    #
    # The low nibble of vt.cur_default is the shape, per the kernel's CUR_*
    # constants: 1 none, 2 underline, 3 lower third, 4 lower half,
    # 5 two thirds, 6 block. The running value was 2, which is where the
    # underscore came from. The equivalent at runtime is `printf '\033[?6c'`
    # written to a specific tty — that form is per-VT, this one is the default
    # every VT resets to.
    "vt.cur_default=6"

    # The console never blanked (consoleblank defaulted to 0). Five minutes,
    # matching the rough feel of the Hyprland idle timeout.
    "consoleblank=300"
  ];

  # Stop the block cursor blinking. This is an fbcon runtime knob with no
  # kernel-parameter equivalent, so it has to be written after boot.
  systemd.tmpfiles.rules = [
    "w /sys/class/graphics/fbcon/cursor_blink - - - - 0"
  ];
}
