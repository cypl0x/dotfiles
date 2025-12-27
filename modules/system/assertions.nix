{
  config,
  lib,
  ...
}: {
  # System-wide configuration assertions to catch errors early
  assertions = [
    # Ensure ACME is configured when nginx is enabled
    {
      assertion = config.services.nginx.enable -> config.security.acme.acceptTerms;
      message = "Nginx is enabled but ACME terms have not been accepted. Set security.acme.acceptTerms = true.";
    }

    # Ensure ACME email is configured when ACME is enabled
    {
      assertion = config.security.acme.acceptTerms -> (config.security.acme.defaults.email != null && config.security.acme.defaults.email != "");
      message = "ACME is enabled but no email address is configured. Set security.acme.defaults.email.";
    }

    # Ensure cypl0x user has SSH keys if SSH is enabled
    {
      assertion =
        config.services.openssh.enable
        -> (
          config.users.users ? cypl0x
          -> (
            config.users.users.cypl0x.openssh.authorizedKeys.keyFiles
            != []
            || config.users.users.cypl0x.openssh.authorizedKeys.keys != []
          )
        );
      message = "SSH is enabled but user 'cypl0x' has no authorized SSH keys configured.";
    }

    # Ensure root user has SSH keys if root login is allowed
    {
      assertion =
        config.services.openssh.settings.PermitRootLogin
        != "no"
        -> (
          config.users.users.root.openssh.authorizedKeys.keyFiles
          != []
          || config.users.users.root.openssh.authorizedKeys.keys != []
        );
      message = "Root login is permitted but no SSH keys are configured for root user.";
    }

    # Warn if nginx is enabled without firewall ports open (though this should be handled by modules)
    {
      assertion =
        config.services.nginx.enable
        -> (
          builtins.elem 80 config.networking.firewall.allowedTCPPorts
          && builtins.elem 443 config.networking.firewall.allowedTCPPorts
        );
      message = "Nginx is enabled but firewall ports 80 and 443 are not open.";
    }

    # Ensure monitoring is properly configured if enabled
    {
      assertion =
        (config.services.netdata.enable or false)
        -> config.systemd.services ? netdata;
      message = "Netdata monitoring is enabled but systemd service is not configured.";
    }
  ];

  # Warnings for non-critical issues
  warnings =
    lib.optional (config.system.stateVersion == "23.11") ''
      System stateVersion is set to "23.11" which may be outdated.
      Consider reviewing NixOS release notes and updating to a newer version if appropriate.
    ''
    ++ lib.optional (
      config.services.openssh.settings.PermitRootLogin
      != "no"
      && config.services.openssh.settings.PermitRootLogin != "prohibit-password"
    ) ''
      Root login is permitted with password authentication.
      Consider setting PermitRootLogin to "prohibit-password" or "no" for better security.
    ''
    ++ lib.optional (
      config.home-manager.users ? wap
      && (config.home-manager.users.wap.programs.git.settings.user.email or "") == "wap@work.com"
    ) ''
      User 'wap' is using placeholder email 'wap@work.com'.
      Update this in home/wap.nix with your actual work email address.
    '';
}
