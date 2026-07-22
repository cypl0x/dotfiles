#!/usr/bin/env bash
# Type a shell command into rofi and see its output in a floating, fully
# selectable/copyable terminal — rofi's own message box is display-only, so we
# hand off to kitty instead.
#
#   plain command         ->  run in a floating kitty (kept open with --hold)
#   prefixed with "em "   ->  run inside an emacsclient vterm (yank into kill
#                             ring, edit, resend — the "pipe to emacsclient" idea)
set -euo pipefail

cmd=$(printf '' | rofi -dmenu -p " sh" -lines 0 \
  -theme "$HOME/.config/rofi/doom-vibrant.rasi")
[ -z "$cmd" ] && exit 0

if [[ "$cmd" == em\ * ]]; then
  body=${cmd#em }
  emacsclient -c -e "(progn (vterm) (vterm-send-string \"${body//\"/\\\"}\") (vterm-send-return))"
else
  kitty --hold --class rofi-cmd --title "sh: $cmd" -- sh -c "$cmd"
fi
