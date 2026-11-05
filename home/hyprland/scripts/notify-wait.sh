#!/usr/bin/env bash
# notify-wait LIMIT NOTIFY-SEND-ARGS...
#
# `notify-send --wait`, bounded: prints the action clicked (as --wait does)
# or nothing.  Waits at most LIMIT (a `timeout` duration: 30m, 2h), then
# closes its own notification, so neither the waiting process nor the
# notification outlives it.
#
# Why: --wait returns only on a click or a close, and swaync keeps
# notifications nobody answered in its center, open.  Every waiter lived on
# (14 of them, up to 11 hours old, on 2026-11-05) and the center filled up
# (776 notifications).
set -uo pipefail

limit=${1:?usage: notify-wait LIMIT NOTIFY-SEND-ARGS...}
shift
out=$(mktemp)
trap 'rm -f "$out"' EXIT

timeout "$limit" notify-send --print-id --wait "$@" >"$out" 2>/dev/null
status=$?
id=$(sed -n 1p "$out")
action=$(sed -n 2p "$out")

if [ "$status" -eq 124 ] && [ -n "$id" ]; then
  busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications CloseNotification u "$id" >/dev/null 2>&1 || true
fi
[ -n "$action" ] && printf '%s\n' "$action"
exit 0
