# Docker Compose Scripts for my Home Server
This is my personal config. You will need to tweak it to your needs.

### Example of usage:

```bash
scp * bbsa@docker:/mnt/docker/
ssh bbsa@docker
cd /mnt/docker
docker compose -f infra-docker-compose.yml up -d
```

### Services Included:
1. **qbittorrent**: Torrent client for downloading and managing torrents.
2. **jackett**: Indexer for searching torrent files.
3. **bazarr**: Subtitle management tool for media libraries.
4. **overseerr**: Media request management for users.
5. **prowlarr**: Indexer for NZBs and torrents.
6. **flaresolverr**: Anti-bot solver for web scraping.
7. **sabnzbd**: Usenet downloader for NZBs.
8. **radarr**: Movie downloader and manager.
9. **sonarr**: TV series downloader and manager.
10. **plex**: Media server for streaming your content.
11. **cloudflared**: DNS resolver using Cloudflare.
12. **pihole**: Network-wide ad blocker.
13. **portainer**: Web UI for managing Docker.
14. **organizr**: Dashboard for organizing services.
15. **watchtower**: Automatic Docker container updater.
16. **zerotier**: Virtual LAN software for connecting devices.
17. **librespeed**: Self-hosted speed test server.

### Notes:
- Volumes are mapped for persistent data storage.
- Environment variables are configured for timezone and user IDs.
- Ports are exposed for web UI access where applicable.
- Use `network_mode: host` for services that need network access like `plex`, `pihole`, `cloudflared`, etc.

### Customization:
- Adjust `TZ`, `PUID`, and `PGID` as per your system setup.
- Update volume paths as per your local directory structure.
```
