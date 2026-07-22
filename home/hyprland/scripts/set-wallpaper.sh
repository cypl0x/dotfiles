#!/usr/bin/env bash
# Set the Doom-vibrant wallpaper via hyprpaper's IPC.
#
# WHY not the declarative `preload=` / `wallpaper=` in hyprpaper.conf?
# On hyprpaper 0.8.4 those directives silently produce no target — hyprpaper
# logs "Monitor <name> has no target: no wp will be created" and the screen
# stays black. The IPC path (hyprctl hyprpaper …) is reliable, so we drive it
# here once the daemon's socket is up.
set -euo pipefail

wp="$HOME/.config/hypr/wallpaper.png"

# Wait for the hyprpaper IPC socket (daemon may still be starting).
for _ in $(seq 1 50); do
  if hyprctl hyprpaper listloaded >/dev/null 2>&1; then break; fi
  sleep 0.2
done

hyprctl hyprpaper preload "$wp" >/dev/null 2>&1 || true
# empty monitor field = all outputs
hyprctl hyprpaper wallpaper ",$wp"
