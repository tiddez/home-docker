# Proxmox Infrastructure Optimization Plan (Revised)

## Current Actual Setup (as of 2026-04-30)

### Storage Devices
| Device | Size | Current Use | Status |
|--------|------|-------------|--------|
| nvme0n1 (NVMe SSD) | 238.5GB | Proxmox OS + pve-data pool | **Active** |
| sda (SATA SSD) | 931.5GB | vm-storage pool (VMs 100, 101) | **Active** |
| sdb (SATA HDD) | 9.1TB | Unallocated | **New - Ready to configure** |

### Current Disk Usage
```
nvme0n1 (238.5GB NVMe)
├─ pve-root: 69.5GB (Proxmox OS)
├─ pve-swap: 7.6GB
├─ pve-data: 141.5GB (thin pool)
│  └─ VM 102: 10GB
└─ Available: ~141.5GB for VMs

sda (931.5GB SATA SSD)
├─ vm-storage: 912.8GB (thin pool)
│  ├─ VM 100: 432GB (32GB root + 400GB data)
│  ├─ VM 101: 132GB (32GB root + 100GB data)
│  └─ Available: ~348GB
└─ Overhead: ~18.7GB

sdb (9.1TB NEW - UNFORMATTED)
└─ Ready for allocation
```

---

## Proposed Configuration for 10TB Disk (sdb)

### Partition Scheme
```
sdb (9.1TB total)
├─ backup-pool:    8TB (8000GB)    → Proxmox backups
└─ smb-share:      1TB (1000GB)    → Network SMB share (future camera/media archive)
```

### Storage Pool Setup

#### Pool 1: `backup-pool` (8TB partition on sdb)
- **Mount Point**: `/mnt/pve/backup-pool`
- **Type**: LVM (ZFS optional for compression)
- **Proxmox Use**: Backup storage
- **Purpose**: 
  - Full backups of all VMs (100, 101, 102)
  - Incremental snapshots
  - Long-term retention
- **Retention Policy**:
  - Daily backups: keep last 7 days
  - Weekly backups: keep last 4 weeks
  - Monthly backups: keep last 12 months

#### Pool 2: `smb-share` (1TB partition on sdb)
- **Mount Point**: `/mnt/pve/smb-share`
- **Type**: ext4 or XFS
- **Network Share**: SMB/CIFS via Samba
- **Purpose**: 
  - Network-accessible storage for clients
  - Future camera footage archive (when needed)
  - Media storage for Docker host access
  - Other long-term archive data
- **Network Access**:
  - Share name: `//proxmox/media-archive`
  - Access from: Docker host (192.168.50.30), Sportclip (192.168.60.10)

---

## Implementation Steps

### Phase 1: Prepare sdb Disk (Week 1)

**Status**: Ready to execute

**Run these commands on root@proxmox:**

```bash
# ========================================
# STEP 1-3: Create Volume Group
# ========================================

sudo pvcreate /dev/sdb2
sudo vgcreate vg-backup /dev/sdb2

# ========================================
# STEP 4: Create Two Logical Volumes
# ========================================

sudo lvcreate -L 8T -n backup-pool vg-backup
sudo lvcreate -L 1T -n smb-share vg-backup

# ========================================
# STEP 5: Format with ext4
# ========================================

sudo mkfs.ext4 -L backup-pool /dev/vg-backup/backup-pool
sudo mkfs.ext4 -L smb-share /dev/vg-backup/smb-share

# ========================================
# STEP 6-7: Create Mount Points & Mount
# ========================================

sudo mkdir -p /mnt/pve/backup-pool
sudo mkdir -p /mnt/pve/smb-share

sudo mount /dev/vg-backup/backup-pool /mnt/pve/backup-pool
sudo mount /dev/vg-backup/smb-share /mnt/pve/smb-share

# ========================================
# STEP 8: Make Persistent (fstab)
# ========================================

# Backup fstab first
sudo cp /etc/fstab /etc/fstab.backup

# Add to fstab
cat << 'EOF' | sudo tee -a /etc/fstab
/dev/mapper/vg--backup-backup--pool  /mnt/pve/backup-pool  ext4  defaults  0  2
/dev/mapper/vg--backup-smb--share    /mnt/pve/smb-share    ext4  defaults  0  2
EOF

# Test fstab is valid
sudo mount -a

# ========================================
# STEP 9: Verify
# ========================================

df -h | grep -E "backup-pool|smb-share"
lsblk
```

**Expected Output:**
```
/dev/mapper/vg--backup-backup--pool  7.9T   28K  7.9T   1% /mnt/pve/backup-pool
/dev/mapper/vg--backup-smb--share    992G  4.0K  992G   1% /mnt/pve/smb-share
```

### Phase 2: Add Storage Pools to Proxmox UI (Week 1)

**Status**: After Phase 1 is complete

**Via Proxmox Web UI:**
1. Go to **Datacenter** → **Storage** → **Add**

**Storage Pool 1: backup-pool**
```
ID:        backup-pool
Type:      Directory
Path:      /mnt/pve/backup-pool
Content:   Backups, Disk images, Snippets
Nodes:     proxmox
Disable:   (unchecked)
```

**Storage Pool 2: smb-share**
```
ID:        smb-share
Type:      Directory
Path:      /mnt/pve/smb-share
Content:   Disk images, Snippets
Nodes:     proxmox
Disable:   (unchecked)
```

**Verify in Proxmox UI:**
- Datacenter → Storage → You should see both pools listed
- Check that both are "Available"
- Disk usage should show correct sizes (~8TB and ~1TB)

### Phase 3: Add Proxmox Storage Pools (Week 1)
**Via Proxmox UI (Datacenter → Storage → Add):**

**Storage Pool 1: backup-pool**
- ID: `backup-pool`
- Type: Directory
- Path: `/mnt/pve/backup-pool`
- Content: Backups, Disk images, Snippets
- Max backups: 10 per VM

**Storage Pool 2: smb-share**
- ID: `smb-share`
- Type: Directory
- Path: `/mnt/pve/smb-share`
- Content: Disk images, Snippets
- Purpose: Network share staging

### Phase 4: Configure Backup Strategy (Week 2)
**Proxmox Backup Jobs:**
- VM 100: Full backup 02:00 daily → `backup-pool`
- VM 101: Full backup 02:30 daily → `backup-pool`
- VM 102: Full backup 03:00 daily → `backup-pool`
- Retention: 7 daily, 4 weekly, 12 monthly

### Phase 5: Setup SMB Share (Week 2)
```bash
# 1. Install Samba (if not present)
apt update && apt install samba samba-common-bin

# 2. Configure /etc/samba/smb.conf
[media-archive]
    path = /mnt/pve/smb-share
    browsable = yes
    read only = no
    create mask = 0755
    directory mask = 0755
    # Optional: restrict access
    valid users = @proxmox

# 3. Restart Samba
systemctl restart smbd

# 4. Test from Docker host
# smbclient -L //192.168.50.20 -U root
# mount -t cifs //192.168.50.20/media-archive /mnt/media-archive -o username=root,password=xxx
```

### Phase 6: Monitor and Test (Week 3)
1. Test first backup cycle (VM 102 is smallest - 10GB)
2. Verify backup restoration capability
3. Verify SMB share accessibility from Docker host
4. Monitor disk usage in Zabbix
5. Test incremental backup efficiency

---

## Updated Storage Summary

### Production Storage (Active VMs)
```
nvme0n1 (238.5GB NVMe)      → Proxmox kernel + emergency VM storage
  └─ pve-data: 141.5GB       (fast SSD, low capacity for OS+essentials)

sda (931.5GB SATA SSD)       → Primary VM storage
  └─ vm-storage: 912.8GB     (VM disks - currently ~565GB used)
     ├─ VM 100: 432GB used
     ├─ VM 101: 132GB used
     └─ Available: ~348GB
```

### Backup & Archive Storage (New)
```
sdb (9.1TB SATA HDD)         → Long-term backup + future archive
  ├─ backup-pool: 8TB        (backup destination - cheap, reliable)
  └─ smb-share: 1TB          (network archive - future camera/media use)
```

---

## Capacity Forecast

| Tier | Device | Total | Used | Available | Growth |
|------|--------|-------|------|-----------|--------|
| **Hot** | NVMe | 141.5GB | 10GB | 131.5GB | 6mo buffer |
| **Warm** | SATA SSD | 912.8GB | 565GB | 347.8GB | 9mo buffer |
| **Cold** | SATA HDD | 8000GB | 0GB | 8000GB | 2+ years |
| **Archive** | SATA HDD | 1000GB | 0GB | 1000GB | Future use |

**Total Storage**: 10.05TB usable | **Total Capacity**: ~14TB raw

---

## Disk Layout Summary for Documentation

### Proxmox Storage Tiers

**Tier 1: NVMe SSD (238.5GB) - Proxmox OS**
- Role: Hypervisor OS + emergency VM cache
- Capacity: 141.5GB usable (pve-data)
- Current use: 10GB (VM 102)
- Retention: System critical

**Tier 2: SATA SSD (931.5GB) - Production VMs**
- Role: Active VM workloads
- Capacity: 912.8GB usable
- Current use: ~565GB (VMs 100, 101)
- Access speed: Fast (SSD)
- Backup targets: Yes

**Tier 3: SATA HDD (9.1TB) - Backups & Archive**
- Role: Backup destination + network archive
- Partition 1 - backup-pool (8TB): Proxmox VM backups
- Partition 2 - smb-share (1TB): Network share (future media/camera archive)
- Access speed: Slow (HDD) - acceptable for backups
- Network share: SMB/CIFS via Samba

---

## Timeline
- **Week 1**: Partition sdb, create LVM volumes, mount, add to Proxmox
- **Week 2**: Configure backup jobs, setup Samba SMB share
- **Week 3**: Test backups, verify restore procedures, monitor stability
- **Week 4**: Optimize, document final configuration

---

## Execution Checklist

### Phase 1: LVM Disk Setup
- [ ] Execute all commands in Phase 1
- [ ] Verify: `df -h | grep -E "backup-pool|smb-share"` shows both mounts
- [ ] Verify: `lsblk` shows both LV under vg-backup
- [ ] Verify: `pvdisplay`, `vgdisplay`, `lvdisplay` output is correct
- [ ] Verify: `/etc/fstab` has both entries (check: `cat /etc/fstab | grep backup`)

### Phase 2: Add to Proxmox UI
- [ ] Datacenter → Storage → Add both pools
- [ ] Verify both pools appear in Storage list
- [ ] Verify both pools show as "Available" (green checkmark)
- [ ] Verify size display is correct (~8TB, ~1TB)

### Phase 3: Configure Backups
- [ ] Create backup jobs for VMs 100, 101, 102 → backup-pool
- [ ] Run first test backup (start with smallest VM)
- [ ] Verify backup file appears in `/mnt/pve/backup-pool`
- [ ] Test restore from backup

### Phase 4: Setup SMB Share
- [ ] Install Samba: `apt update && apt install samba samba-common-bin`
- [ ] Configure `/etc/samba/smb.conf` with media-archive share
- [ ] Restart Samba: `systemctl restart smbd`
- [ ] Test from Docker host: `smbclient -L //192.168.50.20`
- [ ] Mount share on Docker host: `mount -t cifs //192.168.50.20/media-archive ...`

### Phase 5: Update Documentation
- [ ] Update `home_network.md` with new storage pools
- [ ] Add SMB share details to documentation
- [ ] Add Samba credentials/access info
- [ ] Mark this plan as "COMPLETED"

---

## Next Actions
1. ✅ Review this revised plan (DONE - 2026-04-30)
2. ✅ Confirm 8TB backup + 1TB SMB split (CONFIRMED)
3. ✅ Phase 1: LVM setup on sdb (DONE - 2026-04-30)
4. ✅ Phase 2: Add storage pools to Proxmox (DONE - via `pvesm add dir`)
5. ✅ Phase 3: Backup job created (DONE - 2026-04-30, daily 02:00)
6. ✅ Phase 4: Samba SMB share live (DONE - 2026-04-30)
7. ✅ Update `home_network.md` with final configuration (DONE)

**ALL PHASES COMPLETE** 🎉

---

## Implementation Log (2026-04-30)

**Disk wipe**: sdb had a previous NTFS partition ("Seagate Backup Plus Drive") that was wiped per user confirmation. New GPT partition table created with single LVM partition.

**Final state:**
- `/dev/sdb1` (9.1TB) → PV → `vg-backup`
- `vg-backup/backup-pool` (8TB) → ext4 → `/mnt/pve/backup-pool`
- `vg-backup/smb-share` (1TB) → ext4 → `/mnt/pve/smb-share`
- ~98GB free in vg-backup for future expansion
- Both pools registered with Proxmox: `pvesm status` shows them active
