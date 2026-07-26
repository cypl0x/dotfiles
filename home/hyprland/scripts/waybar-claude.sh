#!/usr/bin/env bash
# Waybar custom module: Claude usage — the REAL 5h + weekly limits.
#
# Reads Anthropic's own usage endpoint (the same data `/usage` shows inside
# Claude Code and the meter on claude.ai) — NOT ccusage. ccusage only parses
# local ~/.claude logs and invents its own fixed 5-hour block, so its % and
# reset never matched Anthropic's real rolling windows. This uses the OAuth
# token Claude Code already stores in ~/.claude/.credentials.json.
#
# Bar shows, without hovering: 5h utilization %, 7-day utilization %, and a
# reset countdown for whichever window is the binding constraint (higher %).
# Tooltip adds exact reset date/times for both windows, plus overage credits.
set -euo pipefail

CREDS="${CLAUDE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
API="${CLAUDE_USAGE_URL:-https://api.anthropic.com/api/oauth/usage}"

fallback() {
  printf '{"text":"%s","tooltip":"%s","class":"claude"}\n' "${2:-󰧑 –}" "$1"
  exit 0
}
command -v jq >/dev/null 2>&1 || fallback "jq not found"
command -v curl >/dev/null 2>&1 || fallback "curl not found"
[ -r "$CREDS" ] || fallback "no credentials file"

tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null) || fallback "creds parse error"
[ -n "$tok" ] || fallback "no OAuth token"

fetch() {
  curl -sf --max-time 10 "$API" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" 2>/dev/null
}

# Local date/time of an ISO reset, plus "(in …)" countdown. Defined early so
# --detail can reuse it.
fmt_reset() { # $1 = iso -> "Fri 02:00  (in 11h 38m)"
  local iso=$1 tgt now s d h m
  [ -n "$iso" ] || {
    echo "?"
    return
  }
  tgt=$(date -d "$iso" +%s 2>/dev/null) || {
    echo "$iso"
    return
  }
  now=$(date +%s)
  s=$((tgt - now))
  local when
  when=$(date -d "$iso" '+%a %b %-d, %H:%M' 2>/dev/null)
  if ((s < 0)); then
    echo "$when (now)"
    return
  fi
  d=$((s / 86400))
  h=$(((s % 86400) / 3600))
  m=$(((s % 3600) / 60))
  local in
  if ((d > 0)); then
    in=$(printf '%dd %dh' "$d" "$h")
  elif ((h > 0)); then
    in=$(printf '%dh %02dm' "$h" "$m")
  else in=$(printf '%dm' "$m"); fi
  printf '%s (in %s)' "$when" "$in"
}

# --detail: human-readable dump for the right-click terminal popup.
if [ "${1:-}" = "--detail" ]; then
  d=$(fetch) || {
    echo "Claude usage API unreachable (token may be expired — run Claude Code to refresh)."
    exit 0
  }
  echo "Claude usage — real limits (claude.ai)"
  echo
  while IFS=$'\t' read -r name pct iso; do
    printf '  %-8s %3d%%   resets %s\n' "$name" "$pct" "$(fmt_reset "$iso")"
  done < <(printf '%s' "$d" | jq -r '
    ["5-hour", (.five_hour.utilization|round), .five_hour.resets_at],
    ["7-day",  (.seven_day.utilization|round), .seven_day.resets_at]
    | @tsv')
  extra=$(printf '%s' "$d" | jq -r '.extra_usage as $e
    | if ($e != null and $e.is_enabled)
      then "  Overage  \($e.used_credits/100|floor)/\($e.monthly_limit/100|floor) \($e.currency)  (\($e.utilization|round)%)"
      else empty end')
  [ -n "$extra" ] && {
    echo
    echo "$extra"
  }
  echo
  echo "All active limits:"
  while IFS=$'\t' read -r sev kind pct iso; do
    printf '  [%-8s] %-12s %3s%%   resets %s\n' "$sev" "$kind" "$pct" "$(fmt_reset "$iso")"
  done < <(printf '%s' "$d" | jq -r '.limits[]? | [.severity, .kind, .percent, .resets_at] | @tsv')
  exit 0
fi

resp=$(fetch) || fallback "usage API unreachable\n(token may be expired — run Claude Code to refresh)"

# 5h % + reset, 7d % + reset, worst severity across the active limits.
read -r h5_pct h5_reset d7_pct d7_reset sev <<<"$(printf '%s' "$resp" | jq -r '
  [ ( .five_hour.utilization // 0 | round ),
    ( .five_hour.resets_at   // "" ),
    ( .seven_day.utilization // 0 | round ),
    ( .seven_day.resets_at   // "" ),
    ( [ .limits[]? | .severity ]
      | ( if any(. == "critical") then "critical"
          elif any(. == "warning") then "warning"
          else "normal" end ) )
  ] | @tsv')" 2>/dev/null || fallback "usage parse error"

# ISO-8601 (with tz) -> "Xd Yh" / "Xh Ym" / "Xm" until then.
delta() {
  local iso=$1 tgt now s
  [ -n "$iso" ] || {
    echo "?"
    return
  }
  tgt=$(date -d "$iso" +%s 2>/dev/null) || {
    echo "?"
    return
  }
  now=$(date +%s)
  s=$((tgt - now))
  ((s < 0)) && {
    echo "now"
    return
  }
  local d=$((s / 86400)) h=$(((s % 86400) / 3600)) m=$(((s % 3600) / 60))
  if ((d > 0)); then
    printf '%dd %dh' "$d" "$h"
  elif ((h > 0)); then
    printf '%dh %02dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}
# Exact local date/time of a reset.
at() { [ -n "$1" ] && date -d "$1" '+%a %H:%M' 2>/dev/null || echo "?"; }

h5_pct=${h5_pct:-0}
d7_pct=${d7_pct:-0}
h5_d=$(delta "$h5_reset")
d7_d=$(delta "$d7_reset")

# Bar always shows the 5h reset — it's the window the user watches most.
bind="5h"
bind_d=$h5_d

case "$sev" in
critical) cls="claude critical" ;;
warning) cls="claude warning" ;;
*) cls="claude" ;;
esac

text=$(printf '󰧑 5h %d%% · 7d %d%% · %s↻%s' "$h5_pct" "$d7_pct" "$bind" "$bind_d")

# Overage credits (extra_usage): "used/limit CUR (N%)".
extra=$(printf '%s' "$resp" | jq -r '
  .extra_usage as $e
  | if ($e != null and $e.is_enabled) then
      "\($e.used_credits/100 | floor)/\($e.monthly_limit/100 | floor) \($e.currency) (\($e.utilization|round)%)"
    else "" end' 2>/dev/null || echo "")

tip="Claude usage — real limits (claude.ai)"
tip="${tip}\n5h window: ${h5_pct}%  · resets $(at "$h5_reset") (in ${h5_d})"
tip="${tip}\n7d window: ${d7_pct}%  · resets $(at "$d7_reset") (in ${d7_d})"
[ -n "$extra" ] && tip="${tip}\nOverage credits: ${extra}"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tip" "$cls"
