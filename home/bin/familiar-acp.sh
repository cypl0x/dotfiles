# shellcheck shell=bash
# familiar-acp — run familiar as an ACP agent: give this command to an
# editor (Zed, agent-shell, ...) as the agent to launch.  It connects the
# editor's stdio to the Emacs daemon (familiar-acp.el, M-x
# familiar-acp-start), greeting it with the token familiar's servers share.
#
# Packaged with writeShellApplication (modules/system/packages.nix).

port=${FAMILIAR_ACP_PORT:-39392}
token_file=${FAMILIAR_TOKEN_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/emacs/familiar-mcp-http-token}

if [[ ! -r $token_file ]]; then
  echo "familiar-acp: no token at $token_file (has Emacs served familiar yet?)" >&2
  exit 1
fi
if ! exec 3<>"/dev/tcp/127.0.0.1/$port"; then
  echo "familiar-acp: nothing on 127.0.0.1:$port (M-x familiar-acp-start in Emacs)" >&2
  exit 1
fi
printf 'AUTH %s\n' "$(<"$token_file")" >&3

cat <&3 & # Emacs → editor
from_emacs=$!
# Explicit <&0: a background job in a non-interactive shell otherwise gets
# /dev/null as stdin, reads nothing, and the bridge ended at once.
cat <&0 >&3 & # editor → Emacs
to_emacs=$!

# Whichever side ends first (the editor closes stdin, or Emacs the
# connection), stop the other: no half-dead agent left behind.
wait -n "$from_emacs" "$to_emacs" || true
kill "$from_emacs" "$to_emacs" 2>/dev/null || true
exec 3>&-
