#!/usr/bin/env bash
# Waybar custom module: Claude Code usage, token-focused.
#
# Uses ccusage (https://github.com/ryoppippi/ccusage) — parses the local
# ~/.claude usage logs, no network, no API key. The bar shows the current
# 5-hour rate-limit window's token count; the tooltip adds the % of the window
# elapsed, today, and the last 7 days. Cost is intentionally de-emphasised
# (shown only in the tooltip). Long refresh interval (see config.jsonc) because
# each `npx` startup is not free.
set -euo pipefail

fallback() { printf '{"text":"","tooltip":"%s","class":"claude"}\n' "$1"; exit 0; }
command -v npx >/dev/null 2>&1 || fallback "npx not found"
hum() { numfmt --to=si --format='%.1f' "${1%.*}" 2>/dev/null || echo "${1:-0}"; }

blocks=$(npx -y ccusage@latest blocks --active --json 2>/dev/null) || fallback "ccusage unavailable"
daily=$(npx -y ccusage@latest daily --json 2>/dev/null || echo '{}')

# Active 5h block: tokens, cost, minutes left, and % of the 5h window elapsed.
read -r b_tok b_cost b_rem b_pct <<<"$(printf '%s' "$blocks" | jq -r '
  ( [ .blocks[]? | select(.isActive == true) ] | first ) // ( .blocks[-1]? ) // {} as $b
  | ( ($b.startTime // "") as $s | ($b.endTime // "") as $e
      | if ($s != "" and $e != "")
        then ( ((now - ($s|fromdateiso8601)) / (($e|fromdateiso8601) - ($s|fromdateiso8601)) * 100)
               | if . < 0 then 0 elif . > 100 then 100 else . end | floor )
        else -1 end ) as $pct
  | [ ($b.totalTokens // 0),
      ($b.costUSD // 0),
      ($b.projection.remainingMinutes // 0),
      $pct ] | @tsv')" || fallback "parse error"

# Today and last-7-days token totals from the daily report.
read -r today_tok week_tok <<<"$(printf '%s' "$daily" | jq -r '
  ( [ .daily[]? ] ) as $d
  | [ ( $d[-1].totalTokens // 0 ),
      ( $d[-7:] | map(.totalTokens // 0) | add // 0 ) ] | @tsv' 2>/dev/null || echo "0	0")"

text="󰧑 $(hum "$b_tok")"
tip="Claude Code — token usage\n5h window: $(hum "$b_tok") tok"
[ "${b_pct:-'-1'}" != "-1" ] && tip="${tip}  (${b_pct}% elapsed)"
tip="${tip}\nBlock ends in ~$(printf '%.0f' "${b_rem:-0}") min"
tip="${tip}\nToday: $(hum "$today_tok") tok\nLast 7d: $(hum "$week_tok") tok"
tip="${tip}\n5h cost: \$$(printf '%.2f' "${b_cost:-0}")"

printf '{"text":"%s","tooltip":"%s","class":"claude"}\n' "$text" "$tip"
