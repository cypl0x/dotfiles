_: {
  # Fail2ban - Intrusion Prevention System
  # Provides hardened protection for SSH, Nginx, and other exposed services

  services.fail2ban = {
    enable = true;

    # Maximum number of retries before banning
    maxretry = 3;

    # Ban duration (10 minutes default)
    bantime = "10m";

    # Default ban action: iptables with email notification
    # Available actions: iptables, iptables-allports, iptables-multiport
    banaction = "iptables-multiport";
    banaction-allports = "iptables-allports";

    # Time window for counting retries
    findtime = "10m";

    # Ignore localhost and private networks
    ignoreIP = [
      "127.0.0.1/8"
      "::1"
      # Uncomment and add your trusted networks:
      # "192.168.1.0/24"
      # "10.0.0.0/8"
    ];

    # Hardened jail configurations
    jails = {
      # SSH Protection - Most critical service
      sshd = ''
        enabled = true
        port = ssh
        filter = sshd
        logpath = /var/log/auth.log
        maxretry = 3
        findtime = 10m
        bantime = 1h
        # Increase ban time exponentially for repeat offenders
        bantime.increment = true
        bantime.multipliers = 1 2 4 8 16 32 64
        bantime.maxtime = 48h
      '';

      # Nginx - HTTP Authentication Failures
      nginx-http-auth = ''
        enabled = true
        port = http,https
        filter = nginx-http-auth
        logpath = /var/log/nginx/error.log
        maxretry = 3
        findtime = 10m
        bantime = 1h
      '';

      # Nginx - Limit request floods
      nginx-limit-req = ''
        enabled = true
        port = http,https
        filter = nginx-limit-req
        logpath = /var/log/nginx/error.log
        maxretry = 5
        findtime = 5m
        bantime = 30m
      '';

      # Nginx - Block known bad bots and scanners
      nginx-botsearch = ''
        enabled = true
        port = http,https
        filter = nginx-botsearch
        logpath = /var/log/nginx/access.log
        maxretry = 2
        findtime = 10m
        bantime = 24h
      '';

      # Nginx - Bad request protection (400 errors)
      nginx-bad-request = ''
        enabled = true
        port = http,https
        filter = nginx-bad-request
        logpath = /var/log/nginx/access.log
        maxretry = 10
        findtime = 5m
        bantime = 1h
      '';

      # Nginx - Block 404 spam
      nginx-noscript = ''
        enabled = true
        port = http,https
        filter = nginx-noscript
        logpath = /var/log/nginx/access.log
        maxretry = 6
        findtime = 10m
        bantime = 6h
      '';

      # Nginx - Proxy attack protection
      nginx-noproxy = ''
        enabled = true
        port = http,https
        filter = nginx-noproxy
        logpath = /var/log/nginx/access.log
        maxretry = 2
        findtime = 10m
        bantime = 12h
      '';
    };

    # Custom filters for enhanced protection
    daemonSettings = {
      # Database backend and logging
      DEFAULT = {
        dbpurgeage = "1d";
        loglevel = "INFO";
        logtarget = "SYSTEMD-JOURNAL";
      };

      # Custom nginx filter for bad requests
      "nginx-bad-request" = {
        INCLUDES.before = "common.conf";
        Definition = {
          failregex = ''^<HOST> - .* "(GET|POST|HEAD).*HTTP.*" (400|444|403|405) .*$'';
          ignoreregex = "";
        };
      };

      # Custom nginx filter for bot searches
      "nginx-botsearch" = {
        INCLUDES.before = "common.conf";
        Definition = {
          failregex = [
            ''<HOST>.*"(GET|POST).*(\.php|\.asp|\.exe|\.pl|cgi-bin|wp-admin|wp-login|phpmyadmin|administrator|xmlrpc).*$''
            ''<HOST>.*"(GET|POST).*(etc/passwd|proc/self|shadow|boot\.ini).*$''
            ''<HOST>.*"(GET|POST).*(eval\(|union.*select|concat.*\().*$''
          ];
          ignoreregex = "";
        };
      };

      # Custom nginx filter for script kiddie attacks
      "nginx-noscript" = {
        INCLUDES.before = "common.conf";
        Definition = {
          failregex = ''^<HOST> - .* "(GET|POST|HEAD).*(\.php|\.asp|\.aspx|\.ashx).*" 404 .*$'';
          ignoreregex = "";
        };
      };

      # Custom nginx filter for proxy attempts
      "nginx-noproxy" = {
        INCLUDES.before = "common.conf";
        Definition = {
          failregex = ''^<HOST> - .* "(GET|POST|CONNECT) (http://|https://).*" 404 .*$'';
          ignoreregex = "";
        };
      };
    };
  };

  # Ensure fail2ban starts after network and required services
  systemd.services.fail2ban.after = [
    "network.target"
    "sshd.service"
    "nginx.service"
  ];
}
