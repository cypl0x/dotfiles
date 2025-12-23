#!/usr/bin/env zsh
# Shell completions for various CLI tools
# This file sources/evaluates shell completions for tools that support them

# ============================================================================
# Helper function to check if command exists
# ============================================================================

_has_command() {
  command -v "$1" &>/dev/null
}

# ============================================================================
# Tailscale Completions
# ============================================================================

if _has_command tailscale; then
  # Tailscale provides built-in completion generation
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(tailscale completion zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(tailscale completion bash)"
  fi
fi

# ============================================================================
# Nix Completions
# ============================================================================

# Nix completions are usually handled by the NixOS module, but we can
# ensure they're loaded for interactive shells
if _has_command nix; then
  # Nix completions via zsh-completions (handled by NixOS)
  # Additional nix-specific completions are in fpath from NixOS config
  : # No additional action needed, handled by system
fi

# ============================================================================
# GitHub CLI (gh) Completions
# ============================================================================

if _has_command gh; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(gh completion -s zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(gh completion -s bash)"
  fi
fi

# ============================================================================
# Docker Completions
# ============================================================================

if _has_command docker; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Docker completions are usually in /usr/share/zsh/vendor-completions/
    # or provided by the docker package in NixOS
    : # Handled by docker package
  fi
fi

# ============================================================================
# Docker Compose Completions
# ============================================================================

if _has_command docker-compose; then
  if [[ -n "$ZSH_VERSION" ]]; then
    : # Handled by docker-compose package
  fi
fi

# ============================================================================
# Kubectl (Kubernetes) Completions
# ============================================================================

if _has_command kubectl; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(kubectl completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(kubectl completion bash)
  fi
fi

# ============================================================================
# Helm Completions
# ============================================================================

if _has_command helm; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(helm completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(helm completion bash)
  fi
fi

# ============================================================================
# Terraform Completions
# ============================================================================

if _has_command terraform; then
  if [[ -n "$ZSH_VERSION" ]]; then
    autoload -U +X bashcompinit && bashcompinit
    complete -o nospace -C $(which terraform) terraform
  fi
fi

# ============================================================================
# AWS CLI Completions
# ============================================================================

if _has_command aws; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # AWS CLI v2 has built-in completion
    complete -C aws_completer aws
  fi
fi

# ============================================================================
# Azure CLI Completions
# ============================================================================

if _has_command az; then
  if [[ -n "$ZSH_VERSION" ]]; then
    autoload -U +X bashcompinit && bashcompinit
    source $(az --completion)
  fi
fi

# ============================================================================
# Google Cloud SDK Completions
# ============================================================================

if _has_command gcloud; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # gcloud completion is typically in the SDK path
    if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then
      source "$HOME/google-cloud-sdk/completion.zsh.inc"
    fi
  fi
fi

# ============================================================================
# Rustup Completions
# ============================================================================

if _has_command rustup; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(rustup completions zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(rustup completions bash)"
  fi
fi

# ============================================================================
# Cargo Completions
# ============================================================================

if _has_command cargo; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Cargo completions are usually provided by rustup or the rust package
    : # Handled by rust package
  fi
fi

# ============================================================================
# Poetry (Python) Completions
# ============================================================================

if _has_command poetry; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(poetry completions zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(poetry completions bash)"
  fi
fi

# ============================================================================
# Pipenv Completions
# ============================================================================

if _has_command pipenv; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(_PIPENV_COMPLETE=zsh_source pipenv)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(_PIPENV_COMPLETE=bash_source pipenv)"
  fi
fi

# ============================================================================
# Node Version Manager (nvm) Completions
# ============================================================================

if _has_command nvm; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # nvm completions are usually loaded with nvm itself
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
  fi
fi

# ============================================================================
# Deno Completions
# ============================================================================

if _has_command deno; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(deno completions zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(deno completions bash)"
  fi
fi

# ============================================================================
# Bun Completions
# ============================================================================

if _has_command bun; then
  if [[ -n "$ZSH_VERSION" ]]; then
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
  fi
fi

# ============================================================================
# Chezmoi Completions
# ============================================================================

if _has_command chezmoi; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(chezmoi completion zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(chezmoi completion bash)"
  fi
fi

# ============================================================================
# Minikube Completions
# ============================================================================

if _has_command minikube; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(minikube completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(minikube completion bash)
  fi
fi

# ============================================================================
# Kind (Kubernetes in Docker) Completions
# ============================================================================

if _has_command kind; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(kind completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(kind completion bash)
  fi
fi

# ============================================================================
# Podman Completions
# ============================================================================

if _has_command podman; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Podman completions are usually provided by the package
    : # Handled by podman package
  fi
fi

# ============================================================================
# Skopeo Completions
# ============================================================================

if _has_command skopeo; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Skopeo completions are usually provided by the package
    : # Handled by skopeo package
  fi
fi

# ============================================================================
# Vagrant Completions
# ============================================================================

if _has_command vagrant; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Vagrant completions are usually provided by the package
    : # Handled by vagrant package
  fi
fi

# ============================================================================
# Ansible Completions
# ============================================================================

if _has_command ansible; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Ansible completions are usually provided by the package
    : # Handled by ansible package
  fi
fi

# ============================================================================
# Hugo Completions
# ============================================================================

if _has_command hugo; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(hugo completion zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(hugo completion bash)"
  fi
fi

# ============================================================================
# Flux (GitOps) Completions
# ============================================================================

if _has_command flux; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(flux completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(flux completion bash)
  fi
fi

# ============================================================================
# ArgoCD Completions
# ============================================================================

if _has_command argocd; then
  if [[ -n "$ZSH_VERSION" ]]; then
    source <(argocd completion zsh)
  elif [[ -n "$BASH_VERSION" ]]; then
    source <(argocd completion bash)
  fi
fi

# ============================================================================
# Starship Prompt Completions
# ============================================================================

if _has_command starship; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(starship completions zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(starship completions bash)"
  fi
fi

# ============================================================================
# Direnv Completions
# ============================================================================

if _has_command direnv; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(direnv hook zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(direnv hook bash)"
  fi
fi

# ============================================================================
# Zoxide (better cd) Completions
# ============================================================================

if _has_command zoxide; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(zoxide init zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(zoxide init bash)"
  fi
fi

# ============================================================================
# Atuin (shell history) Completions
# ============================================================================

if _has_command atuin; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(atuin init zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(atuin init bash)"
  fi
fi

# ============================================================================
# Tmuxinator Completions
# ============================================================================

if _has_command tmuxinator; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Tmuxinator completions are usually provided by the package
    : # Handled by tmuxinator package
  fi
fi

# ============================================================================
# Just (command runner) Completions
# ============================================================================

if _has_command just; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(just --completions zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(just --completions bash)"
  fi
fi

# ============================================================================
# Bat Completions
# ============================================================================

if _has_command bat; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Bat completions are usually provided by the package
    : # Handled by bat package in NixOS
  fi
fi

# ============================================================================
# Ripgrep Completions
# ============================================================================

if _has_command rg; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Ripgrep completions are usually provided by the package
    : # Handled by ripgrep package in NixOS
  fi
fi

# ============================================================================
# Eza Completions
# ============================================================================

if _has_command eza; then
  if [[ -n "$ZSH_VERSION" ]]; then
    # Eza completions are usually provided by the package
    : # Handled by eza package in NixOS
  fi
fi

# ============================================================================
# FZF Completions
# ============================================================================

if _has_command fzf; then
  # FZF completions are loaded in the main zsh config
  # This is here for reference only
  : # Handled in main zsh configuration
fi

# ============================================================================
# Git Completions
# ============================================================================

if _has_command git; then
  # Git completions are handled by oh-my-zsh git plugin
  # This is here for reference only
  : # Handled by oh-my-zsh git plugin
fi

# ============================================================================
# Tmux Completions
# ============================================================================

if _has_command tmux; then
  # Tmux completions are handled by oh-my-zsh tmux plugin
  # This is here for reference only
  : # Handled by oh-my-zsh tmux plugin
fi

# ============================================================================
# Completion Settings
# ============================================================================

# Make completions case-insensitive
if [[ -n "$ZSH_VERSION" ]]; then
  zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

  # Use menu selection for completions
  zstyle ':completion:*' menu select

  # Group completions by type
  zstyle ':completion:*' group-name ''

  # Description format
  zstyle ':completion:*:descriptions' format '%B%d%b'

  # Warnings format
  zstyle ':completion:*:warnings' format 'No matches for: %d'

  # Enable completion caching
  zstyle ':completion:*' use-cache on
  zstyle ':completion:*' cache-path ~/.zsh/cache
fi

# ============================================================================
# Debugging
# ============================================================================

# Uncomment to debug which completions are being loaded
# echo "Shell completions loaded for: tailscale, kubectl, helm, etc."
