# Shell Completions Reference

This dotfiles configuration automatically loads shell completions for various CLI tools.

## How It Works

The `home/shell-completions.sh` file is sourced during shell initialization and automatically enables completions for installed tools. It checks if each command exists before attempting to load its completions, so there's no need to modify the file when installing or removing packages.

## Currently Supported Tools

### System & Package Management

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **nix** | ✅ Active | Built-in | NixOS module handles completions |
| **nixos-rebuild** | ✅ Active | Built-in | Part of NixOS system |

### Networking & VPN

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **tailscale** | ✅ Active | Dynamic | `tailscale completion zsh` |

### Version Control

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **git** | ✅ Active | Plugin | Oh-My-Zsh git plugin |
| **gh** | 📦 Optional | Dynamic | GitHub CLI - `gh completion` |

### Container & Orchestration

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **docker** | 📦 Optional | Package | Docker completions from package |
| **docker-compose** | 📦 Optional | Package | Docker Compose completions |
| **kubectl** | 📦 Optional | Dynamic | `kubectl completion zsh` |
| **helm** | 📦 Optional | Dynamic | `helm completion zsh` |
| **minikube** | 📦 Optional | Dynamic | `minikube completion zsh` |
| **kind** | 📦 Optional | Dynamic | `kind completion zsh` |
| **podman** | 📦 Optional | Package | Podman completions from package |

### Cloud Providers

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **aws** | 📦 Optional | Built-in | `complete -C aws_completer aws` |
| **az** | 📦 Optional | Dynamic | Azure CLI completions |
| **gcloud** | 📦 Optional | SDK | Google Cloud SDK completions |

### Infrastructure as Code

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **terraform** | 📦 Optional | Built-in | Terraform built-in completions |
| **ansible** | 📦 Optional | Package | Ansible completions from package |
| **vagrant** | 📦 Optional | Package | Vagrant completions from package |

### GitOps & CD

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **flux** | 📦 Optional | Dynamic | `flux completion zsh` |
| **argocd** | 📦 Optional | Dynamic | `argocd completion zsh` |

### Programming Languages & Tools

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **rustup** | 📦 Optional | Dynamic | `rustup completions zsh` |
| **cargo** | 📦 Optional | Package | Cargo completions from package |
| **poetry** | 📦 Optional | Dynamic | `poetry completions zsh` |
| **pipenv** | 📦 Optional | Dynamic | Pipenv environment completions |
| **deno** | 📦 Optional | Dynamic | `deno completions zsh` |
| **bun** | 📦 Optional | Built-in | Bun completions from `~/.bun/_bun` |

### File Management & Shell Utilities

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **fzf** | ✅ Active | Plugin | Oh-My-Zsh fzf plugin |
| **tmux** | ✅ Active | Plugin | Oh-My-Zsh tmux plugin |
| **bat** | ✅ Active | Package | Bat completions from package |
| **eza** | ✅ Active | Package | Eza completions from package |
| **rg** (ripgrep) | ✅ Active | Package | Ripgrep completions from package |
| **direnv** | 📦 Optional | Hook | `direnv hook zsh` |
| **zoxide** | 📦 Optional | Hook | `zoxide init zsh` |
| **atuin** | 📦 Optional | Hook | `atuin init zsh` |
| **starship** | 📦 Optional | Dynamic | `starship completions zsh` |

### Configuration Management

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **chezmoi** | 📦 Optional | Dynamic | `chezmoi completion zsh` |

### Development Tools

| Tool | Status | Type | Notes |
|------|--------|------|-------|
| **hugo** | 📦 Optional | Dynamic | `hugo completion zsh` |
| **just** | 📦 Optional | Dynamic | `just --completions zsh` |

## Legend

- ✅ **Active**: Currently installed and completions enabled
- 📦 **Optional**: Will be enabled automatically if package is installed
- **Dynamic**: Completions generated at runtime via `eval` or `source <(command)`
- **Package**: Completions provided by the NixOS package
- **Built-in**: Completions built into the tool
- **Plugin**: Completions from Oh-My-Zsh or other plugin
- **Hook**: Shell integration hook (does more than just completions)

## How Completions Are Loaded

### 1. Dynamic Completions (Runtime Generation)

These tools generate their completions on-the-fly:

```bash
# Example: tailscale
eval "$(tailscale completion zsh)"

# Example: kubectl
source <(kubectl completion zsh)
```

**Pros:**
- Always up-to-date with tool version
- No separate completion file needed

**Cons:**
- Slight shell startup delay
- Requires tool to be installed

### 2. Package Completions (Pre-installed)

NixOS packages often include completion files that are automatically added to the completion path:

```bash
# Completions are in: /nix/store/.../share/zsh/site-functions/
# Automatically discovered by zsh
```

**Pros:**
- Fast (no generation needed)
- Part of package installation

### 3. Plugin Completions (Oh-My-Zsh)

Oh-My-Zsh plugins provide completions:

```nix
ohMyZsh = {
  enable = true;
  plugins = [ "git" "fzf" "tmux" ];
};
```

## Completion Features

### Case-Insensitive Matching

Completions are case-insensitive by default:

```bash
# All of these work:
git checkout MAIN
git checkout main
git checkout Main
```

### Menu Selection

Use arrow keys to navigate completion menu:

```bash
git checkout <TAB>
# Navigate with arrows, press Enter to select
```

### Completion Grouping

Completions are grouped by type:

```bash
docker <TAB>
# Shows: Commands, Management Commands, Options separately
```

### Completion Caching

Completions are cached for performance:

```bash
# Cache location: ~/.zsh/cache
# Clear cache: rm -rf ~/.zsh/cache
```

## Testing Completions

### Check if a completion is loaded

```bash
# Method 1: Try to complete
kubectl <TAB>

# Method 2: Check completion function
which _kubectl

# Method 3: List all completions
compaudit
```

### Debug completion issues

```bash
# Enable completion debugging
zstyle ':completion:*' verbose yes

# Test specific completion
_complete_help <command> <TAB>
```

### Rebuild completion cache

```bash
# Remove cache
rm -f ~/.zcompdump*

# Rebuild
compinit

# Or restart shell
exec zsh
```

## Adding New Completions

To add completions for a new tool:

1. **Check if the tool supports completions:**

```bash
<tool> completion --help
<tool> --help | grep -i completion
```

2. **Add to `home/shell-completions.sh`:**

```bash
if _has_command mytool; then
  if [[ -n "$ZSH_VERSION" ]]; then
    eval "$(mytool completion zsh)"
  elif [[ -n "$BASH_VERSION" ]]; then
    eval "$(mytool completion bash)"
  fi
fi
```

3. **Rebuild and test:**

```bash
nrs  # Rebuild system
exec zsh  # Restart shell
mytool <TAB>  # Test completion
```

## Performance Considerations

### Startup Time

Each dynamic completion adds ~10-50ms to shell startup. Current configuration:

- **Fast** (<5ms): Package completions (bat, eza, rg)
- **Medium** (5-20ms): Simple dynamic (tailscale, gh)
- **Slow** (20-50ms): Complex dynamic (kubectl, helm, terraform)

### Optimization Tips

1. **Use package completions when available** (fastest)
2. **Lazy-load expensive completions:**

```bash
# Instead of loading kubectl immediately:
kubectl() {
  unfunction kubectl
  source <(kubectl completion zsh)
  kubectl "$@"
}
```

3. **Cache completions to file:**

```bash
# Generate once
kubectl completion zsh > ~/.zsh/completions/_kubectl

# Add to fpath
fpath=(~/.zsh/completions $fpath)
```

## Common Issues

### Completions Not Working

**Problem:** Pressing TAB shows nothing

**Solutions:**

1. Check if tool is installed:
   ```bash
   which kubectl
   ```

2. Check if completion function exists:
   ```bash
   which _kubectl
   ```

3. Rebuild completion cache:
   ```bash
   rm ~/.zcompdump* && compinit
   ```

4. Check for errors:
   ```bash
   # Restart shell with verbose output
   zsh -xv
   ```

### Slow Shell Startup

**Problem:** Shell takes >1 second to start

**Solutions:**

1. Profile startup time:
   ```bash
   # Add to ~/.zshrc temporarily
   zmodload zsh/zprof
   # ... rest of config
   zprof  # At the end
   ```

2. Lazy-load expensive completions (see optimization tips)

3. Remove unused completions from `shell-completions.sh`

### Conflicting Completions

**Problem:** Completion behaves unexpectedly

**Solutions:**

1. Check completion order:
   ```bash
   echo $fpath
   ```

2. Check which completion is active:
   ```bash
   which _kubectl
   ```

3. Ensure completions load in correct order in `shell-completions.sh`

## Best Practices

1. **Only enable completions you use** - Remove unused tools from `shell-completions.sh`

2. **Prefer package completions** - Faster than dynamic generation

3. **Group similar tools** - Keep cloud tools together, containers together, etc.

4. **Document custom completions** - Add comments for non-standard setups

5. **Test after adding** - Always verify new completions work

6. **Profile startup time** - Keep it under 500ms

## Examples

### Using Completions

```bash
# Tailscale - complete subcommands
tailscale <TAB>
# Shows: up, down, status, netcheck, etc.

# Kubectl - complete resources
kubectl get <TAB>
# Shows: pods, services, deployments, etc.

# Git - complete branches
git checkout <TAB>
# Shows: main, develop, feature/xyz, etc.

# Docker - complete images
docker run <TAB>
# Shows: available images

# Nix - complete packages
nix shell nixpkgs#<TAB>
# Shows: available packages
```

### Custom Completion Example

Create a completion for a custom script:

```bash
# File: ~/.zsh/completions/_myscript
#compdef myscript

_myscript() {
  local -a commands
  commands=(
    'start:Start the service'
    'stop:Stop the service'
    'status:Check service status'
  )
  _describe 'command' commands
}

_myscript "$@"
```

Add to fpath:

```bash
fpath=(~/.zsh/completions $fpath)
compinit
```

## See Also

- [Zsh Completion System](http://zsh.sourceforge.net/Doc/Release/Completion-System.html)
- [Oh-My-Zsh Plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins)
- [Shell Aliases Guide](ALIASES.md)
- [Main README](../README.md)
