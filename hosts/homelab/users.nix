{ pkgs, ... }: {
  # User management for homelab

  # Allow wheel group to use sudo
  security.sudo.wheelNeedsPassword = true;

  # Define users
  users.users = {
    # Example user 1: alice (admin user)
    # Uncomment to enable
    # alice = {
    #   isNormalUser = true;
    #   description = "Alice Smith";
    #   extraGroups = [ "wheel" "networkmanager" ];
    #   shell = pkgs.zsh;
    #   # Set password after rebuild with: sudo passwd alice
    #   # Or use hashedPasswordFile for declarative password:
    #   # hashedPasswordFile = "/etc/nixos/secrets/alice-password-hash";
    #   openssh.authorizedKeys.keys = [
    #     # "ssh-ed25519 AAAAC3... alice@laptop"
    #   ];
    # };

    # Example user 2: bob (regular user)
    # Uncomment to enable
    # bob = {
    #   isNormalUser = true;
    #   description = "Bob Jones";
    #   extraGroups = [ "users" ];
    #   shell = pkgs.bash;
    #   # Set password after rebuild with: sudo passwd bob
    #   # Or use hashedPasswordFile for declarative password:
    #   # hashedPasswordFile = "/etc/nixos/secrets/bob-password-hash";
    # };
  };
}
