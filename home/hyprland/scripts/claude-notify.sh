#!/usr/bin/env bash
# Claude Code "Notification" hook: raise a desktop notification whose click
# jumps to the terminal window running THIS Claude session.
#
# Wire it in ~/.claude/settings.json:
#   "hooks": { "Notification": [ { "hooks": [
#     { "type": "command", "command": "/home/wap/.config/hypr/scripts/claude-notify.sh" }
#   ] } ] }
#
# How the jump works: the hook process is a descendant of the terminal
# emulator, so we walk up the PID chain until a PID matches a Hyprland client —
# that client is the session's window. notify-send --wait attaches a default
# action; clicking the notification in swaync returns "default" and we
# focuswindow it (which switches workspace too). The listener runs detached so
# the hook returns immediately.
set -euo pipefail

input=$(cat 2>/dev/null || echo '{}')
msg=$(printf '%s' "$input" | jq -r '.message // "Claude Code is waiting for your input"' 2>/dev/null ||
  echo "Claude Code is waiting for your input")
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
title="Claude Code"
[ -n "$cwd" ] && title="Claude Code — $(basename "$cwd")"

addr=""
pid=${PPID:-0}
for _ in $(seq 1 15); do
  { [ -z "$pid" ] || [ "$pid" -le 1 ] 2>/dev/null; } && break
  a=$(hyprctl clients -j 2>/dev/null |
    jq -r --argjson p "$pid" '.[] | select(.pid == $p) | .address' | head -n1)
  [ -n "$a" ] && {
    addr="$a"
    break
  }
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done

if [ -n "$addr" ]; then
  (
    # --wait returns only on a click or a close, and swaync moves unanswered
    # notifications to its center without closing them: listeners piled up
    # (175 of them, 5 days old, ~1 GiB on 2026-11-04).  Listen 15 minutes;
    # the notification itself stays in the center after that.
    act=$(timeout 15m notify-send --app-name="Claude Code" --urgency=normal --wait \
      --action="default=Jump to session" "$title" "$msg" 2>/dev/null || true)
    [ "$act" = "default" ] && hyprctl dispatch focuswindow "address:$addr"
  ) &
  disown 2>/dev/null || true
else
  notify-send --app-name="Claude Code" --urgency=normal "$title" "$msg" || true
fi
