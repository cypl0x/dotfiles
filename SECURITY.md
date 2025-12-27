# Security Considerations

## SSH Key Usage

### ⚠️ Current Issue: Shared SSH Key Across Multiple Users

**Status:** Requires Manual Action

**Description:**
The same SSH public key is currently authorized for multiple user accounts:
- `root` (modules/users/root.nix)
- `cypl0x` (modules/users/cypl0x.nix)
- `wap` (modules/users/wap.nix)

**Risk:**
If the corresponding private key is compromised, an attacker would gain access to ALL three accounts, including root. This violates the principle of least privilege.

**Recommendation:**
Generate separate SSH key pairs for each user account, especially for root access:

```bash
# Generate a separate key for root access
ssh-keygen -t ed25519 -C "root@homelab" -f ~/.ssh/id_ed25519_root

# Generate a separate key for the wap user
ssh-keygen -t ed25519 -C "wap@homelab" -f ~/.ssh/id_ed25519_wap

# Keep your existing key for the cypl0x user
```

Then update the respective user configuration files with the appropriate public keys.

**Best Practices:**
- Use different SSH keys for different security contexts
- Consider using SSH certificates for better key management
- Restrict root SSH access to specific trusted IPs if possible
- Regularly rotate SSH keys
- Use hardware security keys (YubiKey) for critical accounts when possible

## ShellFish Credentials

**Status:** ✅ Fixed

ShellFish API credentials have been moved to environment variables. To configure:

1. Copy the template: `cp home/shell/.shellfishrc.secrets.example ~/.shellfishrc.secrets`
2. Edit `~/.shellfishrc.secrets` with your actual credentials from the ShellFish app
3. Source it in your shell profile: `source ~/.shellfishrc.secrets`

The secrets file is gitignored to prevent accidental commits.

## General Security Posture

### ✅ Good Practices Already Implemented
- SSH password authentication disabled (key-only)
- Root password login disabled
- Firewall enabled and configured
- Proper nginx security headers
- Monitoring services bound to localhost only
- No hardcoded passwords in configuration

### Recommendations
- Regularly update NixOS and packages
- Review firewall rules periodically
- Monitor system logs for suspicious activity
- Consider implementing fail2ban for SSH brute force protection
- Keep backups of critical data and configurations

## Firewall Configuration

### Current Firewall Rules

The firewall is configured in the following modules:

- **HTTP/HTTPS (ports 80, 443)**: Opened by `modules/services/nginx.nix`
  - Required for web server access
  - Let's Encrypt certificate validation (port 80)
  - HTTPS traffic (port 443)

- **Tor Relay (port 9001)**: Opened by `modules/services/tor.nix`
  - Tor relay traffic
  - Only opened when Tor service is enabled

- **SSH (port 22)**: Configured in `modules/system/security.nix`
  - Default SSH port
  - Key-based authentication only
  - Root login restricted to key-only

### Viewing Active Firewall Rules

```bash
# List current firewall rules
sudo iptables -L -v -n

# Check firewall status
sudo systemctl status firewall

# View NixOS firewall configuration
sudo nix eval --raw .#nixosConfigurations.homelab.config.networking.firewall.allowedTCPPorts
```

### Adding Custom Firewall Rules

To add custom firewall rules, edit the relevant service module or add them to your host configuration:

```nix
# In hosts/homelab/default.nix
networking.firewall = {
  allowedTCPPorts = [ 8080 ];  # Example: Allow port 8080
  allowedUDPPorts = [ 51820 ]; # Example: Allow UDP port 51820

  # Allow specific IPs
  extraCommands = ''
    iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
  '';
};
```

## SSL/TLS Certificate Management

### Let's Encrypt (ACME) Configuration

SSL certificates are automatically managed by Let's Encrypt through the ACME protocol.

**Configuration:** `modules/services/nginx.nix`
- Email: mail@wolfhard.net
- Auto-renewal enabled
- Certificates stored in: `/var/lib/acme/`

### Certificate Renewal

Certificates are automatically renewed by NixOS systemd timers.

**Check renewal status:**
```bash
# View ACME certificate status
sudo systemctl status acme-*

# View certificate renewal logs
sudo journalctl -u acme-wolfhard.net.service

# List all certificates and expiry dates
sudo certbot certificates
```

**Manual renewal (if needed):**
```bash
# Renew all certificates
sudo systemctl start acme-renew.timer

# Renew specific domain
sudo systemctl start acme-wolfhard.net.service
```

### Troubleshooting Certificate Issues

**Certificate renewal failed:**
1. Check DNS records point to your server
2. Ensure ports 80 and 443 are accessible from the internet
3. Check logs: `sudo journalctl -u acme-<domain>.service`
4. Verify nginx is running: `sudo systemctl status nginx`

**Testing with Let's Encrypt staging:**
```nix
# In modules/services/nginx.nix
security.acme.defaults = {
  email = "mail@wolfhard.net";
  server = "https://acme-staging-v02.api.letsencrypt.org/directory";
};
```

## Incident Response Procedures

### Emergency Access

If normal SSH access is lost:

1. **Physical/Console Access**: Access the server physically or via hosting provider's console
2. **Single User Mode**: Boot into single-user mode for root access
3. **Rescue Mode**: Use NixOS installation media to boot into rescue mode

### Password Reset

```bash
# Boot into single-user mode and run:
passwd cypl0x  # Reset user password
```

### Compromised Key Response

If an SSH key is compromised:

1. **Immediate**: Remove the compromised key from all user configurations
2. **Rebuild**: Run `make switch` to apply changes
3. **Verify**: Check `/home/*/.ssh/authorized_keys` to ensure key is removed
4. **Audit**: Review system logs for unauthorized access
   ```bash
   sudo journalctl -u ssh -S "1 hour ago"
   sudo last
   sudo lastb  # Failed login attempts
   ```
5. **Rotate**: Generate and deploy new SSH keys

### Security Audit Checklist

Run these commands periodically to audit system security:

```bash
# Check for failed SSH login attempts
sudo journalctl -u sshd | grep "Failed password"

# List currently logged-in users
who

# Check for unusual processes
ps aux | grep -v "^\[root\]"

# Review recent system changes
sudo nixos-rebuild list-generations

# Check for outdated packages
nix flake update --dry-run

# Review firewall rules
sudo iptables -L -n -v
```

## Backup and Recovery

### Configuration Backup

All configuration is stored in this Git repository. Ensure:

1. Regular commits of configuration changes
2. Push to remote repository (GitHub/GitLab)
3. Store sensitive files separately (SSH keys, secrets)

### Disaster Recovery

**Restore from scratch:**

```bash
# 1. Install NixOS base system
# 2. Clone repository
git clone https://github.com/yourusername/dotfiles.git
cd dotfiles

# 3. Copy SSH keys and secrets
cp /backup/ssh-keys/* ssh-keys/
cp /backup/.shellfishrc.secrets ~/.shellfishrc.secrets

# 4. Build and activate configuration
make switch
```

### Data Backup Strategy

Critical data to backup regularly:

- `/var/lib/acme/` - SSL certificates
- `/var/www/` - Web content
- `/home/*/` - User data
- Git repository - Configuration

**Recommended backup tools:**
- restic
- borg
- duplicity

## Monitoring and Alerts

### System Monitoring

Services configured in `modules/system/monitoring.nix`:

- **Netdata**: Real-time performance monitoring (http://localhost:19999)
- **System logs**: journalctl

### Recommended Alerting

Consider setting up alerts for:

- Failed SSH login attempts
- Certificate renewal failures
- High CPU/memory usage
- Disk space warnings
- Service failures

**Example using systemd email notifications:**

```nix
systemd.services.acme-wolfhard-net.onFailure = [ "email-notification@%n.service" ];
```

## Security Update Policy

### NixOS Updates

```bash
# Update flake inputs to latest
nix flake update

# Review changes
nix flake show

# Build and test in VM
make vm

# Apply to production
make switch
```

### Security Patches

When security vulnerabilities are announced:

1. Update affected packages: `nix flake update`
2. Rebuild system: `make switch`
3. Verify services are running: `sudo systemctl status`
4. Check logs for errors: `sudo journalctl -xe`

### Update Schedule Recommendation

- **Critical security updates**: Immediately
- **Regular updates**: Weekly
- **Major version upgrades**: After testing in VM
