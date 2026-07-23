#!/usr/bin/env bash
# Fuzzy-switch Firefox tabs from rofi via brotab (bt), then raise Firefox.
#
# One-time setup (brotab talks to the browser over a native-messaging host):
#   1. Install the "Brotab" extension in Firefox.
#   2. Run `bt install` once to register the native host.
# Tridactyl is unaffected — brotab uses its own extension. The Emacs-side
# equivalent is spookfox (SPC-driven tab switch); this is the rofi path.
set -euo pipefail

command -v bt >/dev/null 2>&1 || {
  notify-send "brotab" "bt not found"
  exit 0
}

list=$(bt list 2>/dev/null) ||
  {
    notify-send "brotab" "no browser client — run 'bt install' and add the extension"
    exit 0
  }
[ -z "$list" ] && {
  notify-send "brotab" "no open tabs / client not connected"
  exit 0
}

# `bt list` rows: "<prefix>.<win>.<tab>\t<title>\t<url>". Show title + url;
# -format i returns the 0-based row index so we can recover the tab id.
idx=$(printf '%s\n' "$list" |
  awk -F'\t' '{printf "%s   —   %s\n", $2, $3}' |
  rofi -dmenu -i -p "󰈹 tab" -format i \
    -theme "$HOME/.config/rofi/doom-vibrant.rasi")
[ -z "$idx" ] && exit 0

id=$(printf '%s\n' "$list" | sed -n "$((idx + 1))p" | cut -f1)
[ -n "$id" ] && bt activate "$id"

addr=$(hyprctl clients -j |
  jq -r '.[] | select(.class|test("firefox";"i")) | .address' | head -n1)
[ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr"
