#!/usr/bin/env bash
# Waybar custom module: Claude Code 5-hour usage, as a % of the token limit.
#
# Uses ccusage (https://github.com/ryoppippi/ccusage) — parses the local
# ~/.claude logs, no network/key. ccusage groups usage into fixed 5-hour blocks;
# `--token-limit N` makes it report tokenLimitStatus so we can show "% used".
#
# The limit is your plan's 5h token allowance. ccusage cannot read Anthropic's
# real limit, so it's set here (override with $CLAUDE_5H_TOKEN_LIMIT). Calibrated
# from a known data point: 42.1M tokens read as ~53% -> ~80M limit.
#
# The bar shows CURRENT tokens as a % of that limit (not ccusage's own
# "percentUsed", which is the *projected* end-of-block figure). Note the reset
# countdown is ccusage's fixed-block remainder and can differ from Claude's
# real rolling-window reset.
set -euo pipefail

LIMIT=${CLAUDE_5H_TOKEN_LIMIT:-80000000}
fallback() { printf '{"text":"","tooltip":"%s","class":"claude"}\n' "$1"; exit 0; }
command -v npx >/dev/null 2>&1 || fallback "npx not found"
hum() { numfmt --to=si --format='%.1f' "${1%.*}" 2>/dev/null || echo "${1:-0}"; }

blocks=$(npx -y ccusage@latest blocks --active --token-limit "$LIMIT" --json 2>/dev/null) \
  || fallback "ccusage unavailable"
daily=$(npx -y ccusage@latest daily --json 2>/dev/null || echo '{}')

# totalTokens, % of limit used NOW, minutes left in the 5h block, cost.
read -r b_tok b_pct b_rem b_cost <<<"$(printf '%s' "$blocks" | jq -r '
  ( [ .blocks[]? | select(.isActive == true) ] | first ) // ( .blocks[-1]? ) // {} as $b
  | ( $b.tokenLimitStatus.limit // 0 ) as $lim
  | ( $b.totalTokens // 0 ) as $tok
  | [ $tok,
      ( if $lim > 0 then ($tok / $lim * 100 | floor) else -1 end ),
      ( $b.projection.remainingMinutes // 0 | floor ),
      ( $b.costUSD // 0 ) ] | @tsv')" 2>/dev/null || fallback "parse error"

# Fall back to the configured limit if ccusage omitted tokenLimitStatus.
if [ "${b_pct:-'-1'}" = "-1" ] && [ "${b_tok:-0}" -gt 0 ] 2>/dev/null; then
  b_pct=$(( b_tok * 100 / LIMIT ))
fi

read -r today_tok week_tok <<<"$(printf '%s' "$daily" | jq -r '
  ( [ .daily[]? ] ) as $d
  | [ ( $d[-1].totalTokens // 0 ),
      ( $d[-7:] | map(.totalTokens // 0) | add // 0 ) ] | @tsv' 2>/dev/null || echo "0	0")"

# reset countdown "Xh Ym"
rem=${b_rem:-0}
reset=$(printf '%dh %02dm' $(( rem / 60 )) $(( rem % 60 )))

if [ "${b_pct:-'-1'}" != "-1" ] && [ "${b_pct:-0}" -ge 0 ] 2>/dev/null; then
  text="󰧑 ${b_pct}%"
  if   [ "$b_pct" -ge 90 ]; then cls="claude critical"
  elif [ "$b_pct" -ge 70 ]; then cls="claude warning"
  else cls="claude"; fi
else
  text="󰧑 $(hum "$b_tok")"
  cls="claude"
fi

tip="Claude Code — 5h window"
[ "${b_pct:-'-1'}" != "-1" ] && tip="${tip}\nUsed: ${b_pct}% of $(hum "$LIMIT") token limit"
tip="${tip}\nTokens: $(hum "$b_tok")\nResets in ${reset}"
tip="${tip}\nToday: $(hum "$today_tok") tok · Last 7d: $(hum "$week_tok") tok"
tip="${tip}\n5h cost: \$$(LC_ALL=C printf '%.2f' "${b_cost:-0}")"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tip" "$cls"
