# Home Network Documentation

## Hosts

| IP Address | Role |
|---|---|
| 192.168.50.20 | Proxmox (Hypervisor) |
| 192.168.50.30 | Docker Host |
| 192.168.60.10 | Sportclip |
| 192.168.40.10 | DVR |
| 192.168.99.1 | MikroTik RB750 (Router/GW) |
| 192.168.99.2 | SW |
| 192.168.99.10 | Unifi AP |
| 192.168.99.20 | Unifi Controller LXC (Proxmox) |

---

## Management Interfaces

| Service | URL |
|---|---|
| Proxmox | http://192.168.50.20:8006 |
| Portainer | http://192.168.50.30:9000 |
| Unifi Controller | https://192.168.99.20:8443 |
| Zabbix | http://192.168.50.30:8082 |

---

## Media Stack Containers (192.168.50.30)

| Container | Status | URL |
|---|---|---|
| qBittorrent | Up | http://192.168.50.30:8080 |
| SABnzbd | Up | http://192.168.50.30:6789 |
| Jackett | Up | http://192.168.50.30:9117 |
| Prowlarr | Up | http://192.168.50.30:9696 |
| FlareSolverr | Up | http://192.168.50.30:8191 |
| Radarr | Up | http://192.168.50.30:7878 |
| Sonarr | Up | http://192.168.50.30:8989 |
| Bazarr | Up | http://192.168.50.30:6767 |
| Overseerr | Up | http://192.168.50.30:5055 |
| Plex | Starting | http://192.168.50.30:32400 |

---

## Monitoring Stack — Zabbix (192.168.50.30)

| Container | Status |
|---|---|
| zabbix-db (PostgreSQL) | Up, healthy |
| zabbix-server | Up |
| zabbix-web | Up, healthy |
| zabbix-agent | Replaced by native zabbix-agent2 |

**Access:** http://192.168.50.30:8082

---

## Proxmox Storage (192.168.50.20)

### Physical Disks

| Device | Size | Type | Role |
|---|---|---|---|
| nvme0n1 | 238.5 GB | NVMe SSD | Proxmox OS + system VMs |
| sda | 931.5 GB | SATA SSD | Production VM storage |
| sdb | 9.1 TB | SATA HDD | Backups + SMB share |

### Storage Pools (pvesm)

| Pool ID | Type | Path / Backing | Size | Content | Role |
|---|---|---|---|---|---|
| local | dir | /var/lib/vz | 68 GB | ISO image, Container template | Static files (ISOs, LXC templates) |
| local-lvm | lvmthin | pve/data | 141.5 GB | Disk image, Container | System VMs / LXCs (NVMe-fast) |
| vm-storage | lvmthin | vm-storage/vm-storage | 912.8 GB | Disk image, Container | Production VMs (SSD) |
| backup-pool | dir | /mnt/pve/backup-pool | 8.0 TB | Backup | VM/CT backups (HDD-cold) |
| smb-share | dir | /mnt/pve/smb-share | 1.0 TB | Snippets | Cloud-init / hookscripts; backs the Samba share |

### LVM Layout — sdb (9.1 TB)

```
sdb (9.1 TB)
└─ sdb1 (9.1 TB) → PV → vg-backup
   ├─ backup-pool LV (8 TB) → ext4 → /mnt/pve/backup-pool
   ├─ smb-share LV   (1 TB) → ext4 → /mnt/pve/smb-share
   └─ Free space: ~98 GB (reserved for future expansion)
```

### Resize Notes

To shift capacity between `backup-pool` and `smb-share` (both on `vg-backup`):

```bash
# Example: move 500GB from backup-pool to smb-share
lvresize -L -500G --resizefs /dev/vg-backup/backup-pool
lvresize -L +500G --resizefs /dev/vg-backup/smb-share
```

⚠️ Always ensure data fits within the new size before shrinking.

---

## Virtual Machines (Proxmox)

| VMID | Name | Type | OS Disk | Data Disk | Storage Pool |
|---|---|---|---|---|---|
| 100 | Docker | VM | 32 GB | 400 GB | vm-storage |
| 101 | SportClip | VM | 32 GB | 100 GB | vm-storage |
| 102 | unifi | LXC | 10 GB | — | local-lvm |

---

## Backup Jobs (Proxmox)

| Job ID | Schedule | Targets | Storage | Mode | Compression | Retention |
|---|---|---|---|---|---|---|
| daily-backup | 02:00 daily | All VMs/CTs | backup-pool | snapshot | zstd | 7d / 4w / 6m |

**Manage backups:** Datacenter → Backup (Proxmox UI) or `pvesh get /cluster/backup`

---

## SMB Share — media-archive (192.168.50.20)

**Server:** Samba 4.22 on Proxmox host
**Backing storage:** `/mnt/pve/smb-share` (1 TB ext4 LV on vg-backup)

| Attribute | Value |
|---|---|
| Server | `\\192.168.50.20` |
| Share name | `media-archive` |
| UNC path | `\\192.168.50.20\media-archive` |
| Username | `smbuser` |
| Password | `*********` |
| Access | Read/Write |

**Mount on Linux:**
```bash
sudo mkdir -p /mnt/media-archive
sudo mount -t cifs //192.168.50.20/media-archive /mnt/media-archive \
  -o username=smbuser,password='<PASSWORD>',uid=$(id -u),gid=$(id -g)
```

**Mount on Windows:**
```
net use Z: \\192.168.50.20\media-archive /user:smbuser
```
