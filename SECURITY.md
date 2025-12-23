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
