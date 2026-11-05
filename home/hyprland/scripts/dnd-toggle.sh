#!/usr/bin/env bash
# Toggle swaync's Do-Not-Disturb and say so.  DND had been on unnoticed
# (a stray SUPER+SHIFT+N or right-click on the bell): browser notifications
# never popped up and 776 piled up silently in the center.  The "on"
# message is critical, the one kind DND still shows.
state=$(swaync-client --toggle-dnd --skip-wait)
if [ "$state" = "true" ]; then
  notify-send -u critical -h boolean:SWAYNC_BYPASS_DND:true -t 6000 -a "Do Not Disturb" "Do Not Disturb is on" \
    "Notifications go silently to the center. SUPER+SHIFT+N turns it off."
else
  notify-send -u low -a "Do Not Disturb" "Do Not Disturb is off" "Notifications pop up again."
fi
