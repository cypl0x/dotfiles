#!/usr/bin/env bash
# hypr-dispatch DISPATCHER [ARGS]: `hyprctl dispatch` that works with either
# config.  With hyprland.conf (hyprlang) it passes the call through; with
# hyprland.lua, where `hyprctl dispatch` takes a Lua expression, it
# translates the dispatchers these scripts use into Hyprland 0.56's Lua API
# (argument names from src/config/lua/bindings/LuaBindingsDispatchers.cpp):
#
#   focuswindow SELECTOR                  hl.dsp.focus({ window = SELECTOR })
#   workspace WS                          hl.dsp.focus({ workspace = WS })
#   togglespecialworkspace NAME           hl.dsp.workspace.toggle_special(NAME)
#   resizewindowpixel "exact W H,SEL"     hl.dsp.window.resize({ x, y, window })
#   movewindowpixel "exact X Y,SEL"       hl.dsp.window.move({ x, y, window })
#   exec "[RULES] CMD"                    hl.dsp.exec_cmd(CMD, { RULES })
set -euo pipefail

dispatcher=${1:?usage: hypr-dispatch DISPATCHER [ARGS]}
shift
args="$*"

# Lua config? `hyprctl repl' refuses without it.  (Tests: HYPR_DISPATCH_LUA=1
# forces the Lua path, HYPR_DISPATCH_DRY=1 prints the expression instead.)
if [ -z "${HYPR_DISPATCH_LUA:-}" ] && hyprctl repl 'return 1' 2>&1 | grep -q 'only supported with the lua config'; then
  exec hyprctl dispatch "$dispatcher" "$@"
fi

lua_str() { # a Lua string literal
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}
pixels() { # "exact A B,SELECTOR" or "A B,SELECTOR" -> x = A, y = B, relative, window
  local spec=${1%%,*} sel=${1#*,} relative=true
  [[ $spec == exact* ]] && { relative=false; spec=${spec#exact }; }
  read -r a b <<<"$spec"
  printf 'x = %s, y = %s, relative = %s, window = %s' "$a" "$b" "$relative" "$(lua_str "$sel")"
}

case $dispatcher in
  focuswindow) expr="hl.dsp.focus({ window = $(lua_str "$args") })" ;;
  workspace) expr="hl.dsp.focus({ workspace = $(lua_str "$args") })" ;;
  togglespecialworkspace) expr="hl.dsp.workspace.toggle_special($(lua_str "${args:-}"))" ;;
  resizewindowpixel) expr="hl.dsp.window.resize({ $(pixels "$args") })" ;;
  movewindowpixel) expr="hl.dsp.window.move({ $(pixels "$args") })" ;;
  exec)
    if [[ $args =~ ^\[([^]]*)\][[:space:]]*(.*)$ ]]; then
      rules=${BASH_REMATCH[1]} cmd=${BASH_REMATCH[2]}
      key=${rules%% *} value=${rules#* }
      expr="hl.dsp.exec_cmd($(lua_str "$cmd"), { $key = $(lua_str "$value") })"
    else
      expr="hl.dsp.exec_cmd($(lua_str "$args"))"
    fi
    ;;
  *)
    echo "hypr-dispatch: no Lua translation for '$dispatcher' yet" >&2
    exit 2
    ;;
esac
[ -n "${HYPR_DISPATCH_DRY:-}" ] && { printf '%s\n' "$expr"; exit 0; }
exec hyprctl dispatch "$expr"
