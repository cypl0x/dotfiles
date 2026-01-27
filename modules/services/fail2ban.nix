_: {
  # Fail2ban - Intrusion Prevention System
  # Provides hardened protection for SSH, Nginx, and other exposed services

  services.fail2ban = {
    enable = true;

    # Ignore localhost and private networks
    ignoreIP = [
      "127.0.0.1/8"
      "::1"
      # Uncomment and add your trusted networks:
      # "192.168.1.0/24"
      # "10.0.0.0/8"
    ];

    # Global defaults
    maxretry = 3;
    bantime = "10m";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "48h";
    };

    # Hardened jail configurations using the new submodule API
    jails = {
      # SSH Protection - Most critical service
      sshd = {
        settings = {
          enabled = true;
          port = "ssh";
          filter = "sshd";
          logpath = "/var/log/auth.log";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };

      # Nginx - HTTP Authentication Failures
      nginx-http-auth = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-http-auth";
          logpath = "/var/log/nginx/error.log";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };

      # Nginx - Limit request floods
      nginx-limit-req = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-limit-req";
          logpath = "/var/log/nginx/error.log";
          maxretry = 5;
          findtime = "5m";
          bantime = "30m";
        };
      };

      # Nginx - Block known bad bots and scanners
      nginx-botsearch = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-botsearch";
          logpath = "/var/log/nginx/access.log";
          maxretry = 2;
          findtime = "10m";
          bantime = "24h";
        };
      };

      # Nginx - Bad request protection (400 errors)
      nginx-bad-request = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-bad-request";
          logpath = "/var/log/nginx/access.log";
          maxretry = 10;
          findtime = "5m";
          bantime = "1h";
        };
      };

      # Nginx - Block 404 spam
      nginx-noscript = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-noscript";
          logpath = "/var/log/nginx/access.log";
          maxretry = 6;
          findtime = "10m";
          bantime = "6h";
        };
      };

      # Nginx - Proxy attack protection
      nginx-noproxy = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-noproxy";
          logpath = "/var/log/nginx/access.log";
          maxretry = 2;
          findtime = "10m";
          bantime = "12h";
        };
      };
    };

    # Daemon settings for fail2ban
    daemonSettings = {
      # Global defaults
      DEFAULT = {
        banaction = "iptables-multiport";
        banaction_allports = "iptables-allports";
      };
    };
  };

  # Custom fail2ban filters
  environment.etc = {
    "fail2ban/filter.d/nginx-bad-request.local" = {
      text = ''
        [INCLUDES]
        before = common.conf

        [Definition]
        failregex = ^<HOST> - .* "(GET|POST|HEAD).*HTTP.*" (400|444|403|405) .*$
        ignoreregex =
      '';
    };

    "fail2ban/filter.d/nginx-botsearch.local" = {
      text = ''
        [INCLUDES]
        before = common.conf

        [Definition]
        failregex = <HOST>.*"(GET|POST).*(\.php|\.asp|\.exe|\.pl|cgi-bin|wp-admin|wp-login|phpmyadmin|administrator|xmlrpc).*$
                    <HOST>.*"(GET|POST).*(etc/passwd|proc/self|shadow|boot\.ini).*$
                    <HOST>.*"(GET|POST).*(eval\(|union.*select|concat.*\().*$
        ignoreregex =
      '';
    };

    "fail2ban/filter.d/nginx-noscript.local" = {
      text = ''
        [INCLUDES]
        before = common.conf

        [Definition]
        failregex = ^<HOST> - .* "(GET|POST|HEAD).*(\.php|\.asp|\.aspx|\.ashx).*" 404 .*$
        ignoreregex =
      '';
    };

    "fail2ban/filter.d/nginx-noproxy.local" = {
      text = ''
        [INCLUDES]
        before = common.conf

        [Definition]
        failregex = ^<HOST> - .* "(GET|POST|CONNECT) (http://|https://).*" 404 .*$
        ignoreregex =
      '';
    };
  };

  # Ensure fail2ban starts after network and required services
  systemd.services.fail2ban.after = [
    "network.target"
    "sshd.service"
    "nginx.service"
  ];
}
