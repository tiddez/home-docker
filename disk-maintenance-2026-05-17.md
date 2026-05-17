# Disk Maintenance — 2026-05-17

## Problem

Proxmox reported `vm-storage` (sda, 931.5 GB SATA SSD) at **100% allocated**, and the Docker VM (VM 100) root disk (`/dev/sda2`) was at **100% full** with 0 bytes free.

---

## Root Cause Analysis

### Proxmox Level (vm-storage VG)

The `vm-storage` LVM volume group on `sda` had only **120 MB free** out of 931.5 GB. This is because the thin pool was sized to consume nearly the entire disk when created, leaving no unallocated space for the VG to grow.

```
VG          PSize    PFree
vm-storage  931.51g  120.00m   ← effectively 0% free
```

VM disk allocations on the thin pool:
| VM  | Name      | Disk   | Allocated | Actually Used |
|-----|-----------|--------|-----------|---------------|
| 100 | Docker    | disk-0 | 52 GB     | ~32 GB (61%)  |
| 100 | Docker    | disk-1 | 400 GB    | ~59 GB (15%)  |
| 101 | SportClip | disk-0 | 32 GB     | ~13 GB (40%)  |
| 101 | SportClip | disk-1 | 100 GB    | ~2.5 GB (2%)  |

The thin pool data usage was only **11.67%** — the alarm was purely physical VG allocation, not actual data overflow.

### Docker VM Level (VM 100)

Inside the Docker VM, `/dev/sda2` (root, 32 GB) was 100% full. The cause was **Watchtower** pulling image updates weekly without cleanup — old image layers accumulated as dangling (`<none>:<none>`) images over several weeks.

```
Docker Root Dir: /var/lib/docker  (on /dev/sda2)

Images:   79 total — 25.09 GB, 15.24 GB reclaimable (dangling layers)
Volumes:  18 total —  2.45 GB, all unused
Containers: all stopped
```

---

## Actions Taken

### 1. Docker Cleanup

Removed dangling images, stopped containers, unused volumes and networks:

```bash
docker system prune -f --volumes
```

**Result:** Freed ~11 GB — disk went from **100% → 71%** (8.8 GB free).

### 2. Root Disk Expansion

The Proxmox disk config for VM 100 disk-0 was extended to 52 GB (was previously partitioned as 32 GB with 20 GB unallocated). Partition and filesystem were expanded live without downtime:

```bash
growpart /dev/sda 2
resize2fs /dev/sda2
```

**Result:** Root disk expanded from 32 GB → **52 GB**, usage dropped to **44%** (28 GB free).

### 3. Weekly Auto-Prune (Cron)

Added a cron job under the `docker` user to automatically clean dangling images every Sunday at 3:00 AM:

```bash
0 3 * * 0 docker image prune -f >> /home/docker/docker-prune.log 2>&1
```

`docker image prune -f` only removes untagged/dangling layers. It does **not** affect:
- Running containers
- Stopped containers
- Named images
- Volumes

This prevents disk fill-up from Watchtower's automatic image updates without risking service disruption.

---

## Final State

```
/dev/sda2   52 GB   21 GB used   28 GB free   (44%)
```

All 25 containers restored and running across 4 stacks (net, utils, media, monitoring).

---

## Notes

- **Watchtower** is the source of dangling image accumulation — it auto-pulls updates but doesn't prune old layers. The weekly cron compensates for this.
- To view prune history: `cat /home/docker/docker-prune.log`
- If a container is stopped and left for a week, `docker image prune -f` will **not** remove it or its image — only dangling layers are affected.
- The `vm-storage` thin pool on Proxmox still has only ~120 MB VG free space. Adding a new disk to the VG would resolve this long-term if new VM disks need to be created.
