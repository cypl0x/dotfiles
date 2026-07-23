#!/usr/bin/env bash
# Drop-down terminal (Yakuake-style), resilient to `exit`.
#
# The dedicated Ghostty lives on the hidden `special:term` workspace and is
# only shown/hidden on toggle (redraw, no relaunch). Two quirks handled here:
#   1. If the user typed `exit`, the terminal is gone — respawn when missing.
#   2. Hyprland won't hold a floating special-workspace window at y=0 via a
#      static windowrule, so we pin it to the top edge each time we reveal it.
set -euo pipefail

class="com.ghostty.term"
# Top-anchored geometry (1920x1080 eDP): 1766×626, x=77 centres horizontally,
# y=82 clears the 74px top waybar (otherwise the window hides behind it).
pos_x=77 pos_y=82

# Currently visible? `hyprctl monitors` lists the active special workspace.
if hyprctl monitors | grep -q "special:term"; then
    hyprctl dispatch togglespecialworkspace term          # hide
else
    if ! hyprctl clients | grep -q "class: ${class}$"; then
        hyprctl dispatch exec "[workspace special:term silent] ghostty --class=${class} --background-opacity=0.9"
        for _ in $(seq 1 40); do
            hyprctl clients | grep -q "class: ${class}$" && break
            sleep 0.05
        done
    fi
    hyprctl dispatch togglespecialworkspace term          # show
    hyprctl dispatch movewindowpixel "exact ${pos_x} ${pos_y},class:${class}"
fi
