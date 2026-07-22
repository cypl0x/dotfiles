#!/usr/bin/env bash
# One-line system stats for the hyprlock screen: battery, load, temperature.
set -euo pipefail

# Battery (may be absent on desktops)
bat=""
if [ -r /sys/class/power_supply/BAT0/capacity ]; then
  cap=$(cat /sys/class/power_supply/BAT0/capacity)
  st=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "")
  case "$st" in
    Charging) icon="󰂄" ;;
    Full) icon="󰁹" ;;
    *) icon="󱊣" ;;
  esac
  bat="$icon ${cap}%   "
fi

# 1-minute load average
load=$(cut -d' ' -f1 /proc/loadavg)

# Temperature (first thermal zone), best-effort
temp=""
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$z" ] || continue
  t=$(awk '{printf "%.0f", $1/1000}' "$z")
  temp="    $t°C"
  break
done

echo "${bat} $load${temp}"
