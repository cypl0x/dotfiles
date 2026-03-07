#!/usr/bin/env zsh
# Zsh-specific functions

# ============================================================================
# NixOS / Nix Functions
# ============================================================================

# Detect dotfiles directory (default to ~/dotfiles if DOTFILES_DIR not set)
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# Full update: flake update + rebuild
nixup() {
  local hostname=$(hostname)
  cd "$DOTFILES_DIR"
  nix flake update
  sudo nixos-rebuild switch --flake ".#$hostname"
}

# Update a specific flake input + rebuild
nixup-input() {
  if [ -z "$1" ]; then
    echo "Usage: nixup-input <input-name>"
    echo "Example: nixup-input nixpkgs"
    return 1
  fi
  local hostname=$(hostname)
  cd "$DOTFILES_DIR"
  nix flake lock --update-input "$1"
  sudo nixos-rebuild switch --flake ".#$hostname"
}

# Quick flake check (statix + nix flake check)
nixcheck() {
  cd "$DOTFILES_DIR"
  echo "Running flake check..."
  nix flake check
  echo "Running statix check..."
  statix check
}

nixshow() {
  cd "$DOTFILES_DIR"
  nix flake show
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
  cd "$DOTFILES_DIR"
  nixos-rebuild switch \
    --flake ".#inari" \
    --build-host root@65.109.108.233 \
    --target-host root@65.109.108.233
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
