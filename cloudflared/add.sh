#!/usr/bin/env bash
# Bulk-create Cloudflare DNS routes for every hostname in config.yml
# Run from the host where cloudflared is installed.
#
# Prerequisites:
#   - cloudflared logged in (cloudflared tunnel login)
#   - Tunnel created (cloudflared tunnel create <TUNNEL_NAME>)
#   - config.yml present at $CONF below

TUN=<TUNNEL_NAME>
CONF=/etc/cloudflared/config.yml

grep -E '^[[:space:]]*-[[:space:]]*hostname:' "$CONF" \
  | awk '{print $3}' | tr -d '"' | tr -d "'" \
  | while read -r h; do
      echo "adding $h"
      sudo cloudflared tunnel route dns "$TUN" "$h"
    done
