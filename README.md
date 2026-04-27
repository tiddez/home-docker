# Docker Compose Scripts for my Home Server

This is my personal config. You will need to tweak it to your needs.

## Stack Structure

Services are split into **4 separate stacks**, each with its own compose file:

| Stack | File | Services |
|-------|------|----------|
| `media` | `media-docker-compose.yml` | Plex, Radarr, Sonarr, qBittorrent, Jackett, SABnzbd, Bazarr, Overseerr, Prowlarr, Flaresolverr |
| `net` | `net-docker-compose.yml` | Cloudflared, Pi-hole |
| `monitoring` | `monitoring-docker-compose.yml` | Zabbix, Prometheus, Grafana, cAdvisor, Node Exporter |
| `utils` | `utils-docker-compose.yml` | Portainer, Organizr, Watchtower, Librespeed |

## Deployment

Copy files to the Docker host, then deploy each stack separately:

```bash
scp -r * docker@192.168.50.30:/home/docker/compose/
ssh docker@192.168.50.30
cd /home/docker/compose

docker compose -f media-docker-compose.yml up -d
docker compose -f net-docker-compose.yml up -d
docker compose -f monitoring-docker-compose.yml up -d
docker compose -f utils-docker-compose.yml up -d
```

> The monitoring stack requires config files — copy the `monitoring/` folder to `/home/docker/monitoring/` on the host before starting it.

## Services

### Media Stack
1. **plex** — Media server for streaming content (`network_mode: host`)
2. **radarr** — Movie downloader and manager (`:7878`)
3. **sonarr** — TV series downloader and manager (`:8989`)
4. **qbittorrent** — Torrent client (`:8080`)
5. **jackett** — Torrent indexer (`:9117`)
6. **sabnzbd** — Usenet/NZB downloader (`:6789`)
7. **bazarr** — Subtitle management (`:6767`)
8. **overseerr** — Media request management (`:5055`)
9. **prowlarr** — Unified indexer for Radarr/Sonarr (`:9696`)
10. **flaresolverr** — Anti-bot bypass for indexers (`:8191`)

### Net Stack
11. **cloudflared** — DNS-over-HTTPS resolver via Cloudflare (`network_mode: host`)
12. **pihole** — Network-wide ad blocker (`network_mode: host`, web UI `:8053`)

### Monitoring Stack
13. **zabbix-server** — Infrastructure monitoring server (`:10051`)
14. **zabbix-web** — Zabbix web UI (`:8082`)
15. **zabbix-db** — PostgreSQL backend for Zabbix
16. **zabbix-agent** — Agent running on Docker host
17. **prometheus** — Metrics collection and storage (`:9090`)
18. **grafana** — Metrics visualization dashboards (`:3001`)
19. **cadvisor** — Container resource usage metrics
20. **node-exporter** — Host-level hardware/OS metrics

### Utils Stack
21. **portainer** — Docker web UI (`:9000`)
22. **organizr** — Service dashboard (`:80`)
23. **watchtower** — Automatic container updates
24. **librespeed** — Self-hosted speed test (`:9091`)

## Access URLs

| Service | URL |
|---------|-----|
| Portainer | `http://<host>:9000` |
| Plex | `http://<host>:32400/web` |
| Grafana | `http://<host>:3001` |
| Zabbix | `http://<host>:8082` |
| Prometheus | `http://<host>:9090` |
| Pi-hole | `http://<host>:8053/admin` |
| qBittorrent | `http://<host>:8080` |
| Radarr | `http://<host>:7878` |
| Sonarr | `http://<host>:8989` |
| Overseerr | `http://<host>:5055` |
| Organizr | `http://<host>:80` |
| Librespeed | `http://<host>:9091` |

## Notes

- All volumes use bind mounts to `/home/docker/<service>/` for easy backup.
- Named volumes are used for Portainer (`compose_portainer_data`) and Zabbix DB (`compose_zabbix_db`).
- Adjust `TZ`, `PUID`, and `PGID` for your system.
- Pi-hole and Cloudflared use `network_mode: host` — see `Infos.md` for port 53 conflict resolution.
- Portainer is **not** managed as a Portainer stack to avoid self-deployment crash loops.
- Grafana has Prometheus pre-provisioned as a datasource via `monitoring/provisioning/datasources/`.
