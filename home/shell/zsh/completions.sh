#!/usr/bin/env zsh
# Shell completions for CLI tools that ship their own generator.
#
# Sourced only from programs.zsh.initContent (home/common.nix), i.e. always by
# zsh — flake.nix excludes this file from shellcheck for that reason. It used to
# carry a `[[ -n "$BASH_VERSION" ]]` branch per tool that could never run, plus a
# section per tool whose completions the Nix package already drops into fpath
# (docker, cargo, bat, ripgrep, eza, git, tmux, podman, ...). Those did nothing
# but cost a `_has_command` fork each, so they are gone; anything installed via
# nixpkgs is already completed without help from this file.

# ============================================================================
# Cached completion generators
# ============================================================================
# Asking a tool to emit its completion script on every shell start is the
# single biggest cost in this file: gh ~80ms warm (~280ms cold, i.e. on the
# first shell after a rebuild), rustup ~68ms, tailscale ~22ms. Generate once,
# cache the script under ~/.cache/zsh/init, and source the cache thereafter —
# zprof puts all four installed generators at ~17ms total afterwards.
#
# Staleness key is the tool's *resolved* path, not its mtime: every Nix store
# binary has a 1970 mtime, so an mtime comparison would never see an upgrade,
# while the store path embeds the version and changes on every rebuild.
#
# A missing tool is a silent no-op, so these need no `command -v` guard.
#
# Usage: _cached_completion <cache-name> <command> [args...]
_cached_completion() {
  local name=$1
  shift
  [[ -n ${commands[$1]} ]] || return 0
  local bin=${commands[$1]:A}

  local dir="$HOME/.cache/zsh/init"
  local script="$dir/$name.zsh" stamp="$dir/$name.path"

  if [[ ! -s $script || ! -r $stamp || "$(<$stamp)" != "$bin" ]]; then
    mkdir -p "$dir"
    if ! "$@" >"$script.tmp" 2>/dev/null || [[ ! -s "$script.tmp" ]]; then
      rm -f "$script.tmp"
      return 1
    fi
    mv -f "$script.tmp" "$script"
    print -r -- "$bin" >"$stamp"
  fi

  source "$script"
}

_cached_completion tailscale tailscale completion zsh
_cached_completion gh        gh completion -s zsh
_cached_completion rustup    rustup completions zsh
_cached_completion starship  starship completions zsh
_cached_completion just      just --completions zsh
_cached_completion kubectl   kubectl completion zsh
_cached_completion helm      helm completion zsh
_cached_completion minikube  minikube completion zsh
_cached_completion kind      kind completion zsh
_cached_completion flux      flux completion zsh
_cached_completion argocd    argocd completion zsh
_cached_completion poetry    poetry completions zsh
_cached_completion deno      deno completions zsh
_cached_completion chezmoi   chezmoi completion zsh
_cached_completion hugo      hugo completion zsh

# ============================================================================
# Tools needing bash-style `complete -C` (no zsh generator available)
# ============================================================================

if [[ -n ${commands[terraform]} || -n ${commands[aws]} ]]; then
  autoload -U +X bashcompinit && bashcompinit
  [[ -n ${commands[terraform]} ]] &&
    complete -o nospace -C "${commands[terraform]}" terraform
  [[ -n ${commands[aws]} ]] && complete -C aws_completer aws
fi

# ============================================================================
# Tools shipping a completion file rather than a generator
# ============================================================================

# pipenv drives its generator through an env var, so it can't go through
# _cached_completion (which keys the cache on $1's resolved path).
[[ -n ${commands[pipenv]} ]] && eval "$(_PIPENV_COMPLETE=zsh_source pipenv)"

[[ -r "$HOME/google-cloud-sdk/completion.zsh.inc" ]] &&
  source "$HOME/google-cloud-sdk/completion.zsh.inc"

[[ -r "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# NOTE: direnv / zoxide / atuin init is NOT done here. home-manager already
# injects it into .zshrc via programs.{direnv,zoxide,atuin}.enableZshIntegration
# (see home/common.nix). Re-running the evals here double-bound their hooks
# (atuin Ctrl-R, direnv precmd) and slowed startup — so it was removed.

# ============================================================================
# Completion behaviour
# ============================================================================

# Cache slow completions (apt-style generators) on disk under ~/.cache/zsh.
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/zcompcache"

# Case-insensitive matching, grouped and labelled results.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:warnings' format 'No matches for: %d'

# fzf-tab tuning: eza preview when completing `cd`, group-switch with , / .
[[ -n ${commands[eza]} ]] &&
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:*' switch-group ',' '.'

# fzf-tab replaces zsh's own menu, which must therefore stay off. Keep this
# last: a stray `menu select` anywhere below wins and silently kills the fzf
# picker, which is exactly what used to happen at the bottom of this file.
zstyle ':completion:*' menu no
