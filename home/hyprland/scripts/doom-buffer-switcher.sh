#!/usr/bin/env bash
# Fuzzy-jump to any (Doom) Emacs buffer via rofi, then raise the Emacs window.
#
# Talks to the running Emacs server with emacsclient --eval, so it needs
# `M-x server-start` (Doom starts it by default). Buffer names beginning with a
# space are internal churn and are filtered out; "*scratch*"/"*Messages*" etc.
# are kept on purpose. focuswindow switches workspaces, so this works from any
# workspace.
set -euo pipefail

buffers=$(emacsclient --eval '
  (mapconcat (function identity)
    (seq-filter (lambda (n) (not (string-prefix-p " " n)))
      (mapcar (function buffer-name) (buffer-list)))
    "\n")' 2>/dev/null | sed -e 's/^"//' -e 's/"$//' -e 's/\\n/\n/g') || {
  notify-send "Emacs" "No emacs server (start it with M-x server-start)"
  exit 0
}
[ -z "$buffers" ] && exit 0

choice=$(printf '%s\n' "$buffers" | rofi -dmenu -i -p "  buffer" \
  -theme "$HOME/.config/rofi/doom-vibrant.rasi")
[ -z "$choice" ] && exit 0

# Escape backslashes and quotes for the elisp string literal.
esc=${choice//\\/\\\\}
esc=${esc//\"/\\\"}
emacsclient --eval "(switch-to-buffer \"$esc\")" >/dev/null 2>&1 || true

addr=$(hyprctl clients -j |
  jq -r '.[] | select(.class|test("emacs";"i")) | .address' | head -n1)
[ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr"
