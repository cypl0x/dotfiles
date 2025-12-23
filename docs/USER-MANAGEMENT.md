# NixOS User & Password Management

## Overview

NixOS handles user management declaratively, but passwords require special handling since they shouldn't be stored in plain text in your configuration files (especially if you're using git).

## Methods for Setting Passwords

### 1. Imperative Password Setting (Recommended for Development)

Define users in configuration without passwords, then set passwords manually:

```nix
users.users.alice = {
  isNormalUser = true;
  description = "Alice Smith";
  extraGroups = [ "wheel" "networkmanager" ];
  shell = pkgs.zsh;
};

users.users.bob = {
  isNormalUser = true;
  description = "Bob Jones";
  extraGroups = [ "users" ];
  shell = pkgs.bash;
};
```

After rebuilding, set passwords manually:

```bash
sudo passwd alice
sudo passwd bob
```

**Pros:**
- Passwords not in configuration files
- Simple and secure for local systems
- Passwords survive rebuilds

**Cons:**
- Not fully declarative
- Manual step required on new systems

### 2. Hashed Passwords (Semi-Declarative)

Generate a password hash and store it in configuration:

```bash
# Generate password hash
mkpasswd -m sha-512
# Enter password when prompted, copy the hash
```

Add to configuration:

```nix
users.users.alice = {
  isNormalUser = true;
  hashedPassword = "$6$rounds=656000$YourHashHere...";
  extraGroups = [ "wheel" ];
};
```

**Pros:**
- Declarative
- Works on fresh installs

**Cons:**
- Hash visible in configuration (still secure, but not ideal for git)
- Hard to manage many users

### 3. Hashed Password Files (Best Practice)

Store hashed passwords in separate files outside git:

```bash
# Generate password and save to file
mkpasswd -m sha-512 > /etc/nixos/secrets/alice-password-hash
mkpasswd -m sha-512 > /etc/nixos/secrets/bob-password-hash

# Protect the files
chmod 600 /etc/nixos/secrets/*
```

In configuration:

```nix
users.users.alice = {
  isNormalUser = true;
  hashedPasswordFile = "/etc/nixos/secrets/alice-password-hash";
  extraGroups = [ "wheel" ];
};

users.users.bob = {
  isNormalUser = true;
  hashedPasswordFile = "/etc/nixos/secrets/bob-password-hash";
  extraGroups = [ "users" ];
};
```

In `.gitignore`:

```
secrets/
```

**Pros:**
- Fully declarative
- Secrets not in git
- Clean separation

**Cons:**
- Need to manage secret files separately
- Must backup secret files

### 4. Initial Password (First Login Only)

Set a temporary password that must be changed on first login:

```nix
users.users.alice = {
  isNormalUser = true;
  initialPassword = "changeme123";
  extraGroups = [ "wheel" ];
};
```

Or with hash:

```nix
users.users.alice = {
  isNormalUser = true;
  initialHashedPassword = "$6$rounds=656000$...";
  extraGroups = [ "wheel" ];
};
```

**Important:** `initialPassword` only works on first user creation. Subsequent rebuilds won't change the password.

### 5. Secrets Management Tools (Production)

For production systems, use dedicated secrets management:

#### sops-nix

```nix
# In flake.nix inputs
inputs.sops-nix.url = "github:Mic92/sops-nix";

# In configuration
imports = [ inputs.sops-nix.nixosModules.sops ];

sops.defaultSopsFile = ./secrets/secrets.yaml;
sops.secrets.alice-password.neededForUsers = true;

users.users.alice = {
  isNormalUser = true;
  hashedPasswordFile = config.sops.secrets.alice-password.path;
};
```

#### agenix

```nix
# Similar approach using age encryption
users.users.alice = {
  isNormalUser = true;
  hashedPasswordFile = config.age.secrets.alice-password.path;
};
```

## Complete User Configuration Example

```nix
{ pkgs, ... }: {
  # Create a secrets directory (outside git)
  # mkdir -p /etc/nixos/secrets
  # chmod 700 /etc/nixos/secrets

  users.users.alice = {
    isNormalUser = true;
    description = "Alice Smith";
    extraGroups = [
      "wheel"          # sudo access
      "networkmanager" # manage network
      "docker"         # docker access
    ];
    shell = pkgs.zsh;
    hashedPasswordFile = "/etc/nixos/secrets/alice-password-hash";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3... alice@laptop"
    ];
  };

  users.users.bob = {
    isNormalUser = true;
    description = "Bob Jones";
    extraGroups = [ "users" ];
    shell = pkgs.bash;
    hashedPasswordFile = "/etc/nixos/secrets/bob-password-hash";
  };

  # Service account (no password, SSH only)
  users.users.deploy = {
    isNormalUser = true;
    description = "Deployment User";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3... deploy@ci-server"
    ];
  };
}
```

## User Management Commands

### Generate Password Hash

```bash
# Using mkpasswd (recommended)
mkpasswd -m sha-512

# Save directly to file
mkpasswd -m sha-512 > /etc/nixos/secrets/user-password-hash

# Using openssl
openssl passwd -6

# Using Python
python3 -c 'import crypt; print(crypt.crypt("password", crypt.mksalt(crypt.METHOD_SHA512)))'
```

### Set/Change Password Imperatively

```bash
# Set password for user
sudo passwd alice

# Force password change on next login
sudo passwd -e alice

# Lock account
sudo passwd -l alice

# Unlock account
sudo passwd -u alice
```

### List Users

```bash
# All users
cat /etc/passwd

# Normal users only
awk -F: '$3 >= 1000 {print $1}' /etc/passwd

# Users with sudo access (wheel group)
getent group wheel
```

### Delete Users

Remove from configuration and rebuild, or:

```bash
# Remove user and home directory
sudo userdel -r alice

# Just remove user
sudo userdel alice
```

## Best Practices

### 1. Development/Local Systems

```nix
users.users.alice = {
  isNormalUser = true;
  extraGroups = [ "wheel" ];
};
```

Then: `sudo passwd alice`

### 2. Personal Dotfiles (Private Repo)

```nix
users.users.alice = {
  isNormalUser = true;
  hashedPasswordFile = "/etc/nixos/secrets/alice-password-hash";
  extraGroups = [ "wheel" ];
};
```

With `.gitignore`:
```
secrets/
```

### 3. Public Dotfiles

```nix
users.users.alice = {
  isNormalUser = true;
  # No password in config - set manually
  extraGroups = [ "wheel" ];
};
```

Document in README: "Run `sudo passwd alice` after first rebuild"

### 4. Production Systems

Use sops-nix or agenix for encrypted secrets management.

## Common User Groups

```nix
extraGroups = [
  "wheel"          # sudo/admin access
  "networkmanager" # manage network connections
  "docker"         # docker daemon access
  "libvirtd"       # KVM/QEMU virtual machines
  "audio"          # audio devices
  "video"          # video devices
  "input"          # input devices
  "dialout"        # serial ports
  "plugdev"        # pluggable devices
  "users"          # standard user group
];
```

## Example: Add Two Users to Your Dotfiles

Create a new module: `hosts/homelab/users.nix`

```nix
{ pkgs, ... }: {
  # Enable sudo without password for wheel group (optional)
  security.sudo.wheelNeedsPassword = true;

  users.users.alice = {
    isNormalUser = true;
    description = "Alice Smith";
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    # Password will be set manually with: sudo passwd alice
  };

  users.users.bob = {
    isNormalUser = true;
    description = "Bob Jones";
    extraGroups = [ "users" ];
    shell = pkgs.bash;
    # Password will be set manually with: sudo passwd bob
  };
}
```

Import in `configuration.nix`:

```nix
imports = [
  ./hardware-configuration.nix
  ./vultr.nix
  ./users.nix  # Add this line
];
```

Rebuild and set passwords:

```bash
sudo nixos-rebuild switch --flake .#homelab
sudo passwd alice
sudo passwd bob
```

## Handling SSH Keys

```nix
users.users.alice = {
  isNormalUser = true;
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alice@laptop"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... alice@desktop"
  ];
};
```

Or from files:

```nix
users.users.alice = {
  isNormalUser = true;
  openssh.authorizedKeys.keyFiles = [
    ./ssh-keys/alice.pub
  ];
};
```

## Security Considerations

1. **Never** store plain text passwords in configuration
2. **Always** add `secrets/` to `.gitignore`
3. Use `hashedPasswordFile` for declarative passwords
4. Consider SSH keys instead of passwords for remote access
5. Use strong password hashing: SHA-512 with high rounds
6. For production, use sops-nix or agenix
7. Regularly rotate passwords
8. Use `initialPassword` only for development/testing

## Migration Strategy

If you have existing users with passwords:

```bash
# Extract current password hash
sudo cat /etc/shadow | grep alice

# Save to file
sudo cat /etc/shadow | grep alice | cut -d: -f2 > /etc/nixos/secrets/alice-password-hash

# Add to configuration
users.users.alice.hashedPasswordFile = "/etc/nixos/secrets/alice-password-hash";
```

## Resources

- [NixOS Manual: User Management](https://nixos.org/manual/nixos/stable/index.html#sec-user-management)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [agenix](https://github.com/ryantm/agenix)
- [mkpasswd man page](https://linux.die.net/man/1/mkpasswd)
