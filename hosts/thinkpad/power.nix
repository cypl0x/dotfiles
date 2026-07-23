_: {
  # ThinkPad power / battery / firmware — laptop-scoped (not imported by the
  # inari server). Aim: longer battery, cooler chassis, healthier SSD, and
  # in-band firmware updates, all declaratively.

  services = {
    # Intel thermal management daemon — throttles before thermal emergencies,
    # keeps fan noise and skin temperature down under sustained load.
    thermald.enable = true;

    # TLP — the battery/CPU power manager. Chosen over power-profiles-daemon
    # (they conflict; NixOS asserts if both run) because there is no GNOME/KDE
    # profile toggle on this Hyprland host and TLP squeezes more runtime.
    power-profiles-daemon.enable = false;
    tlp = {
      enable = true;
      settings = {
        # Scaling governor: responsive on AC, efficient on battery.
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        # Intel P-state energy/performance hints.
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

        # Let the CPU boost on AC, cap it on battery to save power/heat.
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;

        # Runtime PM for PCIe/other devices.
        RUNTIME_PM_ON_AC = "auto";
        RUNTIME_PM_ON_BAT = "auto";

        # ThinkPad battery longevity: stop charging at 80% on the internal
        # battery (BAT0). Prevents keeping the cell at 100% while docked.
        # Requires the tp_smapi / natacpi charge-threshold support present on
        # most ThinkPads; harmless no-op if the model lacks it.
        START_CHARGE_THRESH_BAT0 = 75;
        STOP_CHARGE_THRESH_BAT0 = 80;
      };
    };

    # Periodic SSD TRIM.
    fstrim.enable = true;

    # Firmware updates via LVFS (`fwupdmgr refresh && fwupdmgr update`).
    fwupd.enable = true;
  };

  # Compressed RAM swap — cheap way to extend usable memory and reduce disk
  # swap thrash on the laptop (the server sets its own in hosts/inari).
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
