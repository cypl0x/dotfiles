# Deployment Guide

This guide covers initial deployment, updates, and maintenance of the NixOS homelab configuration.

## Prerequisites

### Required
- NixOS installation (minimal or graphical)
- Git
- Network access
- SSH access (for remote deployment)

### Recommended
- Basic understanding of Nix/NixOS
- Familiarity with systemd
- DNS configured for your domains

## Initial Deployment

### 1. Fresh NixOS Installation

If starting from scratch:

```bash
# Boot from NixOS installation media
# Follow the installation guide: https://nixos.org/manual/nixos/stable/index.html#sec-installation

# Partition disk (example using GPT + UEFI)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 512MiB 100%
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 2 esp on

# Format partitions
mkfs.ext4 -L nixos /dev/sda1
mkfs.fat -F 32 -n boot /dev/sda2

# Mount filesystems
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# Generate initial configuration
nixos-generate-config --root /mnt
```

### 2. Clone Configuration Repository

```bash
# On the target system
cd /mnt/etc/nixos

# Backup generated config
mv configuration.nix configuration.nix.backup
mv hardware-configuration.nix hardware-configuration.nix.backup

# Clone your dotfiles repository
git clone https://github.com/yourusername/dotfiles.git .

# Copy hardware configuration
cp hardware-configuration.nix.backup hosts/homelab/hardware.nix
```

### 3. Configure SSH Keys

```bash
# Generate SSH keys for each user (do this on your local machine)
ssh-keygen -t ed25519 -C "cypl0x@homelab" -f ~/.ssh/id_ed25519_homelab

# Copy public key content
cat ~/.ssh/id_ed25519_homelab.pub

# Add to ssh-keys/homelab.pub in the repository
```

### 4. Initial Build and Installation

```bash
# From /mnt/etc/nixos
nixos-install --flake .#homelab

# Set root password when prompted
# Reboot
reboot
```

### 5. Post-Installation Setup

After reboot:

```bash
# Login as cypl0x
# The system should be configured based on your flake

# Verify services are running
sudo systemctl status nginx
sudo systemctl status sshd

# Test web server (should show default page)
curl http://localhost
```

## DNS Configuration

### Required DNS Records

For proper operation, configure these DNS records:

| Type  | Name               | Value              | TTL  |
|-------|--------------------|--------------------|------|
| A     | wolfhard.net       | YOUR_SERVER_IP     | 3600 |
| A     | wolfhard.dev       | YOUR_SERVER_IP     | 3600 |
| A     | wolfhard.tech      | YOUR_SERVER_IP     | 3600 |
| A     | docs.wolfhard.net  | YOUR_SERVER_IP     | 3600 |
| A     | docs.wolfhard.dev  | YOUR_SERVER_IP     | 3600 |
| A     | docs.wolfhard.tech | YOUR_SERVER_IP     | 3600 |
| CNAME | www.wolfhard.net   | wolfhard.net       | 3600 |
| CNAME | www.wolfhard.dev   | wolfhard.dev       | 3600 |
| CNAME | www.wolfhard.tech  | wolfhard.tech      | 3600 |

### Verify DNS Propagation

```bash
# Check DNS records
dig wolfhard.net
dig docs.wolfhard.net

# Check from multiple locations
# Use https://dnschecker.org/
```

## SSL Certificate Setup

### Let's Encrypt Configuration

Certificates are automatically obtained on first nginx start.

**Initial Certificate Acquisition:**

```bash
# Ensure DNS is properly configured
# Ensure ports 80 and 443 are accessible from internet

# Start nginx (will automatically request certificates)
sudo systemctl start nginx

# Check certificate status
sudo systemctl status acme-wolfhard.net.service
sudo systemctl status acme-docs.wolfhard.net.service

# View logs if there are issues
sudo journalctl -u acme-wolfhard.net.service -f
```

**Common Issues:**

1. **DNS not propagated**: Wait for DNS TTL to expire
2. **Ports blocked**: Check firewall and router/hosting provider
3. **Rate limits**: Use Let's Encrypt staging server for testing

```nix
# For testing, uncomment in modules/services/nginx.nix:
# server = "https://acme-staging-v02.api.letsencrypt.org/directory";
```

## Updating the System

### Regular Updates

```bash
# Update flake inputs to latest versions
nix flake update

# Preview what will change
nix flake show

# Build new configuration (doesn't activate)
make build

# Test in VM (recommended for major changes)
make vm

# Apply changes to running system
make switch
```

### Update Workflow

1. **Pull latest changes** (if using git)
   ```bash
   git pull origin main
   ```

2. **Review changes**
   ```bash
   git log -p
   ```

3. **Update dependencies**
   ```bash
   nix flake update
   ```

4. **Test build**
   ```bash
   make build
   ```

5. **Apply**
   ```bash
   make switch
   ```

6. **Verify services**
   ```bash
   sudo systemctl status nginx
   sudo systemctl status sshd
   ```

## Rolling Back

If an update causes issues:

```bash
# List available generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or switch to specific generation
sudo nixos-rebuild switch --switch-generation 123

# Make permanent by updating flake.lock
git checkout flake.lock
```

## Remote Deployment

### Deploy from Local Machine

```bash
# Build on local machine and deploy to remote
nixos-rebuild switch --flake .#homelab \
  --target-host cypl0x@homelab.example.com \
  --build-host localhost

# Or use the Makefile with remote host
HOST=homelab make switch
```

### SSH Configuration

Add to your local `~/.ssh/config`:

```
Host homelab
    HostName YOUR_SERVER_IP
    User cypl0x
    IdentityFile ~/.ssh/id_ed25519_homelab
    ForwardAgent yes
```

## Monitoring Deployment

### Check System Status

```bash
# Overall system health
sudo systemctl status

# Specific services
sudo systemctl status nginx
sudo systemctl status acme-wolfhard.net
sudo systemctl status tailscale

# Failed services
sudo systemctl --failed

# Recent logs
sudo journalctl -xe

# Service-specific logs
sudo journalctl -u nginx -f
```

### Performance Monitoring

```bash
# Access Netdata dashboard
# http://localhost:19999 (when on the server)
# Or via SSH tunnel:
ssh -L 19999:localhost:19999 cypl0x@homelab

# Then open http://localhost:19999 in your browser
```

### Disk Usage

```bash
# Check disk usage
df -h

# Nix store cleanup
nix-collect-garbage -d

# More aggressive cleanup (removes old generations)
sudo nix-collect-garbage -d
```

## Troubleshooting Deployment

### Build Fails

```bash
# Check syntax errors
fd -e nix -x nix-instantiate --parse {}

# Run linters
make lint-deadnix
make fmt-check
statix check

# Verbose build output
nixos-rebuild switch --flake .#homelab --show-trace
```

### Service Won't Start

```bash
# Check service status
sudo systemctl status SERVICE_NAME

# View logs
sudo journalctl -u SERVICE_NAME -n 50

# Check configuration
systemctl cat SERVICE_NAME

# Restart service
sudo systemctl restart SERVICE_NAME
```

### Network Issues

```bash
# Check firewall rules
sudo iptables -L -n -v

# Test port accessibility
nc -zv localhost 80
nc -zv localhost 443

# Check DNS resolution
dig wolfhard.net

# Restart networking
sudo systemctl restart systemd-networkd
```

### Certificate Issues

See [SECURITY.md](../SECURITY.md#ssltls-certificate-management) for detailed certificate troubleshooting.

## Maintenance Tasks

### Weekly

- Check for system updates: `nix flake update`
- Review failed services: `sudo systemctl --failed`
- Check disk usage: `df -h`

### Monthly

- Clean old generations: `sudo nix-collect-garbage -d`
- Review security logs: `sudo journalctl -u sshd | grep Failed`
- Update documentation if configuration changed
- Backup critical data

### Quarterly

- Review and update dependencies
- Security audit (see [SECURITY.md](../SECURITY.md))
- Review firewall rules
- Test disaster recovery procedures

## Production Checklist

Before deploying to production:

- [ ] DNS records configured and propagated
- [ ] Firewall rules reviewed and tested
- [ ] SSL certificates obtained successfully
- [ ] All services started successfully
- [ ] Backup strategy implemented
- [ ] Monitoring configured
- [ ] Security hardening applied
- [ ] Documentation updated
- [ ] Rollback plan tested
- [ ] Emergency access verified

## Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Package Search](https://search.nixos.org/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [SECURITY.md](../SECURITY.md) - Security procedures
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture
- [NGINX.md](./NGINX.md) - Web server configuration
