# Proxmox SWAP Setup instructions

## Check for existing swap

If you have an existing swap setup it should show here.  We need to remove it.

```
swapon --show --bytes
```

Check if you have swap in fstab (remove if you have it)

```
zramctl || true
```
## Purge Existing Swap

```
# Turn off all active swap now
swapoff -a

# If you used zram-tools in the past, stop and remove it
systemctl disable --now zramswap.service 2>/dev/null || true
apt-get -y purge zram-tools 2>/dev/null || true

# Remove stale fstab swap lines
nano /etc/fstab

```

## Install Swap

(optional)  Create ZFS Zvol for swap

```
zfs create -V 32G -b $(getconf PAGESIZE) \
    -o logbias=throughput -o sync=always \
    -o primarycache=metadata \
    -o com.sun:auto-snapshot=false apool/swap
```

```
cat >/etc/default/zramswap <<'EOF'

ALLOCATION=16384   # 8GB
PERCENT=25        # % of system RAM
PRIORITY=100       # high priority
EOF
```

```
apt update && apt install zram-tools
```

```
systemctl restart zramswap
swapon --show   # verify /dev/zram0 16G pri 100
```

```
truncate -s 32G /apool/swap
chmod 600 /apool/swap
mkswap /apool/swap
swapon -p 10 /apool/swap
```

Mount on boot

```
/dev/zvol/apool/swap none swap defaults,pri=10 0 0
```

Set Swapiness

```
echo 'vm.swappiness=10' >> /etc/sysctl.conf   # swap only under real pressure
sysctl -p
```






## Test Swap Setup

Setup Monitor in Shell A

```
watch -n1 'free -h; echo; swapon --show --bytes; echo; grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree)" /proc/meminfo'
```

Setup Monitor in Shell B

```
watch -n1 'printf "zram0 mm_stat: "; cat /sys/block/zram0/mm_stat; echo; zpool iostat -v 1 1 || true'
```

Create RAM Pressure in Shell C (Adjust memory close to your mem limit, plus swap.  If you have 128gb RAM & 32GB Swap, try 110gb)

Prep Test Folder

```
mkdir -p /mnt/tmpfs-test
mount -t tmpfs -o size=110G tmpfs /mnt/tmpfs-test
```

Run Test

```
for i in $(seq 1 110000); do
  dd if=/dev/zero of=/mnt/tmpfs-test/f$i bs=1M count=1 status=none || break
  if ! ((i%1000)); then echo "Wrote ${i}M"; fi
done
```

Cleanup

```
rm -f /mnt/tmpfs-test/bloat /mnt/tmpfs-test/f*
umount /mnt/tmpfs-test
rmdir /mnt/tmpfs-test
```