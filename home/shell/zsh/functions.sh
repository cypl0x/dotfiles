#!/usr/bin/env zsh
# Zsh-specific functions

# ============================================================================
# NixOS / Nix Functions
# ============================================================================

# Detect dotfiles directory (default to ~/dotfiles if DOTFILES_DIR not set)
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# These helpers all operate on $DOTFILES_DIR. Each cd runs inside a subshell so
# the calling shell stays wherever you invoked it from — a bare `cd` here used
# to dump you in ~/dotfiles after every update.

# Full update: flake update + rebuild
nixup() {
  (
    cd "$DOTFILES_DIR" || return 1
    nix flake update
    sudo nixos-rebuild switch --flake ".#$(hostname)"
  )
}

# Update a specific flake input + rebuild
nixup-input() {
  if [ -z "$1" ]; then
    echo "Usage: nixup-input <input-name>"
    echo "Example: nixup-input nixpkgs"
    return 1
  fi
  (
    cd "$DOTFILES_DIR" || return 1
    nix flake lock --update-input "$1"
    sudo nixos-rebuild switch --flake ".#$(hostname)"
  )
}

# Quick flake check (statix + nix flake check)
nixcheck() {
  (
    cd "$DOTFILES_DIR" || return 1
    echo "Running flake check..."
    nix flake check
    echo "Running statix check..."
    statix check
  )
}

nixshow() {
  (
    cd "$DOTFILES_DIR" || return 1
    nix flake show
  )
}

nixlint() {
  statix check "$DOTFILES_DIR"
}

# Quick rebuild shortcuts
nrs() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild switch --flake "$DOTFILES_DIR#$(hostname)"
}

# Local-only rebuild (ignore distributed builders)
nrsl() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild switch --flake "$DOTFILES_DIR#$(hostname)" --option builders ""
}

# Remote rebuild/deploy to inari
nrsi() {
  (
    cd "$DOTFILES_DIR" || return 1
    nixos-rebuild switch \
      --flake ".#inari" \
      --use-substitutes \
      --build-host root@65.109.108.233 \
      --target-host root@65.109.108.233
  )
}

nrb() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild boot --flake "$DOTFILES_DIR#$(hostname)"
}

nrt() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild test --flake "$DOTFILES_DIR#$(hostname)"
}

nrsv() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild switch --flake "$DOTFILES_DIR#$(hostname)" --show-trace
}

nrbs() {
  statix check "$DOTFILES_DIR" && sudo nixos-rebuild build --flake "$DOTFILES_DIR#$(hostname)"
}

# ============================================================================
# Yazi — file manager that cd's the shell to its last dir on quit
# ============================================================================
# `y` launches yazi and, on exit, changes the shell into wherever you left it.
# Quit with `q` / `SPC q q` to cd; use `SPC q Q` to stay put.
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd" || return
  fi
  rm -f -- "$tmp"
}

# ============================================================================
# Desktop notifications for long-running commands (>= 5s)
# ============================================================================

__cmd_start_time=0
__cmd_last=()

preexec() {
  __cmd_start_time=$EPOCHSECONDS
  __cmd_last=("$@")
}

precmd() {
  local __cmd_exit_code=$?
  if ((__cmd_start_time > 0)); then
    local elapsed=$((EPOCHSECONDS - __cmd_start_time))
    if ((elapsed >= 5)); then
      local title="Command finished"
      local body="${__cmd_last[1]:-command} (${elapsed}s)"
      if ((__cmd_exit_code != 0)); then
        title="Command failed ($__cmd_exit_code)"
      fi
      command -v notify-send >/dev/null 2>&1 && notify-send "$title" "$body"
    fi
  fi
  __cmd_start_time=0
  __cmd_last=()
}

# ============================================================================
# pick-from-screen — reuse something a previous command printed
# ============================================================================
# The shell never sees stdout. It goes straight to the pty, and only whoever
# owns the scrollback keeps it — the multiplexer if there is one, the terminal
# otherwise, and on a bare kernel VT nobody at all. So "copy that UUID from
# the last command" is only solvable by asking the owner for the text back.
#
# tmux, zellij and kitty all expose their buffer to the CLI, so one keybinding
# can cover all three. Everything else exposes nothing, hence the bail-out.
#
# Alt-v  words — UUIDs, hashes, paths, IPs
# Alt-V  lines — a whole suggested command, e.g. from `tldr`
#
# Each host has a better native tool: prefix+Tab (extrakto) and prefix+g
# (tmux-thumbs) under tmux, ctrl+space>y under kitty. This exists because it is
# the same keybinding everywhere and never leaves the zsh line editor.

__screen_dump() {
  if [[ -n $TMUX ]]; then
    # -J rejoins wrapped lines so a long URL doesn't arrive in two pieces.
    tmux capture-pane -p -J -S -5000
  elif [[ -n $ZELLIJ ]]; then
    # No --path means STDOUT; no --ansi means plain text.
    zellij action dump-screen --full
  elif [[ -n $KITTY_WINDOW_ID ]] && command -v kitten >/dev/null 2>&1; then
    # kitty needs no multiplexer: remote control hands back the scrollback.
    # Requires allow_remote_control (set in home/kitty-thinkpad.nix).
    # Use command -v (not zsh $+commands) so shellcheck stays happy.
    kitten @ get-text --extent all --ansi=false 2>/dev/null
  else
    return 1
  fi
}

__pick_from_screen() {
  local mode=$1 dump sel cleaned
  if ! dump=$(__screen_dump) || [[ -z $dump ]]; then
    zle -M "pick-from-screen: needs tmux, zellij or kitty — nothing else hands the scrollback back"
    return 1
  fi

  if [[ $mode == words ]]; then
    # Split on anything unprintable-or-space, drop 1-char noise, dedup, then
    # reverse so the most recent output is at the top of the picker.
    sel=$(print -r -- "$dump" | tr -cs '[:graph:]' '\n' |
      awk 'length >= 2 && !seen[$0]++' | tac |
      fzf --height 40% --reverse --multi --prompt='screen word> ')
  else
    sel=$(print -r -- "$dump" | awk 'NF && !seen[$0]++' | tac |
      fzf --height 40% --reverse --multi --prompt='screen line> ')
  fi

  # fzf exits non-zero when cancelled; either way redraw the prompt it ate.
  if [[ -n $sel ]]; then
    # Multi-select joins with spaces; strip fzf's trailing newline first.
    # Unnested expansions (shellcheck SC2299; bash-compatible form).
    cleaned=${sel%$'\n'}
    cleaned=${cleaned//$'\n'/ }
    LBUFFER+=$cleaned
  fi
  zle reset-prompt
}

_pick_word_from_screen() { __pick_from_screen words; }
_pick_line_from_screen() { __pick_from_screen lines; }
zle -N _pick_word_from_screen
zle -N _pick_line_from_screen
bindkey '^[v' _pick_word_from_screen
bindkey '^[V' _pick_line_from_screen
