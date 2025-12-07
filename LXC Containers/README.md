# LXC Creation, optimized for Debian 13

## What is this?
I made this so I could start a new LXC, configured and hardened, as quickly as possible.

### lxc-bootstrap
- Disable Root Login
- Setup Admin user
- Installs sudo
- Disable Password Authentication (SSH Only! Add your SSH keys when you create the LXC in the Proxmox GUI)
- Installs Unattended Upgrades
- Installs fail2ban to monitor logs for intrusion attempts
- Hardens SSHD
- Some sysctl hardening, but may not do much since we're in a CT.  (Remove 20-hardening.conf if you use multiple NIC's)
- disable fstrim

### lxc-bootstrap-external-syslog

- Same as lxc-bootstrap, plus:
- Saves system logs to memory only to reduce disk I/O
- Installs rsyslog to forward logs to external syslog server (update with your syslog IP or edit /etc/rsyslog.d/01-graylog.conf accordingly)

## Instructions

### 1. Create your LXC in Proxmox and start it (Make sure you add ssh keys!)

<details>
  <summary>Debian 13 LXC Creation Commands</summary>

```
# ------------ Begin Required Config ------------- #
# Set your CT ID
VMID=1300
HOSTNAME="debian13-lxc"
DISK_SIZE_GB=16
MEMORY_MB=2048
SWAP_MB=512
CPUS=2

TEMPLATE_STORAGE="local"     # storage for debian 13 template
ROOTFS_STORAGE="local-zfs"   # storage for container disk

# Networking
BRIDGE="vmbr0"
VLAN_TAG=""

# ------------ SSH KEYS (EDIT THESE) ------------ #
# Put all your public keys here, one per line.
SSH_KEYS_TEXT=$(cat << 'EOF'
ssh-ed25519 AAAA... user1@host
ssh-ed25519 AAAA... user2@host
EOF
)

# ------------ End Required Config ------------- #

# debian image to download
CT_TEMPLATE="debian-13-standard_13.1-2_amd64.tar.zst"

# Temp file to hold the keys during creation
SSH_KEY_FILE="/root/ct-${VMID}-ssh-keys.pub"

# Fail if it's just empty/whitespace
if ! printf '%s\n' "$SSH_KEYS_TEXT" | grep -q '[^[:space:]]'; then
  echo "ERROR: SSH_KEYS_TEXT is empty or whitespace. Add at least one SSH public key." >&2
  exit 1
fi

# Write keys to temp file
printf '%s\n' "$SSH_KEYS_TEXT" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

# Validate using ssh-keygen (parses OpenSSH authorized_keys format)
if ! ssh-keygen -l -f "$SSH_KEY_FILE" >/dev/null 2>&1; then
  echo "ERROR: SSH_KEYS_TEXT does not contain valid SSH public key(s)." >&2
  rm -f "$SSH_KEY_FILE"
  exit 1
fi

FEATURES="nesting=1,keyctl=1"
UNPRIVILEGED=1

# Download template
pveam download "$TEMPLATE_STORAGE" "$CT_TEMPLATE" || echo "Template may already exist, continuing..."

# Build net0 from the vars above (DHCP only)
NET0="name=eth0,bridge=${BRIDGE},ip=dhcp"
[ -n "$VLAN_TAG" ] && NET0="${NET0},tag=${VLAN_TAG}"

# Create the container
pct create "$VMID" "${TEMPLATE_STORAGE}:vztmpl/${CT_TEMPLATE}" \
  --hostname "$HOSTNAME" \
  --ostype debian \
  --rootfs "${ROOTFS_STORAGE}:${DISK_SIZE_GB}" \
  --memory "$MEMORY_MB" \
  --swap "$SWAP_MB" \
  --cores "$CPUS" \
  --net0 "$NET0" \
  ${NAMESERVER:+--nameserver "$NAMESERVER"} \
  --unprivileged "$UNPRIVILEGED" \
  --features "$FEATURES" \
  --ssh-public-keys "$SSH_KEY_FILE"

# Clean up temp ssh file
rm -f "$SSH_KEY_FILE"
echo "Temp SSH file cleaned: $SSH_KEY_FILE"

```

</details>

### 2. Update our lxc-bootstrap config file with your info.

Review the file "lxc-bootstrap" and edit it to suit your system.  These are the items you need to look at:

Update your timezone:

```

--- timezone ---

```

Add your IP(s) to the fail2ban "ignoreip"

```

--- fail2ban policy ---

```

If using the external syslog version, update the config with your external syslog server IP.

```

--- rsyslog forwarder ---

```

### 3. Log into LXC and Copy / Paste entire file contents of the lxc-bootstrap file directly into your LXC's CLI

### 4.  Use LXC as is!

### 5. (Optional)  Turn LXC into blank template!

Strip identity

From inside the LXC:

```
# Blank machine id
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id 2>/dev/null || true
# Force new SSH host key
sudo rm -f /etc/ssh/ssh_host_* || true
# clean logs and history
sudo find /var/log -type f -delete || true
sudo rm -f /root/.bash_history /home/admin/.bash_history 2>/dev/null || true

```
Shutdown the LXC and convert it to a template in Proxmox

Done!

### FAQ

 - The Proxmox storage isn't correctly setup to accept CT Templates.  i.e. local, local-zfs etc.  It's not a path, it's the name of the proxmox storage.
 - After installing inside the lxc, root will be disabled.  You will need to login with "admin".