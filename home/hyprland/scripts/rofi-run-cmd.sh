#!/usr/bin/env bash
# Type a shell command into rofi and see its output in a floating, fully
# selectable/copyable terminal — rofi's own message box is display-only, so we
# hand off to kitty instead.
#
#   plain command         ->  run in a floating kitty (kept open via --hold)
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
  # --class sets the Wayland app-id; keep it in sync with the float-rofi-cmd
  # windowrule in hyprland.conf. kitty is not single-instance unless started
  # with --single-instance, so this window always gets its own process and
  # keeps its class — no ghostty-style handoff to strip it.
  #
  # --hold keeps the window open after the command exits so the output stays
  # readable and selectable (ghostty spelled this --wait-after-command).
  kitty --class=com.rofi.cmd --title="sh: $cmd" --hold sh -c "$cmd"
fi
