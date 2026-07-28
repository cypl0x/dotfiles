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
  };
}
