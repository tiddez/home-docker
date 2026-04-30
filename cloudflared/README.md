# Cloudflare Tunnel — Home Lab Setup

Exposes internal services (Proxmox, Plex, *arr stack, etc.) to the internet through a Cloudflare Tunnel — no port forwarding, no public IP needed.

## How it works

```
Internet -> Cloudflare edge -> Tunnel (outbound from your LAN) -> cloudflared on Docker host -> Internal service
```

`cloudflared` runs as a **systemd service on the Docker host** (192.168.50.30). It establishes an outbound connection to Cloudflare, so no inbound ports are opened on the home router.

## Files

| File | Purpose |
|---|---|
| `config.yml` | Ingress rules — maps `*.example.com` hostnames to internal `IP:port` services |
| `add.sh` | Helper script: reads hostnames from `config.yml` and creates the matching Cloudflare DNS CNAMEs in one go |

## Initial setup (one-time)

```bash
# 1. Install cloudflared on the host
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# 2. Authenticate against your Cloudflare account
cloudflared tunnel login

# 3. Create the tunnel
cloudflared tunnel create <TUNNEL_NAME>

# 4. Move credentials and config into place
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/<UUID>.json /etc/cloudflared/
sudo cp config.yml /etc/cloudflared/

# 5. Edit /etc/cloudflared/config.yml and fill in your tunnel name, UUID, and hostnames

# 6. Create DNS CNAMEs for every hostname (uses add.sh)
sudo bash add.sh

# 7. Install as a systemd service
sudo cloudflared service install
sudo systemctl enable --now cloudflared

# 8. Verify
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f
```

## Adding a new service

1. Edit `/etc/cloudflared/config.yml` — add a new ingress block **before** the `http_status:404` catch-all
2. Run `sudo bash add.sh` (creates the DNS records, idempotent)
3. Restart cloudflared: `sudo systemctl restart cloudflared`

## Common pitfalls

### 1. Self-signed origins (Proxmox web UI)
Proxmox at `:8006` uses a self-signed cert -> cloudflared rejects it:
```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```
**Fix:** Add `noTLSVerify: true` under `originRequest`.

### 2. Wrong key name: `httpHostRequest` vs `httpHostHeader`
Only `httpHostHeader` is valid.

### 3. Typos in the host header
The `httpHostHeader` value must **exactly match** the public hostname.

### 4. qBittorrent / Sonarr / Radarr — Host header validation
qBittorrent rejects requests where the `Host` header doesn't match `localhost`. Either:
- Disable host header validation in qBittorrent: **Settings -> Web UI -> Bypass authentication for clients on whitelisted IP subnets** + uncheck **"Enable Host header validation"**
- Or whitelist the public hostname: **Settings -> Web UI -> Server domains** -> add `qbit.example.com`

### 5. Catch-all rule placement
The `service: http_status:404` rule **must be the last** entry.

## Troubleshooting

```bash
# Live tail of cloudflared logs
sudo journalctl -u cloudflared -f

# Validate config syntax
cloudflared tunnel ingress validate

# Test what hostname maps to
cloudflared tunnel ingress rule https://plex.example.com

# List tunnels and routes
cloudflared tunnel list
cloudflared tunnel route list
```

## Security notes

- `credentials-file` (`<UUID>.json`) contains the **tunnel secret** — never commit it
- Cloudflare Access policies (Zero Trust) can be layered on top for SSO/MFA
- Internal IPs in `config.yml` are only used inside your LAN
