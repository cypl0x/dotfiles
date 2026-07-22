#!/usr/bin/env bash
# Network stats for the default-route interface.
#   (no arg)  → live throughput sampled over 1s: "󰈀 iface  󰇚 <down>/s  󰕒 <up>/s"
#   sum       → cumulative traffic since boot:   "󰇚 <rx>  󰕒 <tx>  Σ <total>"
# Prints an offline marker when there is no default route.
set -euo pipefail

iface=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
if [ -z "${iface:-}" ]; then
  echo "󰤭 offline"
  exit 0
fi

human() {
  local b=$1
  if [ "$b" -ge 1073741824 ]; then
    awk "BEGIN{printf \"%.1fG\", $b/1073741824}"
  elif [ "$b" -ge 1048576 ]; then
    awk "BEGIN{printf \"%.1fM\", $b/1048576}"
  elif [ "$b" -ge 1024 ]; then
    awk "BEGIN{printf \"%.0fK\", $b/1024}"
  else
    echo "${b}B"
  fi
}

if [ "${1:-}" = "sum" ]; then
  rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
  tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
  echo "󰇚 $(human "$rx")   󰕒 $(human "$tx")   Σ $(human $((rx + tx)))"
  exit 0
fi

rx1=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
tx1=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
sleep 1
rx2=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
tx2=$(cat "/sys/class/net/$iface/statistics/tx_bytes")

echo "󰈀 $iface   󰇚 $(human $((rx2 - rx1)))/s   󰕒 $(human $((tx2 - tx1)))/s"
