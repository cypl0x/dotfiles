{
  modulesPath,
  lib,
  ...
}: {
  # VM test configuration - lightweight version for testing
  # Build with: make vm
  # Run with: result/bin/run-homelab-vm-vm

  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"

    # Reuse most of the homelab configuration
    ../homelab/default.nix
  ];

  # Override hardware config for VM
  boot = {
    loader.grub = {
      device = lib.mkForce "/dev/vda";
      efiSupport = lib.mkForce false;
      efiInstallAsRemovable = lib.mkForce false;
    };
  };

  # VM-specific settings for better performance
  virtualisation = {
    # Allocate reasonable resources
    memorySize = 2048; # 2GB RAM
    cores = 2; # 2 CPU cores
    diskSize = 8192; # 8GB disk

    # Forward ports for testing
    forwardPorts = [
      {
        from = "host";
        host.port = 8080;
        guest.port = 80;
      }
      {
        from = "host";
        host.port = 8443;
        guest.port = 443;
      }
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    # Use graphics for easier debugging
    graphics = false; # Set to true if you want a GUI

    # Share host filesystem for easy file access (optional)
    sharedDirectories = {
      dotfiles = {
        source = "$HOME/dotfiles";
        target = "/mnt/dotfiles";
      };
    };
  };

  # VM-specific optimizations
  # Disable some services that aren't needed for testing
  services = {
    # Disable Tor in VM (not needed for testing)
    tor.relay.enable = lib.mkForce false;

    # Disable Tailscale in VM (requires real network)
    tailscale.enable = lib.mkForce false;

    # Keep nginx for testing web server
    # Keep monitoring for testing system health
  };

  # Use simpler ACME configuration for VM testing
  # Don't actually try to get Let's Encrypt certs in VM
  security.acme = {
    acceptTerms = lib.mkForce true;
    # Use a dummy email for VM
    defaults.email = lib.mkForce "test@example.com";
    # Use staging server to avoid rate limits if accidentally run
    defaults.server = lib.mkForce "https://acme-staging-v02.api.letsencrypt.org/directory";
  };

  # Disable ACME certificate generation in VM (will fail without public DNS)
  # Keep nginx running but use self-signed certs or http only
  services.nginx.virtualHosts = lib.mkForce {
    "localhost" = {
      # Disable ACME in VM
      enableACME = false;
      # Don't force SSL in VM for easier testing
      forceSSL = false;

      root = "/var/www/wolfhard";

      locations."/" = {
        index = "index.html";
        tryFiles = "$uri $uri/ =404";
      };

      extraConfig = ''
        access_log /var/log/nginx/localhost.access.log;
        error_log /var/log/nginx/localhost.error.log;
        charset utf-8;
      '';
    };
  };

  # Helpful message on login
  users.motd = ''
    ═══════════════════════════════════════════════════════════
                    Homelab VM Test Environment
    ═══════════════════════════════════════════════════════════

    This is a test VM running the homelab configuration.

    Testing access:
      - Web server (HTTP):  http://localhost:8080 (on host)
      - SSH:                ssh -p 2222 cypl0x@localhost (on host)
      - Inside VM:          http://localhost

    Useful commands:
      - Check nginx:        systemctl status nginx
      - View web logs:      journalctl -u nginx -f
      - Test web content:   curl http://localhost
      - Shared dotfiles:    ls /mnt/dotfiles

    To shutdown: poweroff
    ═══════════════════════════════════════════════════════════
  '';
}
