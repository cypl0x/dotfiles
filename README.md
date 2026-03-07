# NixOS Dotfiles Configuration

A flake-based NixOS configuration repository for the `inari` server and the `thinkpad` laptop.

## Repository Structure

```
dotfiles/
├── flake.nix                      # Main flake configuration
├── hosts/
│   ├── inari/
│   │   ├── default.nix            # System configuration
│   │   ├── hardware.nix
│   │   ├── services.nix           # Host-specific services
│   │   └── nextcloud.nix          # Nextcloud site config
│   └── thinkpad/
│       ├── default.nix            # Laptop configuration
│       └── hardware.nix
├── home/
│   ├── shellfishrc                # ShellFish iOS integration
│   ├── shell-aliases.sh           # 100+ aliases and functions
│   └── shell-completions.sh       # Auto-loading completions
├── web/
│   └── static/                    # Static website content
│       ├── index.html
│       └── 404.html
└── modules/                       # Custom NixOS modules (future use)
```

## Features

- **Flake-based configuration** for reproducible builds
- **Zsh** as default shell with Oh My Zsh
- **FZF integration** for fuzzy finding with tmux support
- **Syntax highlighting** and **auto-suggestions** in zsh
- **Smart completions** for 40+ CLI tools (auto-loaded when installed)
- **Bat as PAGER** for syntax-highlighted man pages
- **Comprehensive cheatsheet tools**: cheat, tldr, eg, howdoi, navi
- **Git configuration** with custom user settings
- **Tailscale** configured as exit node
- **Tor relay** (non-exit) named "cypl0x"
- **SSH hardening** with ShellFish iOS support
- **Nginx web server** with HTTPS and multiple domains
- **Development tools**: vim, emacs, ripgrep, bat, fzf

## Migrating from Global NixOS Config to Dotfiles Flake

If you're currently using `/etc/nixos/configuration.nix` (non-flake), here's how to migrate:

### Step 1: Backup Current Configuration

```bash
# Backup your current working configuration
sudo cp -r /etc/nixos /etc/nixos.backup
```

### Step 2: Clone or Initialize Dotfiles Repo

```bash
# If starting fresh
cd /root
git clone <your-repo-url> dotfiles

# Or initialize this existing directory
cd ~/dotfiles
git init
git add .
git commit -m "Initial commit: NixOS flake configuration"
```

### Step 3: Test the Flake Configuration

Before switching, test that the flake builds correctly:

```bash
cd ~/dotfiles
nix flake check
```

### Step 4: Switch to Flake Configuration

```bash
# Rebuild using the flake
sudo nixos-rebuild switch --flake ~/dotfiles#inari

# Or if you're in the dotfiles directory
cd ~/dotfiles
sudo nixos-rebuild switch --flake .#inari
```

### Step 5: Update Boot Loader (Optional)

To make the flake the default configuration for future boots:

```bash
# Symlink the flake to /etc/nixos (optional for convenience)
sudo ln -sf ~/dotfiles/flake.nix /etc/nixos/flake.nix
```

### Step 6: Verify the Migration

```bash
# Check that the system is using the new configuration
nixos-version
systemctl status
```

## Common NixOS Operations

### Rebuilding the System

```bash
# Rebuild and switch to new configuration
sudo nixos-rebuild switch --flake ~/dotfiles#inari

# Rebuild and switch, showing detailed build logs
sudo nixos-rebuild switch --flake ~/dotfiles#inari --show-trace

# Build but don't activate (test configuration)
sudo nixos-rebuild build --flake ~/dotfiles#inari

# Rebuild and activate on next boot (safer for remote systems)
sudo nixos-rebuild boot --flake ~/dotfiles#inari
```

### Updating the System

```bash
# Update flake inputs (nixpkgs, etc.)
cd ~/dotfiles
nix flake update

# Update and rebuild in one go
cd ~/dotfiles
nix flake update && sudo nixos-rebuild switch --flake .#inari

# Update only specific input
nix flake lock --update-input nixpkgs
```

### Upgrading Packages

```bash
# Update flake.lock and rebuild
cd ~/dotfiles
nix flake update
sudo nixos-rebuild switch --flake .#inari

# Clean up old generations to free space
sudo nix-collect-garbage --delete-older-than 30d

# Clean up everything except current generation
sudo nix-collect-garbage -d
```

### Rolling Back

```bash
# List all system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Switch to specific generation
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 42
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### Checking and Optimizing

```bash
# Check flake for errors
cd ~/dotfiles
nix flake check

# Show flake info
nix flake show

# Show flake metadata
nix flake metadata

# Optimize nix store (deduplicate files)
sudo nix-store --optimise

# Verify nix store integrity
sudo nix-store --verify --check-contents
```

## Helpful NixOS Shell Functions & Aliases

Add these to your shell configuration for easier NixOS management. They're already included in this flake's zsh configuration.

### Rebuild Aliases

```bash
# Quick rebuild from dotfiles
alias nrs='sudo nixos-rebuild switch --flake ~/dotfiles#inari'
alias nrb='sudo nixos-rebuild boot --flake ~/dotfiles#inari'
alias nrt='sudo nixos-rebuild test --flake ~/dotfiles#inari'

# Rebuild with verbose output
alias nrsv='sudo nixos-rebuild switch --flake ~/dotfiles#inari --show-trace'

# Build without switching (test configuration)
alias nrbs='sudo nixos-rebuild build --flake ~/dotfiles#inari'
```

### Update & Upgrade Functions

```bash
# Update flake and rebuild
nixup() {
  cd ~/dotfiles
  nix flake update
  sudo nixos-rebuild switch --flake .#inari
}

# Update specific input
nixup-input() {
  if [ -z "$1" ]; then
    echo "Usage: nixup-input <input-name>"
    echo "Example: nixup-input nixpkgs"
    return 1
  fi
  cd ~/dotfiles
  nix flake lock --update-input "$1"
  sudo nixos-rebuild switch --flake .#inari
}
```

### Cleanup & Maintenance

```bash
# Clean old generations
nixclean() {
  local days=${1:-30}
  echo "Deleting generations older than $days days..."
  sudo nix-collect-garbage --delete-older-than ${days}d
  echo "Optimizing store..."
  sudo nix-store --optimise
}

# Full cleanup (delete all old generations)
nixclean-all() {
  echo "Warning: This will delete all old generations!"
  read -p "Continue? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo nix-collect-garbage -d
    sudo nix-store --optimise
  fi
}
```

### System Information

```bash
# Show current generation
nixgen() {
  sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
}

# Show disk usage
nixdu() {
  echo "=== Nix Store Usage ==="
  du -sh /nix/store
  echo ""
  echo "=== Generation Sizes ==="
  sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | \
    while read -r gen _; do
      if [[ $gen =~ ^[0-9]+$ ]]; then
        du -sh "/nix/var/nix/profiles/system-${gen}-link" 2>/dev/null
      fi
    done
}

# Show what changed between generations
nixdiff() {
  local gen1=${1:-$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -2 | head -1 | awk '{print $1}')}
  local gen2=${2:-$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -1 | awk '{print $1}')}

  nix store diff-closures \
    /nix/var/nix/profiles/system-${gen1}-link \
    /nix/var/nix/profiles/system-${gen2}-link
}
```

### Search & Explore

```bash
# Search for packages
nixsearch() {
  if [ -z "$1" ]; then
    echo "Usage: nixsearch <package-name>"
    return 1
  fi
  nix search nixpkgs "$1"
}

# Show package info
nixinfo() {
  if [ -z "$1" ]; then
    echo "Usage: nixinfo <package-name>"
    return 1
  fi
  nix eval nixpkgs#$1.meta.description
  nix eval nixpkgs#$1.meta.homepage
}

# Show what's in current system
nixlist() {
  nix-store -q --references /run/current-system/sw | \
    grep -v '\.drv$' | \
    sed 's|/nix/store/[a-z0-9]\{32\}-||' | \
    sort | \
    bat
}
```

### Development Helpers

```bash
# Enter a development shell with packages
nixshell() {
  nix-shell -p "$@"
}

# Run a command with packages available
nixrun() {
  if [ -z "$1" ]; then
    echo "Usage: nixrun <package> [command]"
    echo "Example: nixrun hello hello"
    return 1
  fi
  local pkg=$1
  shift
  nix run nixpkgs#$pkg -- "$@"
}

# Try a package without installing
nixtry() {
  if [ -z "$1" ]; then
    echo "Usage: nixtry <package>"
    return 1
  fi
  nix shell nixpkgs#$1
}
```

### Flake Management

```bash
# Quick flake check
nixcheck() {
  cd ~/dotfiles
  nix flake check
}

# Show flake outputs
nixshow() {
  cd ~/dotfiles
  nix flake show
}

# Format nix files
nixfmt() {
  find ~/dotfiles -name '*.nix' -type f -exec nixfmt {} \;
}
```

## Usage Examples

### Example 1: Daily System Update

```bash
# Update all flake inputs and rebuild
nixup

# Or manually:
cd ~/dotfiles
nix flake update
nrs  # (alias for nixos-rebuild switch)
```

### Example 2: Adding a New Package

1. Edit `hosts/inari/default.nix`
2. Add package to `environment.systemPackages`
3. Rebuild:

```bash
cd ~/dotfiles
nrs  # or: sudo nixos-rebuild switch --flake .#inari
```

### Example 3: Testing Configuration Before Applying

```bash
# Build configuration without activating
nrbs  # or: sudo nixos-rebuild build --flake ~/dotfiles#inari

# If build succeeds, then switch
nrs
```

### Example 4: Rollback After Bad Update

```bash
# See all generations
nixgen

# Rollback to previous
sudo nixos-rebuild switch --rollback

# Or switch to specific generation
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 42
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### Example 5: Cleanup Old Generations

```bash
# Delete generations older than 14 days
nixclean 14

# Or delete all old generations (keep only current)
nixclean-all
```

### Example 6: Search and Install Package

```bash
# Search for a package
nixsearch python3

# Add it to the host configuration, then rebuild
nrs
```

### Example 7: Try Package Without Installing

```bash
# Temporarily try a package
nixtry cowsay
cowsay "Hello from NixOS!"
exit  # Package is gone after exiting shell

# Or run once
nixrun cowsay cowsay "One-time use"
```

### Example 8: Compare What Changed

```bash
# See what changed in last update
nixdiff

# Compare specific generations
nixdiff 41 42
```

## Cheatsheet Tools Usage

This configuration includes multiple cheatsheet tools:

```bash
# Quick examples (concise)
tldr tar

# Detailed examples
eg tar

# Community cheatsheets
cheat tar
cheat -l  # list all available cheatsheets

# Stack Overflow answers
howdoi extract tar.gz file
howdoi --all  # show multiple answers

# Interactive cheatsheet with fzf
navi
```

## Git Workflow for Dotfiles

```bash
cd ~/dotfiles

# Make changes to configuration files
vim hosts/inari/default.nix

# Test the changes
nrbs  # build without switching

# Apply changes
nrs

# Commit changes
git add .
git commit -m "Add new package: <package-name>"
git push
```

## Troubleshooting

### Configuration fails to build

```bash
# Check for syntax errors
cd ~/dotfiles
nix flake check

# Build with detailed error messages
sudo nixos-rebuild switch --flake .#inari --show-trace
```

### System won't boot after update

1. At boot, select previous generation from bootloader
2. Once booted, rollback:
   ```bash
   sudo nixos-rebuild switch --rollback
   ```

### Out of disk space

```bash
# Clean old generations and optimize
nixclean-all

# Check what's using space
nixdu
df -h /nix
```

### Flake inputs are outdated

```bash
# Update all inputs
cd ~/dotfiles
nix flake update

# Or update just nixpkgs
nix flake lock --update-input nixpkgs
```

## Shell Aliases & Functions

This configuration includes 100+ helpful aliases and functions.

**Quick highlights:**

```bash
# Modern ls with icons (eza)
ll              # Long list with git status
la              # Long list with hidden files
lt2             # Tree view 2 levels deep

# Quick navigation
...             # Go up 2 directories
mkcd dir        # Make directory and cd into it

# Git shortcuts
gaa && gcm "message" && gp    # Add all, commit, push

# System info
sysinfo         # Show system information
topcpu          # Top CPU processes
dusort          # Directory sizes sorted

# Utilities
extract file.tar.gz     # Extract any archive
backup config.nix       # Create timestamped backup
weather London          # Quick weather
genpass 32             # Generate password
serve 8000             # Start HTTP server
```

## Shell Completions

Smart tab completions for 40+ CLI tools are automatically loaded when the tools are installed.

**Currently active:**
- tailscale, nix, git, fzf, tmux, bat, eza, ripgrep

**Auto-enabled when installed:**
- kubectl, helm, docker, terraform, aws, gh, rustup, poetry, and many more

```bash
# Examples
tailscale <TAB>     # Complete subcommands
kubectl get <TAB>   # Complete resources
git checkout <TAB>  # Complete branches
nix shell nixpkgs#<TAB>  # Complete packages
```

## Nginx Web Server

Hardened Nginx configuration with HTTPS via Let's Encrypt.

**Domains**:
- **Main sites**: wolfhard.net, wolfhard.dev, wolfhard.tech (+ www subdomains)

**Features**:
- **HTTPS with Let's Encrypt** (automatic certificate management)
- **HTTP → HTTPS redirect** (all traffic encrypted)
- **Security headers** (XSS, clickjacking protection, CSP)
- **Static asset caching** (1 year for images/fonts/css/js)
- **TLS 1.2/1.3** with modern cipher suites
- Custom error pages, Gzip compression

**Quick start**:

```bash
# Access via HTTPS
curl -I https://wolfhard.net

# HTTP auto-redirects to HTTPS
curl -I http://wolfhard.net

# View logs
tail -f /var/log/nginx/wolfhard.net.access.log

# Update content
vim ~/dotfiles/web/static/index.html
nrs  # Rebuild to deploy changes
```

**Note**: DNS must point to your server before first rebuild for SSL certificates to work.

## User Management

Quick example:

```nix
# Edit modules/users/*.nix and enable user definitions
# Then rebuild and set passwords:
sudo nixos-rebuild switch --flake .#inari
sudo passwd alice
sudo passwd bob
```

## Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Home Manager](https://github.com/nix-community/home-manager) (for user-level dotfiles)
- [NixOS Search](https://search.nixos.org/packages)

## License

MIT

## Author

Wolfhard Prell (mail@wolfhard.net)
