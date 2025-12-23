# Nginx Static Web Server Configuration

This dotfiles configuration includes a hardened Nginx setup for serving static websites with HTTPS.

## Overview

- **Ports**: 80 (HTTP - redirects to HTTPS), 443 (HTTPS)
- **Domains**: wolfhard.net, wolfhard.dev, wolfhard.tech (with www subdomains)
- **SSL/TLS**: Let's Encrypt certificates (automatic renewal)
- **Document Root**: `/var/www/wolfhard` (symlink to `/etc/nginx/www`)
- **Security**: Hardened with modern security headers and best practices
- **HTTP to HTTPS**: All HTTP traffic automatically redirected to HTTPS

## Features

### Security Hardening

- **Security Headers**:
  - X-Frame-Options: Prevents clickjacking
  - X-Content-Type-Options: Prevents MIME type sniffing
  - X-XSS-Protection: XSS attack protection
  - Content-Security-Policy: Restricts resource loading
  - Referrer-Policy: Controls referrer information

- **Server Hardening**:
  - Server version hidden (server_tokens off)
  - Request size limits (10MB max)
  - Optimized timeouts and buffer sizes
  - Hidden files (.htaccess, .git) blocked

- **Best Practices**:
  - Gzip compression enabled
  - Static asset caching (1 year for images/fonts/css/js)
  - UTF-8 charset
  - Custom error pages (404, 50x)

### Virtual Hosts

All three domains serve the same content:

1. **wolfhard.net** (+ www.wolfhard.net)
2. **wolfhard.dev** (+ www.wolfhard.dev)
3. **wolfhard.tech** (+ www.wolfhard.tech)

### Default Server

- Catches all requests to unknown domains
- Returns HTTP 444 (close connection without response)
- Security measure to prevent domain-based attacks

## Directory Structure

```
dotfiles/
├── hosts/homelab/
│   └── nginx.nix              # Nginx configuration module
└── web/
    └── static/
        ├── index.html         # Homepage
        └── 404.html           # 404 error page
```

Deployed to:
```
/etc/nginx/www/                # NixOS-managed static files
    ├── index.html
    └── 404.html
/var/www/wolfhard -> /etc/nginx/www  # Symlink
```

## Configuration Files

### Main Configuration

Located at: `hosts/homelab/nginx.nix`

Key sections:
- Recommended Nginx settings enabled
- Security headers in `appendHttpConfig`
- Virtual host definitions
- Firewall rules
- Static file deployment

### Website Content

Located at: `web/static/`

Files are automatically deployed to `/etc/nginx/www/` during system rebuild.

## Usage

### Accessing the Website

```bash
# Local access
curl http://localhost:8080

# Via domain (requires DNS or /etc/hosts)
curl http://wolfhard.net:8080

# Test from browser
http://your-server-ip:8080
```

### Viewing Logs

```bash
# Access logs
tail -f /var/log/nginx/wolfhard.net.access.log
tail -f /var/log/nginx/wolfhard.dev.access.log
tail -f /var/log/nginx/wolfhard.tech.access.log

# Error logs
tail -f /var/log/nginx/wolfhard.net.error.log

# All nginx logs
journalctl -u nginx -f
```

### Testing Configuration

```bash
# Test nginx configuration syntax
sudo nginx -t

# Reload nginx (after manual config changes)
sudo systemctl reload nginx

# Restart nginx
sudo systemctl restart nginx

# Check nginx status
sudo systemctl status nginx
```

## Updating Website Content

### Method 1: Edit in Dotfiles (Recommended)

1. Edit files in `web/static/`:
   ```bash
   vim ~/dotfiles/web/static/index.html
   ```

2. Rebuild system:
   ```bash
   nrs  # or: nixos-rebuild switch --flake ~/dotfiles#homelab
   ```

3. Changes are automatically deployed

### Method 2: Direct Edit (Temporary)

```bash
# Edit directly (changes lost on rebuild!)
sudo vim /etc/nginx/www/index.html

# Nginx automatically serves updated file
```

**Note**: Direct edits are lost on next system rebuild. Always edit in `web/static/` for permanent changes.

## Adding New Pages

1. Create new HTML file in `web/static/`:
   ```bash
   vim ~/dotfiles/web/static/about.html
   ```

2. Add to nginx.nix `environment.etc`:
   ```nix
   environment.etc."nginx/www/about.html" = {
     source = ../../web/static/about.html;
     mode = "0644";
     user = "nginx";
     group = "nginx";
   };
   ```

3. Rebuild:
   ```bash
   nrs
   ```

4. Access at: `http://domain:8080/about.html`

## Adding Static Assets

### CSS Files

1. Create CSS file:
   ```bash
   mkdir -p ~/dotfiles/web/static/css
   vim ~/dotfiles/web/static/css/style.css
   ```

2. Add to nginx.nix:
   ```nix
   environment.etc."nginx/www/css/style.css" = {
     source = ../../web/static/css/style.css;
     mode = "0644";
     user = "nginx";
     group = "nginx";
   };
   ```

3. Link in HTML:
   ```html
   <link rel="stylesheet" href="/css/style.css">
   ```

### Images

Same process as CSS:
```nix
environment.etc."nginx/www/images/logo.png" = {
  source = ../../web/static/images/logo.png;
  mode = "0644";
  user = "nginx";
  group = "nginx";
};
```

### JavaScript

```nix
environment.etc."nginx/www/js/script.js" = {
  source = ../../web/static/js/script.js;
  mode = "0644";
  user = "nginx";
  group = "nginx";
};
```

## HTTPS/SSL Configuration (Let's Encrypt)

### Overview

This configuration uses NixOS's built-in ACME support for automatic Let's Encrypt certificates.

**Features:**
- Automatic certificate issuance on first rebuild
- Automatic renewal (checked twice daily)
- HTTP to HTTPS redirect (all HTTP traffic → HTTPS)
- Support for multiple domains and subdomains

### How It Works

```nix
# In nginx.nix
security.acme = {
  acceptTerms = true;
  defaults.email = "mail@wolfhard.net";
};

# For each domain:
"wolfhard.net" = {
  enableACME = true;      # Request Let's Encrypt cert
  forceSSL = true;        # Redirect HTTP → HTTPS
  serverAliases = [ "www.wolfhard.net" ];
};
```

### Certificate Management

**Certificate location**: `/var/lib/acme/<domain>/`

```bash
# Check certificate expiry
openssl x509 -in /var/lib/acme/wolfhard.net/cert.pem -noout -dates

# View certificate details
openssl x509 -in /var/lib/acme/wolfhard.net/cert.pem -noout -text

# Force certificate renewal
systemctl start acme-wolfhard.net.service

# Check ACME service status
systemctl status acme-wolfhard.net.service

# View renewal logs
journalctl -u acme-wolfhard.net.service -f
```

### First-Time Setup

**IMPORTANT**: Configure DNS BEFORE rebuilding!

1. **Set up DNS records** (see DNS Configuration section below)

2. **Verify DNS propagation**:
   ```bash
   dig wolfhard.net +short
   # Should return your server's public IP
   ```

3. **Rebuild system**:
   ```bash
   nrs
   ```

4. **Watch certificate issuance** (usually completes in < 1 minute):
   ```bash
   journalctl -fu acme-wolfhard.net.service
   ```

5. **Test HTTPS**:
   ```bash
   curl -I https://wolfhard.net
   ```

6. **Test HTTP redirect**:
   ```bash
   curl -I http://wolfhard.net
   # Should show: Location: https://wolfhard.net/
   ```

### Troubleshooting

**Certificate issuance fails:**

1. **Check DNS**:
   ```bash
   dig wolfhard.net +short  # Must return server IP
   ```

2. **Check port 80 accessible from internet**:
   ```bash
   # From external machine:
   curl http://your-server-ip
   ```

3. **View ACME logs**:
   ```bash
   journalctl -u acme-wolfhard.net.service -n 100
   ```

4. **Use staging server** (to avoid rate limits during testing):
   ```nix
   # In nginx.nix
   security.acme.defaults = {
     email = "mail@wolfhard.net";
     server = "https://acme-staging-v02.api.letsencrypt.org/directory";
   };
   ```
   Then rebuild and test. Switch back to production when ready.

5. **Manual renewal**:
   ```bash
   systemctl start acme-wolfhard.net.service
   ```

**HTTP redirect not working:**

- Check nginx is running: `systemctl status nginx`
- Check firewall: `ss -tulpn | grep nginx`
- View nginx logs: `journalctl -u nginx -f`

### Security Features

- **TLS 1.2 and 1.3** only (older versions disabled)
- **Modern cipher suites** (via `recommendedTlsSettings`)
- **HSTS** (HTTP Strict Transport Security)
- **Forward secrecy** enabled
- **OCSP stapling** enabled

### Testing SSL Configuration

```bash
# Check SSL with openssl
openssl s_client -connect wolfhard.net:443 -servername wolfhard.net

# Online SSL test
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=wolfhard.net
```

## DNS Configuration

To use your domains, configure DNS records:

### A Records (IPv4)

```
wolfhard.net      A      YOUR_SERVER_IPv4
www.wolfhard.net  A      YOUR_SERVER_IPv4
wolfhard.dev      A      YOUR_SERVER_IPv4
www.wolfhard.dev  A      YOUR_SERVER_IPv4
wolfhard.tech     A      YOUR_SERVER_IPv4
www.wolfhard.tech A      YOUR_SERVER_IPv4
```

### AAAA Records (IPv6)

```
wolfhard.net      AAAA   YOUR_SERVER_IPv6
www.wolfhard.net  AAAA   YOUR_SERVER_IPv6
(repeat for other domains)
```

## Adding HTTPS (Let's Encrypt)

To enable HTTPS with Let's Encrypt certificates:

### 1. Add ACME Configuration

Edit `nginx.nix`:

```nix
security.acme = {
  acceptTerms = true;
  defaults.email = "mail@wolfhard.net";
};
```

### 2. Update Virtual Hosts

```nix
"wolfhard.net" = {
  enableACME = true;
  forceSSL = true;
  # ... rest of config
};
```

### 3. Open Port 80

ACME needs port 80 for validation:

```nix
networking.firewall.allowedTCPPorts = [ 80 8080 ];
```

### 4. Rebuild

```bash
nrs
```

Certificates will be automatically obtained and renewed.

## Performance Optimization

### Enable HTTP/2

Already enabled via `recommendedTlsSettings` when HTTPS is configured.

### Enable Caching

Static assets are already cached for 1 year:
- Images: jpg, jpeg, png, gif, ico, svg
- Fonts: woff, woff2, ttf, eot
- Scripts: js
- Styles: css

### Enable Brotli Compression

Add to `nginx.nix`:

```nix
services.nginx = {
  # ... existing config
  appendHttpConfig = ''
    # ... existing headers

    # Brotli compression
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css application/json application/javascript text/xml application/xml;
  '';
};
```

## Security Considerations

### Current Security Features

✅ Security headers (XSS, clickjacking, etc.)
✅ Hidden files blocked
✅ Server version hidden
✅ Request size limits
✅ Timeout limits
✅ Default server returns 444
✅ Dedicated nginx user
✅ File permissions set correctly

### Additional Security Measures

1. **Rate Limiting**:
   ```nix
   appendHttpConfig = ''
     limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
     limit_req zone=one burst=20 nodelay;
   '';
   ```

2. **IP Whitelisting** (if needed):
   ```nix
   locations."/" = {
     extraConfig = ''
       allow 1.2.3.4;
       deny all;
     '';
   };
   ```

3. **Fail2ban Integration**: Monitor logs and ban IPs

## Troubleshooting

### Nginx Won't Start

```bash
# Check nginx config
sudo nginx -t

# Check journal
journalctl -u nginx -n 50

# Check permissions
ls -la /var/www/wolfhard
ls -la /etc/nginx/www
```

### Page Not Found (404)

```bash
# Check if files exist
ls -la /var/www/wolfhard/

# Check nginx error log
tail -f /var/log/nginx/wolfhard.net.error.log

# Verify symlink
readlink /var/www/wolfhard
```

### Permission Denied

```bash
# Check nginx user
ps aux | grep nginx

# Fix permissions
sudo chown -R nginx:nginx /var/www

# Check SELinux (if enabled)
sudo setenforce 0  # temporary
```

### Port 8080 Already in Use

```bash
# Find process using port
sudo lsof -i :8080

# Or use ss
sudo ss -tulpn | grep 8080
```

## Monitoring

### Check Nginx Status

```bash
# Service status
systemctl status nginx

# Test config
sudo nginx -t

# Check listening ports
ss -tulpn | grep nginx
```

### Monitor Access

```bash
# Real-time access log
tail -f /var/log/nginx/wolfhard.net.access.log

# Count requests
wc -l /var/log/nginx/wolfhard.net.access.log

# Top IPs
awk '{print $1}' /var/log/nginx/wolfhard.net.access.log | sort | uniq -c | sort -rn | head
```

## Backup

Website content is stored in git:

```bash
cd ~/dotfiles
git add web/
git commit -m "Update website content"
git push
```

Logs are in `/var/log/nginx/` (consider log rotation).

## See Also

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Security Headers](https://securityheaders.com/)
- [Main README](../README.md)
