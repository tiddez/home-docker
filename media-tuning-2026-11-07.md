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
| Duplicated media | Imports were copied, not hardlinked (137 GB stored twice) | Single `/mnt/storage:/data` mount + existing duplicates hardlinked → `/mnt/storage` 70% → 42% |
| Seeding | Torrents seeded forever, so completed downloads were never removed | Ratio 2.0 or 7 days, then Radarr/Sonarr remove them |

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
2. **Wrong mount**: Radarr mounts `/mnt/storage/Videos/radarr/movies:/movies`, Bazarr mounted `/mnt/storage/Videos/radarr:/movies`, so every Radarr path was "Path does not exist". Fixed the Bazarr mount to match Radarr and cleared the temporary movie path mapping (`/movies → /movies/movies`). Later superseded by the shared `/data` mount (§8).

Bazarr → Plex connection re-authenticated (was failing with 401), so Plex refreshes items after a subtitle download.

## 6. qBittorrent peer port

qBittorrent listened on `42190`, but Docker only published `62609/tcp`, so no peer could connect in.

- `Session\Port=62609` in `/home/docker/qbittorrent/config/qBittorrent/qBittorrent.conf`
- Added `62609:62609/udp` to the compose file (uTP/DHT)
- **To do on the router:** forward `62609` TCP+UDP → `192.168.50.30` for full incoming connectivity.

## 7. Watchtower cleanup

Watchtower updated `:latest` images daily without deleting old ones (13 GB reclaimable on the 52 GB root disk — same root cause as [disk-maintenance-2026-05-17](disk-maintenance-2026-05-17.md)). Added `WATCHTOWER_CLEANUP=true` in `utils-docker-compose.yml`.

## 8. Hardlinks: one shared `/data` mount

### Problem
Downloads (`/downloads`) and the library (`/movies`, `/tv`) were separate bind mounts. A hardlink cannot cross mount points (`EXDEV`), so Radarr/Sonarr **copied** every import, even with *Use Hardlinks instead of Copy* enabled. Each movie was stored twice while seeding.

### Fix
qBittorrent, Radarr, Sonarr and Bazarr all mount `/mnt/storage:/data`, so downloads and library are on the same mount and imports are instant hardlinks.

| App | Before | After |
|---|---|---|
| qBittorrent save path | `/downloads/` | `/data/Downloads/torrents/` |
| qBittorrent temp path | `/downloads/incomplete/` | `/data/Downloads/torrents/incomplete/` |
| Radarr root folder (+ movies, collections) | `/movies` | `/data/Videos/radarr/movies` |
| Sonarr root folder | `/tv` | `/data/Videos/sonarr` |
| Seerr default directory | `/movies`, `/tv` | same as Radarr/Sonarr |
| Bazarr | `/movies`, `/tv` | `/data` (same paths as Radarr/Sonarr, no path mappings) |
| Plex | `/media` | unchanged |

Radarr movies were re-pointed with the movie editor using *Move files = No* — no files moved on disk. Hardlink verified inside Radarr (`ln` across `/data/Downloads` → `/data/Videos` = 2 links).

The old `/mnt/storage/Downloads/torrents:/downloads` mount was first kept for the 5 torrents added before this change (saved path `/downloads`), then removed the same day: with qBittorrent stopped, `save_path` and `qBt-savePath` in their `BT_backup/*.fastresume` files were rewritten from `/downloads` to `/data/Downloads/torrents` (same host folder, so no data moved and hardlinks kept). All 5 restored without file errors. Backup of the original records: `/home/docker/backups/pre-hardlinks-2026-11-07/BT_backup-before-path-rewrite`.

> Don't use qBittorrent's *Set location* to move torrents between two different mounts — it copies the data and breaks hardlinks.

### Existing duplicates
Every download file was matched to a library file by identical size plus SHA-256 of three 8 MB samples (start, middle, end). The 5 matches were replaced with hardlinks to the library file, so torrents keep seeding without using extra space:

| Download | Size |
|---|---|
| The Godfather (1972) Remux | 49.0 GB |
| The Avengers (2012) Remux | 32.6 GB |
| Iron Man 3 (2013) Remux | 28.4 GB |
| Thor: The Dark World (2013) Remux | 25.2 GB |
| Thor (2011) Bluray-1080p | 2.2 GB |
| **Total** | **137.4 GB** |

Result: `/mnt/storage` **319 GB → 191 GB used (70% → 42%)**. Library files were not modified.

Not duplicates (not in the library), left untouched: Iron Man (2008), Iron Man 2 (2010), The Walking Dead: Daryl Dixon S01.

Backups taken before the change: `/home/docker/backups/pre-hardlinks-2026-11-07/` (Radarr/Sonarr backup zips, qBittorrent config, compose file, Seerr settings) and `bazarr.db.bak-2026-11-07`.

## 9. Seeding limit

qBittorrent had no share limit, so torrents seeded forever and Radarr/Sonarr *Remove Completed Downloads* never triggered.

```ini
Session\GlobalMaxRatio=2
Session\GlobalMaxSeedingMinutes=10080   ; 7 days
Session\ShareLimitAction=Stop
```

Whichever comes first stops the torrent; Radarr/Sonarr then remove it and its files from the downloads folder. With hardlinks only the download-side name is deleted — the library file keeps the data and Plex is unaffected. Only deleting a movie in Radarr (*Delete files*) or Plex removes it from the library.

## 10. Cleanup of unwanted media

Removed on request (not tracked by Radarr/Sonarr):

| Item | Where | Size |
|---|---|---|
| Iron Man (2008) | qBittorrent + downloads folder | 12.3 GB |
| Iron Man 2 (2010) | qBittorrent + downloads folder | 6.0 GB |
| The Walking Dead: Daryl Dixon S01 | qBittorrent + downloads folder | 2.3 GB |
| Guardians of the Galaxy Vol. 3 Remux | loose file in movies root | 43 GB |
| Madoff (2016) | Plex entry only (files were already gone) | — |

Torrents were removed by moving their `BT_backup` entries to `/home/docker/backups/removed-torrents-2026-11-07/` while qBittorrent was stopped. A duplicate rescan afterwards found **0** duplicate files. `/mnt/storage`: **191 GB → 129 GB used (28%)**.

## 11. SABnzbd (Usenet) — prepared, then removed

SABnzbd had never been used (0 history entries): no Usenet server, no Usenet indexer, not connected to Radarr/Sonarr, and the web UI was unreachable because the compose published `6789` (NZBGet's port, left over from an NZBGet → SABnzbd swap) while SABnzbd listens on `8080` inside the container.

| Change | Before | After |
|---|---|---|
| Port | `6789:6789` (dead) | `6789:8080` → UI at `http://192.168.50.30:6789` |
| Config folder | `/home/docker/nzbget/config` | `/home/docker/sabnzbd/config` |
| Download folders | `/mnt/storage/Downloads/nzbget` (empty) | `/data/Downloads/usenet/{incomplete,complete}` on the shared `/data` mount |
| Categories | defaults only | `radarr`, `sonarr` |
| Radarr / Sonarr | qBittorrent only | + SABnzbd download client (tested OK) |

Radarr and Sonarr already prefer Usenet (default delay profile, 0 delay), so once an indexer exists Usenet is tried first and torrents are the fallback.

### To finish the trial
1. Buy a Usenet **provider** (e.g. Newshosting, Eweka, Frugal — a 1-month plan is enough to test) and an **indexer** (e.g. NZBGeek).
2. SABnzbd (`:6789`) → setup wizard / Config → Servers → add the provider (host, port 563, SSL, username, password, connections per the plan).
3. Prowlarr → Indexers → Add → the Usenet indexer (API key). It syncs to Radarr/Sonarr automatically.
4. Request something in Seerr and check that it arrives via SABnzbd.

### Outcome: removed
Usenet has no free provider for media (only time/data-limited trials that convert to paid plans), so it was dropped for now:
- SABnzbd download client removed from Radarr and Sonarr (health OK).
- `sabnzbd` service removed from `media-docker-compose.yml`, container deleted, empty `/mnt/storage/Downloads/usenet` folders removed.
- **Kept:** `/home/docker/sabnzbd/config` (categories `radarr`/`sonarr` and `/data/Downloads/usenet` paths already set).

To try Usenet later, restore the service block (see commit `c4c51ce`):

```yaml
  sabnzbd:
    image: lscr.io/linuxserver/sabnzbd:latest
    restart: unless-stopped
    environment:
      - TZ=America/Sao_Paulo
      - PUID=1000
      - PGID=1000
    volumes:
      - /home/docker/sabnzbd/config:/config
      - /mnt/storage:/data
    ports:
      - '6789:8080'  # SABnzbd listens on 8080 in the container; host 8080 is qBittorrent
```

then follow *To finish the trial* above, plus re-add SABnzbd as a download client in Radarr/Sonarr (host `192.168.50.30`, port `6789`, categories `radarr`/`sonarr`).

## How to delete media

Always delete in **Radarr** (movies) or **Sonarr** (series) — they own the library:

1. Open the item → **Delete**
2. Check **Delete Movie Folder** / **Delete Series Folder** (removes the files)
3. Check **Add List Exclusion** if it should never come back

Then:
- **Plex** removes it automatically (library auto-scan is on).
- **qBittorrent**: if still seeding, the download-side hardlink keeps the data until the seeding limit (≤ 7 days), then Radarr/Sonarr remove it. To free space immediately, also delete the torrent in qBittorrent with *Also remove files*.
- **Seerr**: delete the request if there was one.

Don't delete only in Plex or only on disk — Radarr/Sonarr still monitor the item, see it missing, and download it again. Deleting only in qBittorrent removes just the download copy.

---

## Open items

| Item | Impact | Notes |
|---|---|---|
| **Router port forward** | Slower torrents | MikroTik RB750Gr3: dst-nat `62609` TCP+UDP → `192.168.50.30` (public IP, not CGNAT — WireGuard already reachable). Without it, only peers with an open port can connect. |
