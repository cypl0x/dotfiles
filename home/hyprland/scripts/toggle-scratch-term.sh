#!/usr/bin/env bash
# Drop-down scratchpad terminal (Yakuake-style), resilient to `exit`.
#
# The dedicated Ghostty lives on the hidden `special:scratch` workspace and is
# only shown/hidden on toggle (redraw, no relaunch). But if the user types
# `exit`, the terminal is gone — so before toggling, respawn it when missing.
set -euo pipefail

class="com.ghostty.scratch"

if hyprctl clients | grep -q "class: ${class}$"; then
    # Alive — just toggle visibility.
    hyprctl dispatch togglespecialworkspace scratch
else
    # Died (user `exit`ed) or never spawned — respawn, wait for map, then show.
    hyprctl dispatch exec "[workspace special:scratch silent] ghostty --class=${class}"
    for _ in $(seq 1 40); do
        hyprctl clients | grep -q "class: ${class}$" && break
        sleep 0.05
    done
    hyprctl dispatch togglespecialworkspace scratch
fi
