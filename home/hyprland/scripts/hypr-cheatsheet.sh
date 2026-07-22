#!/usr/bin/env bash
# which-key-style Hyprland keybinding cheatsheet — parses the live hyprland.conf
# and lists every bind* in a rofi popup. The trailing `# comment` on a bind line
# (if present) is used as the description, otherwise the dispatcher + args.
set -euo pipefail

conf="$HOME/.config/hypr/hyprland.conf"
[ -f "$conf" ] || { notify-send "Hyprland" "hyprland.conf not found"; exit 0; }

awk '
  /^[[:space:]]*bind[a-z]*[[:space:]]*=/ {
    line=$0
    sub(/^[^=]*=[[:space:]]*/, "", line)           # drop the "bind... =" prefix
    desc=""
    if (match(line, /#/)) {                          # inline comment -> description
      desc=substr(line, RSTART+1); sub(/^[[:space:]]+/, "", desc)
      line=substr(line, 1, RSTART-1)
    }
    n=split(line, a, ",")
    mods=a[1]; key=a[2]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", mods)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    action=""
    for (i=3; i<=n; i++) { v=a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
                           action=(action=="") ? v : action" "v }
    gsub(/\$mainMod/, "SUPER", mods)
    gsub(/[[:space:]]+/, "+", mods)                  # "SUPER SHIFT" -> "SUPER+SHIFT"
    combo=(mods=="") ? key : mods"+"key
    if (desc=="") desc=action
    if (combo!="") printf "%-24s  %s\n", combo, desc
  }' "$conf" \
  | rofi -dmenu -i -no-custom -p "󰌌 keys" \
         -theme "$HOME/.config/rofi/doom-vibrant.rasi" >/dev/null || true
