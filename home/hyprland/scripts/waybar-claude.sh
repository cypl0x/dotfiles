#!/usr/bin/env bash
# Waybar custom module: current Claude Code usage.
#
# Uses ccusage (https://github.com/ryoppippi/ccusage), which parses the local
# ~/.claude usage logs — no network, no API key. `blocks --active` reports the
# live 5-hour rate-limit window: spend so far, token count and the projected
# end-of-block cost. Run on a long interval (see config.jsonc) because the first
# `npx` invocation has to fetch the package.
#
# Emits waybar JSON ({text,tooltip,class}); prints an empty text when there is
# no active block or ccusage isn't reachable, so the module just disappears.
set -euo pipefail

fallback() { printf '{"text":"","tooltip":"%s","class":"claude"}\n' "$1"; exit 0; }

command -v npx >/dev/null 2>&1 || fallback "npx not found"

j=$(npx -y ccusage@latest blocks --active --json 2>/dev/null) || fallback "ccusage unavailable"
[ -z "$j" ] && fallback "no ccusage output"

printf '%s' "$j" | jq -c '
  ( [ .blocks[]? | select(.isActive == true) ] | first )
    // ( .blocks[-1]? ) // {} as $b
  | ($b.costUSD // 0)                      as $cost
  | ($b.totalTokens // 0)                  as $tok
  | ($b.projection.totalCost // 0)         as $proj
  | ($b.projection.remainingMinutes // 0)  as $rem
  | ($cost*100|round/100|tostring)         as $c
  | ($proj*100|round/100|tostring)         as $p
  | { text: ("󰧑 $" + $c),
      tooltip: ("Claude Code — active 5h block\nSpent: $" + $c
                + "   (projected $" + $p + ")\nTokens: " + ($tok|tostring)
                + "\nBlock ends in ~" + ($rem|floor|tostring) + " min"),
      class: "claude" }' 2>/dev/null || fallback "parse error"
