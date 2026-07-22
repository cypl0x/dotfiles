#!/usr/bin/env bash
# mako left-click handler: jump to the window that sent the notification.
#
# mako runs this via `on-button-left=exec ...` with $id set to the clicked
# notification's ID. We look up its app-name / desktop-entry with
# `makoctl list -j`, invoke the default action (so apps that handle it still
# open the specific mail/chat), dismiss it, then focuswindow the best-matching
# Hyprland client — focuswindow switches workspaces, so this works even with
# misc:focus_on_activate = false.
set -euo pipefail

id="${id:?expected \$id from mako}"

notif=$(makoctl list -j | jq -c --argjson id "$id" '.[] | select(.id == $id)')
[ -z "$notif" ] && exit 0

app=$(jq -r '.app_name // ""' <<<"$notif")
entry=$(jq -r '.desktop_entry // ""' <<<"$notif")

# Default action first (notification must still exist for it), then dismiss.
if [ "$(jq -r '.actions | has("default")' <<<"$notif")" = "true" ]; then
  makoctl invoke -n "$id" || true
fi
makoctl dismiss -n "$id" || true

# Match app-name/desktop-entry against client class/initialClass, comparing
# lowercased alphanumerics only ("Telegram Desktop" vs org.telegram.desktop).
# Exact matches (score 2) beat substring matches (score 1).
addr=$(hyprctl clients -j | jq -r --arg app "$app" --arg entry "$entry" '
  def squash: (. // "") | ascii_downcase | gsub("[^a-z0-9]"; "");
  ($app | squash) as $a | ($entry | squash) as $e |
  [ .[]
    | select(.mapped == true)
    | .cls = (.class | squash) | .icls = (.initialClass | squash)
    | .score =
        (if ($a != "" and (.cls == $a or .icls == $a))
            or ($e != "" and (.cls == $e or .icls == $e)) then 2
         elif .cls != ""
              and (($a != "" and (.cls | (contains($a) or inside($a))))
                or ($e != "" and (.cls | (contains($e) or inside($e))))) then 1
         else 0 end)
    | select(.score > 0)
  ] | sort_by(-.score) | .[0].address // empty')

if [ -n "$addr" ]; then
  hyprctl dispatch focuswindow "address:$addr"
fi
