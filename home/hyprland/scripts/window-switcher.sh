#!/usr/bin/env bash
# Fuzzy switch/jump to any open window (terminals included) via rofi.
#
# rofi's built-in `-show window` mode is X11-only and does nothing on Wayland,
# so we drive it from Hyprland's own client list instead. Column 1 is the
# window address (data), column 2 is the human label (shown).
#
# For switching *within* a terminal (kitty tabs, tmux/zellij panes) use that
# tool's native switcher — kitty: Ctrl+Space b b, tmux: prefix w, zellij: Ctrl+t.
set -euo pipefail

rows=$(hyprctl clients -j | jq -r '
  .[] | select(.mapped == true and .title != "")
  | "\(.address)\t\(.class)  —  \(.title)   [ws \(.workspace.name)]"')

[ -z "$rows" ] && exit 0

choice=$(printf '%s\n' "$rows" | rofi -dmenu -i \
  -p "  window" \
  -with-nth 2 \
  -theme "$HOME/.config/rofi/doom-vibrant.rasi")

[ -z "$choice" ] && exit 0
addr=$(printf '%s' "$choice" | cut -f1)
hyprctl dispatch focuswindow "address:$addr"
