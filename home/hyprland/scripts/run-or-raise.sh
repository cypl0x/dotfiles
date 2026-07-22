#!/usr/bin/env bash
# run-or-raise: focus an existing window of $class, or launch $cmd if none.
# Usage: run-or-raise.sh <class-regex> <command> [args...]
set -euo pipefail

class="$1"
shift

if hyprctl clients -j | grep -q "\"class\": \"${class}\""; then
  hyprctl dispatch focuswindow "class:^(${class})$"
else
  setsid -f "$@" >/dev/null 2>&1
fi
