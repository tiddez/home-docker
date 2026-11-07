# Media Stack Tuning — 2026-11-07

## Summary

| Area | Problem | Fix |
|---|---|---|
| Storage | Proxmox disk grown to 500 GB, but `/mnt/storage` still 385 GB | `growpart /dev/sdb 2` + `resize2fs /dev/sdb2` → 484 GB |
| Plex playback | Seeking was slow/blurry with a bitrate limit | Clients set to Original quality (Direct Play) — no server change |
| Indexers | 7 dead/hijacked indexers, duplicate Jackett feeds, broken FlareSolverr | Cleaned up Prowlarr, removed Jackett + FlareSolverr |
| Release quality | Grabs with few seeds, any language, any quality | Min 15 seeders, original/English only, 1080p default |
| Subtitles | Bazarr never downloaded pt-BR | No providers enabled + wrong `/movies` mount |
| qBittorrent | Listening port ≠ published port (no incoming peers) | Listening port set to `62609`, TCP+UDP published |
| Root disk | Watchtower left old images behind (13 GB reclaimable) | `WATCHTOWER_CLEANUP=true` |

All app settings live in bind-mounted config folders (`/home/docker/<app>/config`), so recreating containers does not lose configuration. Backups of every file changed are on the Docker VM with the suffix `.bak-2026-11-07`.

---

## 1. Storage resize (Docker VM, `/dev/sdb`)

After growing the disk in Proxmox, the guest saw `sdb` = 500 GB but `sdb2` still ended at the old size. `sdb2` is the last partition, so it was grown online:

```bash
sudo growpart /dev/sdb 2
sudo resize2fs /dev/sdb2
df -h /mnt/storage   # 484G
```

## 2. Plex playback

Plex Pass is **not** active, so hardware transcoding is unavailable even though the iGPU (Intel UHD 630, `8086:3E92`) is passed through to the container. Any transcode runs on the VM's 3 vCPUs, and every seek restarts it.

Fix is on the **clients**: Settings → Quality → Home Streaming = **Original/Maximum**, *Automatically adjust quality* = off. Verify in Plex Dashboard that playback shows **Direct Play**.

Notes:
- Image-based subtitles (PGS/VobSub) force a transcode — prefer SRT (what Bazarr downloads).
- If transcoding is ever needed (remote/low bandwidth), Plex Pass or Jellyfin would use the iGPU.

## 3. Indexers (Prowlarr)

### Removed
| Indexer | Reason |
|---|---|
| 52BT, Magnet Cat, NorTorrent | Redirecting to unrelated domains (likely hijacked) |
| Demonoid Clone, Demonoid Clone2 | Offline, no definition in Prowlarr |
| Uindex | Blocked by Cloudflare |
| UzTracker | Failing since May |

### Added (only after passing a test)
YTS, MagnetDownload, TorrentProject2.
Tested but not added (offline/timeout): EZTV, TorrentDownloads, kickasstorrents, ExtraTorrent.

### Priorities (lower = preferred)
| Priority | Indexers |
|---|---|
| 10 | The Pirate Bay, Knaben, YTS |
| 15–25 | LimeTorrents, MagnetDownload, TorrentProject2, Torrent9 |
| 30 | RuTor, BigFANGroup |
| 40–45 | Nyaa.si, SubsPlease, nekoBT, Bangumi Moe (anime) |

### Jackett + FlareSolverr removed
- Sonarr/Radarr had manual Torznab entries pointing at Jackett (`:9117`) for The Pirate Bay, TorrentDownload and Apache, duplicating Prowlarr → removed; both apps now get indexers only from Prowlarr (full sync).
- FlareSolverr 3.5.2 could no longer solve Cloudflare challenges (timeouts), and only slowed searches. The proxy and the `flaresolverr` tag were removed from Prowlarr.
- Both services removed from `media-docker-compose.yml`; their config folders remain in `/home/docker/jackett` and `/home/docker/flaresolverr`.

Backup of the old Prowlarr indexer list: `/home/docker/prowlarr-indexers-backup-2026-11-07.json`.

## 4. Release rules (Radarr + Sonarr)

### Minimum seeders = 15
Set in Prowlarr → Settings → Apps → Sync Profiles → *Standard* (was 5), which syncs to every indexer in Radarr and Sonarr.

### Language: original or English only
Custom format **Not Original or English** (both apps), with three required, negated *Language* conditions:

| Condition | Value |
|---|---|
| Not Original | Original |
| Not English | English |
| Not Unknown | Unknown |

Scored **-10000** in every quality profile, with *Minimum Custom Format Score* = 0, so matching releases are rejected. Radarr's profile language changed from *Original* to *Any* so English versions of foreign films are allowed.

| Release | Result |
|---|---|
| Original language / English / no language tag | Allowed |
| MULTi including original or English | Allowed |
| Other dubs (FRENCH, RUS, DUBLADO PT-BR, …) | Rejected |

Example: *La Casa de Papel* (original Spanish) → Spanish, English and MULTi allowed; PT/FR/other dubs rejected.

### 1080p default
- Seerr → Radarr and Sonarr (incl. anime) default profile: **HD-1080p** (was *Any*).
- All existing movies moved to HD-1080p.
- When adding directly in Radarr/Sonarr, pick HD-1080p once — the add dialog remembers it per browser.

## 5. Subtitles (Bazarr, pt-BR)

Two problems:
1. **No providers enabled** → enabled OpenSubtitles.com and Subdl; language profile *bbsa* = `pb` (Portuguese – Brazil).
2. **Wrong mount**: Radarr mounts `/mnt/storage/Videos/radarr/movies:/movies`, Bazarr mounted `/mnt/storage/Videos/radarr:/movies`, so every Radarr path was "Path does not exist". Fixed the Bazarr mount to match Radarr and cleared the temporary movie path mapping (`/movies → /movies/movies`).

Bazarr → Plex connection re-authenticated (was failing with 401), so Plex refreshes items after a subtitle download.

## 6. qBittorrent peer port

qBittorrent listened on `42190`, but Docker only published `62609/tcp`, so no peer could connect in.

- `Session\Port=62609` in `/home/docker/qbittorrent/config/qBittorrent/qBittorrent.conf`
- Added `62609:62609/udp` to the compose file (uTP/DHT)
- **To do on the router:** forward `62609` TCP+UDP → `192.168.50.30` for full incoming connectivity.

## 7. Watchtower cleanup

Watchtower updated `:latest` images daily without deleting old ones (13 GB reclaimable on the 52 GB root disk — same root cause as [disk-maintenance-2026-05-17](disk-maintenance-2026-05-17.md)). Added `WATCHTOWER_CLEANUP=true` in `utils-docker-compose.yml`.

---

## Open items

| Item | Impact | Notes |
|---|---|---|
| **Hardlinks** | ~148 GB duplicated | Downloads (`/downloads`) and library (`/movies`, `/tv`) are separate bind mounts, so Radarr/Sonarr *copy* instead of hardlink, even with "Use Hardlinks" on. Fix: single `/mnt/storage:/data` mount in qBittorrent, Radarr, Sonarr, Bazarr and update paths. |
| **Seeding limit** | Downloads never cleaned | qBittorrent has no ratio/seeding-time limit, so Radarr/Sonarr "Remove Completed" never triggers. |
| **SABnzbd** | Unused | No Usenet indexer or download client configured in Radarr/Sonarr. |
| **Router port forward** | Slower torrents | Forward `62609` TCP+UDP to `192.168.50.30`. |
