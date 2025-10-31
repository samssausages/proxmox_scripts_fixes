Cloud init:

## Updated for Debian 13

## Docker.yml
- Installs Docker
- Sets some reasonable defaults
- Disable Root Login
- Disable Password Authentication (SSH Only! Add your SSH keys in the file)
- Installs Unattended Upgrades (Security Updates Only)
- Installs qemu-guest-agent
- Installs cloud-guest-utils (for growpart, to auto grow disk if you expand it later. Auto expands at boot)
- Uses separate disk for appdata, mounted to /mnt/appdata (entire docker folder (/var/lib/docker/) is mounted to /mnt/appdata/docker)
- Installs systemd-zram-generator for swap (to reduce disk I/O)
- Shuts down the VM after cloud-init is complete

## Docker_graylog.yml

- Installs Docker
- Sets some reasonable defaults
- Disable Root Login
- Disable Password Authentication (SSH Only! Add your SSH keys in the file)
- Installs Unattended Upgrades (Security Updates Only)
- Installs qemu-guest-agent
- Installs cloud-guest-utils (for growpart, to auto grow disk if you expand it later. Auto expands at boot)
- Uses separate disk for appdata, mounted to /mnt/appdata (entire docker folder (/var/lib/docker/) is mounted to /mnt/appdata/docker)
- Installs systemd-zram-generator for swap (to reduce disk I/O)
- Shuts down the VM after cloud-init is complete
- Configures VM with rsyslog and forwards to log server using rsyslog (Make sure you set your syslog server IP in the file.  Same for the docker GELF logging driver settings)
- Persistent Local Logging is disabled!  We forward all logs to external syslog and we keep local logs in memory only to reduce disk I/O.  This means logs will be lost on reboot and will live on your syslog server only.

## Step By Step Guide to using these files:

### 1. Download the Cloud Init Image for Debian 13

Find newest version here:
https://cloud.debian.org/images/cloud/trixie/

As of writing this, the most current amd64 is: 
https://cloud.debian.org/images/cloud/trixie/20251006-2257/debian-13-genericcloud-amd64-20251006-2257.qcow2

Save to your proxmox server, e.g.:
`/mnt/pve/smb/template/iso/debian-13-genericcloud-amd64-20251006-2257.qcow2`

```
wget https://cloud.debian.org/images/cloud/trixie/20251006-2257/debian-13-genericcloud-amd64-20251006-2257.qcow2
```

### 2. Create the cloud init snippet file

Create a file in your proxmox server at e.g.:
`/mnt/pve/smb/snippets/cloud-init-debian13-docker.yaml`

#### for docker.yml:
```
wget -O ./cloud-init-debian13-docker.yaml https://raw.githubusercontent.com/samssausages/proxmox_scripts_fixes/708825ff3f4c78ca7118bd97cd40f082bbf19c03/cloud-init/docker.yml
```

#### for docker_graylog.yml:
```
wget -O ./cloud-init-debian13-docker-log.yaml https://github.com/samssausages/proxmox_scripts_fixes/blob/708825ff3f4c78ca7118bd97cd40f082bbf19c03/cloud-init/docker_graylog.yml
```


### 3. Create a new VM in Proxmox.  You can config the VM here and past all of this into the CLI:
(note path to the cloud-init from step 1 and path to snipped file created in step 2)

```
# ------------ Begin User Config ------------- #
# Choose a VM ID
VMID=9300

# Choose a name
NAME=debian13-docker

# Storage to use
ST=apool

# Path to Cloud Init Image from step 1
IMG=/mnt/pve/bertha-smb/template/iso/debian-13-genericcloud-amd64-20251006-2257.qcow2

# Storage location for the cloud init drive from step 2 (must be on proxmox snippet storage and include proxmox storage + snippets path)
YML=user=bertha-smb:snippets/cloud-init-debian13-docker.yaml

# VM CPU Cores
CPU=4

# VM Memory (in MB)
MEM=4096

# VM Appdata Disk Size (in GB)
APPDATA_DISK_SIZE=32

# ------------ End User Config ------------- #

# Create VM
qm create $VMID \
  --name $NAME \
  --cores $CPU \
  --memory $MEM \
  --net0 virtio,bridge=vmbr1 \
  --scsihw virtio-scsi-single \
  --agent 1

# Import the Debian cloud image as the first disk
qm importdisk $VMID "$IMG" "$ST"

# Attach the imported disk as scsi0 (enable TRIM/discard and mark as SSD; iothread is fine with scsi-single)
qm set $VMID --scsi0 $ST:vm-$VMID-disk-0,ssd=1,discard=on,iothread=1

# Create & attach a NEW second disk as scsi1 on the same storage
qm set $VMID --scsi1 $ST:$APPDATA_DISK_SIZE,ssd=1,discard=on,iothread=1

# Cloud-init drive
qm set $VMID --ide2 $ST:cloudinit --boot order=scsi0

# Point to your cloud-init user-data snippet
qm set $VMID --cicustom "$YML"

# SERIAL CONSOLE (video → serial0)
qm set $VMID --serial0 socket
qm set $VMID --vga serial0

# Convert to template
qm template $VMID

```
### 4. Deploy a new VM from the template we just created

- Go to the Template you just created in the Proxmox GUI and config the cloud-init settings as needed (e.g. set hostname, set IP address if not using DHCP)  (SSH keys are set in out snippet file)

- Click "Generate Cloud-Init Configuration"

- Right click the template -> Clone

### 5. Start the new VM & allow enough time for cloud-init to complete 

It may take 5-10 minutes depending on your internet speed, as it downloads packages and updates the system.  The VM will turn off when cloud-init is completed.
You can kind of monitor progress by looking at the VM console output in Proxmox GUI.  But sometimes that doesn't refresh properly, so best to just wait until it shuts down.
If the VM doesn't shut down and just sits at a login prompt, then cloud-init likely failed.  Check logs for failure reasons.

### 7. Remove cloud-init drive to prevent re-running cloud-init on boot

### 8. Access your new VM

- check logs inside VM to confirm cloud-init completed successfully:

```
sudo cloud-init status --long
```

### 9. Increase the VM disk size in proxmox GUI, if needed & reboot VM (optional)

### 9. Enjoy your new Docker Debian 13 VM!

### Troubleshooting:

Check Cloud-Init logs from inside VM.  This should be your first step if something is not working as expected and done after first vm boot:

```
sudo cloud-init status --long
```

Cloud init validate file from host:

```
cloud-init schema --config-file ./cloud-config.yml --annotate
```

Cloud init validate file from inside VM:

```
sudo cloud-init schema --system --annotate
``` 
### Common Reasons for Cloud-Init Failures:
- Incorrect YAML formatting (use a YAML validator to check your file)
- Network issues preventing package downloads
- Incorrect SSH key format
- Insufficient VM resources (CPU, RAM)
- Proxmox storage name not matching what is in the commands