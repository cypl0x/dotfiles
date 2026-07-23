#!/usr/bin/env bash
# Type a shell command into rofi and see its output in a floating, fully
# selectable/copyable terminal — rofi's own message box is display-only, so we
# hand off to ghostty instead.
#
#   plain command         ->  run in a floating ghostty (kept open via
#                             --wait-after-command)
#   prefixed with "em "   ->  run inside an emacsclient vterm (yank into kill
#                             ring, edit, resend — the "pipe to emacsclient" idea)
set -euo pipefail

cmd=$(printf '' | rofi -dmenu -p " sh" -lines 0 \
  -theme "$HOME/.config/rofi/doom-vibrant.rasi")
[ -z "$cmd" ] && exit 0

if [[ $cmd == em\ * ]]; then
  body=${cmd#em }
  emacsclient -c -e "(progn (vterm) (vterm-send-string \"${body//\"/\\\"}\") (vterm-send-return))"
else
  # class must be a valid GTK app-id (dotted, no hyphens) or ghostty ignores it
  # and falls back to com.mitchellh.ghostty — keep in sync with the float-rofi-cmd
  # windowrule in hyprland.conf. gtk-single-instance=false is required: otherwise
  # this invocation joins the already-running ghostty process and the new window
  # inherits com.mitchellh.ghostty, so --class (and the float rule) is ignored.
  ghostty --class=com.rofi.cmd --title="sh: $cmd" --gtk-single-instance=false \
    --wait-after-command=true -e sh -c "$cmd"
fi
