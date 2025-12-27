# System Architecture

This document describes the architecture and organization of the NixOS dotfiles configuration.

## Overview

This is a NixOS flake-based configuration for a homelab server providing:
- Static website hosting across multiple domains
- Documentation hosting
- Monitoring and system management
- Secure remote access via SSH and Tailscale
- Tor relay services

## Repository Structure

```
dotfiles/
├── flake.nix                 # Flake entry point and outputs
├── flake.lock               # Locked dependency versions
├── Makefile                 # Build and deployment shortcuts
│
├── hosts/                   # Host-specific configurations
│   └── homelab/
│       ├── default.nix      # Main host configuration
│       ├── hardware.nix     # Hardware-specific settings
│       └── services.nix     # Host-specific services (nginx virtualhosts)
│
├── modules/                 # Reusable NixOS modules
│   ├── system/              # System-level modules
│   │   ├── packages.nix     # System-wide packages
│   │   ├── shell.nix        # Shell configuration (zsh, bash)
│   │   ├── security.nix     # SSH and security settings
│   │   ├── monitoring.nix   # Monitoring services (netdata)
│   │   └── assertions.nix   # Configuration validation
│   │
│   ├── services/            # Service modules
│   │   ├── nginx.nix        # Nginx base configuration
│   │   ├── tailscale.nix    # Tailscale VPN
│   │   └── tor.nix          # Tor relay
│   │
│   ├── users/               # User account modules
│   │   ├── root.nix         # Root user configuration
│   │   ├── cypl0x.nix       # Primary user
│   │   └── wap.nix          # Work account
│   │
│   └── web/                 # Web-related helpers
│       └── nginx-helpers.nix # Reusable nginx functions
│
├── home/                    # Home Manager configurations
│   ├── common.nix           # Shared home-manager config
│   ├── cypl0x.nix           # User-specific config
│   ├── wap.nix              # Work user config
│   ├── root.nix             # Root user home config
│   └── shell/               # Shell configurations
│       ├── zsh/             # Zsh specific files
│       ├── starship.toml    # Starship prompt config
│       └── tmux.conf        # Tmux configuration
│
├── web/                     # Web content and builders
│   ├── docs.nix             # Documentation builder
│   ├── static/              # Static website files
│   └── docs/                # Documentation markdown
│
├── ssh-keys/                # SSH public keys
│   └── homelab.pub          # Server SSH key
│
└── docs/                    # Project documentation
    ├── DEPLOYMENT.md        # Deployment guide
    ├── ARCHITECTURE.md      # This file
    └── NGINX.md             # Nginx documentation
```

## Module Organization

### System Modules (`modules/system/`)

**Purpose:** System-level configuration that affects all users

- **packages.nix**: Defines system-wide packages (CLI tools, development tools, AI tools)
- **shell.nix**: Configures default shell (zsh) and shell environment
- **security.nix**: SSH daemon configuration, security policies
- **monitoring.nix**: System monitoring services (netdata)
- **assertions.nix**: Validates configuration correctness at build time

### Service Modules (`modules/services/`)

**Purpose:** Individual service configurations

- **nginx.nix**: Base nginx configuration with security headers, ACME setup
- **tailscale.nix**: Tailscale VPN for secure remote access
- **tor.nix**: Tor relay configuration

### User Modules (`modules/users/`)

**Purpose:** User account definitions

- Defines user accounts with home directories
- Configures SSH authorized keys
- Sets user-specific settings

### Web Modules (`modules/web/`)

**Purpose:** Web-related helper functions and configurations

- **nginx-helpers.nix**: Provides reusable functions for nginx configuration
  - `mkVirtualHost`: Creates virtualhost with common settings
  - `mkMultiDomainVirtualHosts`: Generates virtualhosts for multiple TLDs
  - Security header templates (strict and permissive CSP)
  - Caching configuration helpers

## Home Manager Integration

Home Manager manages user-specific configurations:

### Common Configuration (`home/common.nix`)

Shared across all users:
- Git configuration
- Shell setup (zsh, starship, tmux)
- Editor preferences
- Shell aliases and functions

### User-Specific Configuration

Each user imports `common.nix` and overrides as needed:
- **cypl0x.nix**: Primary user with personal git config
- **wap.nix**: Work account with work email
- **root.nix**: Root user with minimal config

## Data Flow

### Build Process

```
flake.nix
    │
    ├─→ nixosConfigurations.homelab
    │       │
    │       ├─→ hosts/homelab/default.nix
    │       │       │
    │       │       ├─→ System Modules (modules/system/*)
    │       │       ├─→ Service Modules (modules/services/*)
    │       │       ├─→ User Modules (modules/users/*)
    │       │       └─→ hosts/homelab/services.nix
    │       │
    │       └─→ home-manager.nixosModules.home-manager
    │               │
    │               ├─→ home/cypl0x.nix
    │               ├─→ home/wap.nix
    │               └─→ home/root.nix
    │
    └─→ Checks (statix, deadnix, formatting)
```

### Nginx Configuration Flow

```
modules/services/nginx.nix (base config + security headers)
    │
    └─→ hosts/homelab/services.nix
            │
            ├─→ imports modules/web/nginx-helpers.nix
            │
            └─→ generates virtualHosts using:
                    ├─→ mkMultiDomainVirtualHosts (main domains)
                    └─→ mkMultiDomainVirtualHosts (docs subdomains)
```

## Design Patterns

### 1. Module Composition

Modules are composed hierarchically:
- Base configuration in `modules/`
- Host-specific overrides in `hosts/`
- User-specific in `home/`

### 2. DRY (Don't Repeat Yourself)

Using helper functions to avoid duplication:
- Nginx helpers generate multiple similar virtualhosts
- Common home-manager config shared across users
- Reusable security header templates

### 3. Separation of Concerns

Each module has a single responsibility:
- Services configured independently
- System and user configuration separated
- Web content separate from web server config

### 4. Configuration Validation

Assertions module validates:
- Required services are configured correctly
- Dependencies are met (e.g., nginx → ACME)
- Security best practices are followed

## Key Technologies

### NixOS Flakes

- **Declarative**: Entire system described in Nix code
- **Reproducible**: Locked dependencies ensure consistent builds
- **Atomic**: Updates are atomic, easy to rollback
- **Composable**: Modular design allows easy reuse

### Home Manager

- **User Environment**: Manages dotfiles and user packages
- **Unified Configuration**: Same language (Nix) for system and user config
- **Version Control**: User config tracked in git

### Services

- **Nginx**: High-performance web server with automatic SSL
- **ACME**: Automatic SSL certificate management
- **Tailscale**: Mesh VPN for secure access
- **Netdata**: Real-time performance monitoring
- **Tor**: Privacy-focused relay node

## Security Architecture

### Layers of Security

1. **Network Layer**
   - Firewall with minimal open ports (22, 80, 443, 9001)
   - Tailscale for secure remote access

2. **Application Layer**
   - Nginx with security headers (CSP, HSTS, etc.)
   - Strict Content Security Policy
   - SSL/TLS enforcement

3. **Access Control**
   - SSH key-only authentication
   - Root login restricted
   - Separate user accounts

4. **Monitoring**
   - Netdata for performance monitoring
   - Systemd journal for centralized logging

### Security Headers

Applied globally via `modules/services/nginx.nix`:
- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- Strict-Transport-Security (HSTS)
- Content-Security-Policy (CSP)
- Permissions-Policy
- Cross-Origin policies

## Extensibility

### Adding a New Service

1. Create module in `modules/services/newservice.nix`
2. Import in `hosts/homelab/default.nix`
3. Configure service-specific settings
4. Add firewall rules if needed
5. Add assertions for validation

Example:
```nix
# modules/services/newservice.nix
{config, lib, ...}: {
  services.newservice = {
    enable = true;
    # ... configuration
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```

### Adding a New User

1. Create user module in `modules/users/newuser.nix`
2. Create home config in `home/newuser.nix`
3. Import both in `hosts/homelab/default.nix` and `flake.nix`
4. Add SSH key to `ssh-keys/`

### Adding a New Domain

Using the nginx helpers:

```nix
# In hosts/homelab/services.nix
services.nginx.virtualHosts =
  nginxHelpers.mkMultiDomainVirtualHosts {
    name = "newdomain";
    tlds = ["com" "net" "org"];
    root = "/var/www/newdomain";
    enableCaching = true;
  };
```

## Build and Deployment

### Local Build

```bash
make build      # Build configuration
make switch     # Build and activate
make vm         # Test in virtual machine
```

### Remote Deployment

```bash
nixos-rebuild switch --flake .#homelab \
  --target-host user@host \
  --build-host localhost
```

### CI/CD Integration

The flake includes checks for:
- **statix**: Nix linting
- **deadnix**: Dead code detection
- **alejandra**: Code formatting

Run via:
```bash
nix flake check
```

## Performance Considerations

### Build Optimization

- Flake inputs locked for consistent builds
- Local builds cached by Nix
- Binary cache for common packages

### Runtime Optimization

- Nginx caching for static assets (1 year for images, 1 hour for HTML)
- Gzip compression enabled
- Optimized buffer sizes and timeouts

### Resource Usage

Typical resource usage:
- RAM: ~512MB baseline + services
- Disk: ~5GB for NixOS + packages
- CPU: Minimal when idle

## Monitoring and Observability

### Metrics

- **Netdata**: Real-time performance graphs
  - CPU, memory, disk usage
  - Network traffic
  - Service health

### Logs

- **journalctl**: Centralized logging
  - Service-specific logs: `journalctl -u nginx`
  - System logs: `journalctl -xe`
  - Follow mode: `journalctl -f`

### Alerting

Currently manual monitoring. Consider adding:
- Email notifications for service failures
- Disk space alerts
- Certificate expiry warnings

## Future Improvements

Potential enhancements:

1. **Automated backups**: Implement automatic backup to remote storage
2. **Secret management**: Use agenix or sops-nix for secrets
3. **CI/CD**: Automatic deployment on git push
4. **Monitoring alerts**: Email/webhook notifications
5. **Additional services**: Database, container orchestration
6. **High availability**: Load balancing, failover
7. **Development environments**: Per-project dev shells

## Related Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment procedures
- [SECURITY.md](../SECURITY.md) - Security policies and procedures
- [NGINX.md](./NGINX.md) - Web server configuration
- [README.md](../README.md) - Quick start guide
