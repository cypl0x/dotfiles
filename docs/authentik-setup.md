# Authentik Setup (inari)

This checklist documents the manual post-deploy steps for Authentik on
`inari`.

## 1) Server-side secrets (before first deploy)

Create the Authentik secret env file on `inari`:

```bash
sudo install -d -m 700 /etc/authentik
sudo install -m 600 /dev/null /etc/authentik/secrets.env
sudo sh -c 'echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 50 | tr -d "\\n=")" >> /etc/authentik/secrets.env'
sudo sh -c 'echo "AUTHENTIK_BOOTSTRAP_PASSWORD=<strong-password>" >> /etc/authentik/secrets.env'
sudo sh -c 'echo "AUTHENTIK_BOOTSTRAP_EMAIL=wolfhard@wolfhard.net" >> /etc/authentik/secrets.env'
```

LDAP outpost token file (create after outpost/token exists in UI):

```bash
sudo install -m 600 /dev/null /etc/authentik/ldap.env
sudo sh -c 'echo "AUTHENTIK_TOKEN=<ldap-outpost-token>" >> /etc/authentik/ldap.env'
```

## 2) Initial Authentik login

1. Open `https://authentik.wolfhard.net/if/flow/initial-setup/`.
2. Log in with the bootstrap credentials from `/etc/authentik/secrets.env`.
3. Rotate to a strong permanent admin password.

## 3) Create OIDC provider for Linkwarden

1. In Authentik, create an Application + Provider (OIDC).
2. Set redirect URI:
   - `https://linkwarden.wolfhard.net/api/v1/auth/callback/authentik`
3. Configure Linkwarden to use the Authentik client ID/secret and issuer URL.

## 4) Create LDAP outpost

1. In Authentik, create LDAP Provider and LDAP Outpost.
2. Copy the generated outpost token.
3. Put token into `/etc/authentik/ldap.env` as `AUTHENTIK_TOKEN=...`.
4. Redeploy:

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#inari
```

## 5) Quick validation

```bash
systemctl status authentik authentik-worker authentik-ldap --no-pager
ss -tlnp | grep ':389\|:9000'
curl -k https://127.0.0.1 -H 'Host: authentik.wolfhard.net' -o /dev/null -w '%{http_code}\n'
```
