#!/usr/bin/env bash
# Network throughput for the default-route interface, sampled over 1s.
# Prints "󰇚 <down>  󰕒 <up>" in human units, or an offline marker.
set -euo pipefail

iface=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
if [ -z "${iface:-}" ]; then
  echo "󰤭 offline"
  exit 0
fi

rx1=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
tx1=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
sleep 1
rx2=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
tx2=$(cat "/sys/class/net/$iface/statistics/tx_bytes")

human() {
  local b=$1
  if   [ "$b" -ge 1048576 ]; then awk "BEGIN{printf \"%.1fM\", $b/1048576}"
  elif [ "$b" -ge 1024 ];    then awk "BEGIN{printf \"%.0fK\", $b/1024}"
  else echo "${b}B"
  fi
}

echo "󰈀 $iface   󰇚 $(human $((rx2 - rx1)))/s   󰕒 $(human $((tx2 - tx1)))/s"
