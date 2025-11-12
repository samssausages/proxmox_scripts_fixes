# Cloud init, optimized for Debian 13

## What is this?

I made this so you can spin up a new VM, with Docker pre-installed, and everything configured - in minutes.
I do this by providing you with all the proxmox CLI commands to prevision a new VM quickly and ready for cloud-init.

Cloud-init is one of the fastest ways to spin up a pre-configured new VM.
The cloud-init config file runs on VM first boot and installs, updates and configures all of our apps for us!
Simply add your docker-compose.yml file and go!

I have spent a lot of time making sure this follows best practices for security and stability.  If you have suggestions on how to improve, let me know!

## Docker.yml

- Installs Docker
- Sets some reasonable defaults
- Disable Root Login
- Disable Password Authentication (SSH Only! Add your SSH keys in the file)
- Installs Unattended Upgrades (Critical only, no auto reboot)
- Installs qemu-guest-agent
- Installs cloud-guest-utils (To auto grow disk if you expand it later. Auto expands at boot)
- Uses separate disk for appdata, mounted to /mnt/appdata.  The entire docker folder (/var/lib/docker/) is mounted to /mnt/appdata/docker.  Default is 16GB, you can grow it in proxmox if needed.
- Mounts /mnt/appdata with with nodev for additional security
- Installs systemd-zram-generator for swap (to reduce disk I/O)
- Shuts down the VM after cloud-init is complete
- Dumps cloud-init log file at /home/admin/logs on first boot

## Docker_graylog.yml

- Same as Docker.yml Plus:
- Configures VM with rsyslog and forwards to log server using rsyslog (Make sure you set your syslog server IP in the file.)
- To reduce disk I/O, persistent Local Logging is disabled.  I forward all logs to external syslog and keep local logs in memory only.  This means logs will be lost on reboot and will live on your syslog server only.

## Step By Step Guide to using these files:

### 1. Batch commands to create a new VM Template in Proxmox.

Edit the configurables that you care about and then you can simply copy/paste the entire block into your CLI.

Note: Currently does not work with VM storage set to "local".  These commands assume you're using zfs for VM storage. (snippet and ISO storage can be local, but VM provisioning commands are not compatible with local storage.)  

##### Provision VM - Debian 13 - Docker - Local Logging

<details>
  <summary>Debian 13 - Docker - Local Logging</summary>

```
# ------------ Begin Required Config ------------- #

# Set your VMID
VMID=9000

# Set your VM Name
NAME=debian13-docker

# Name of your Proxmox Snippet Storage: (examples: local, local-zfs, smb, rpool.)
SNIPPET_STORAGE_NAME=bertha-smb

# Path to your Proxmox Snippet Storage: (Local storage is usually mounted at /var/lib/vz/snippets, remote at /mnt/pve/)
SNIPPET_STORAGE_PATH=/mnt/pve/bertha-smb/snippets

# Path to your Proxmox ISO Storage: (Local storage is usually mounted at /var/lib/vz/template/iso, remote at /mnt/pve/)
ISO_STORAGE_PATH=/mnt/pve/bertha-smb/template/iso

# Name of your Proxmox VM Storage: (examples: local, local-zfs, smb, rpool)
VM_STORAGE_NAME=apool

# ------------ End Required Config ------------- #

# ------------ Begin Optional Config ------------- #

# Size of your Appdata Disk in GB
APPDATA_DISK_SIZE=16

# VM Hardware Config
CPU=4
MEM_MIN=1024
MEM_MAX=4096

# ------------ End Optional Config ------------- #

# Grab Debian 13 ISO
wget -O $ISO_STORAGE_PATH/debian-13-genericcloud-amd64-20251006-2257.qcow2 https://cloud.debian.org/images/cloud/trixie/20251006-2257/debian-13-genericcloud-amd64-20251006-2257.qcow2

# Grab Cloud Init yml
wget -O $SNIPPET_STORAGE_PATH/cloud-init-debian13-docker.yaml https://raw.githubusercontent.com/samssausages/proxmox_scripts_fixes/708825ff3f4c78ca7118bd97cd40f082bbf19c03/cloud-init/docker.yml

# Generate unique serial and wwn for appdata disk
APP_SERIAL="APPDATA-$VMID"
APP_WWN="$(printf '0x2%015x' "$VMID")"

# Create the VM
qm create $VMID \
  --name $NAME \
  --cores $CPU \
  --cpu host \
  --memory $MEM_MAX \
  --balloon $MEM_MIN \
  --net0 virtio,bridge=vmbr100,queues=$CPU,firewall=1 \
  --scsihw virtio-scsi-single \
  --serial0 socket \
  --vga serial0 \
  --cicustom "vendor=$SNIPPET_STORAGE_NAME:snippets/cloud-init-debian13-docker.yaml" \
  --agent 1 \
  --ostype l26 \
  --localtime 0 \
  --tablet 0

qm set $VMID -rng0 source=/dev/urandom,max_bytes=1024,period=1000
qm set $VMID --ciuser admin --ipconfig0 ip=dhcp
qm importdisk $VMID "$ISO_STORAGE_PATH/debian-13-genericcloud-amd64-20251006-2257.qcow2" "$VM_STORAGE_NAME"
qm set $VMID --scsi0 $VM_STORAGE_NAME:vm-$VMID-disk-0,ssd=1,discard=on,iothread=1
qm set $VMID --scsi1 $VM_STORAGE_NAME:$APPDATA_DISK_SIZE,ssd=1,discard=on,iothread=1,backup=1,serial=$APP_SERIAL,wwn=$APP_WWN
qm set $VMID --ide2 $VM_STORAGE_NAME:cloudinit --boot order=scsi0
qm template $VMID
```

</details>

##### Provision VM - Debian 13 - Docker - Remote Syslog

<details>
  <summary>Debian 13 - Docker - Remote Syslog Logging</summary>

```
# ------------ Begin Required Config ------------- #

# Set your VMID
VMID=9000

# Set your VM Name
NAME=debian13-docker

# Name of your Proxmox Snippet Storage: (examples: local, local-zfs, smb, rpool.)
SNIPPET_STORAGE_NAME=bertha-smb

# Path to your Proxmox Snippet Storage: (Local storage is usually mounted at /var/lib/vz/snippets, remote at /mnt/pve/)
SNIPPET_STORAGE_PATH=/mnt/pve/bertha-smb/snippets

# Path to your Proxmox ISO Storage: (Local storage is usually mounted at /var/lib/vz/template/iso, remote at /mnt/pve/)
ISO_STORAGE_PATH=/mnt/pve/bertha-smb/template/iso

# Name of your Proxmox VM Storage: (examples: local, local-zfs, smb, rpool)
VM_STORAGE_NAME=apool

# ------------ End Required Config ------------- #

# ------------ Begin Optional Config ------------- #

# Size of your Appdata Disk in GB
APPDATA_DISK_SIZE=16

# VM Hardware Config
CPU=4
MEM_MIN=1024
MEM_MAX=4096

# ------------ End Optional Config ------------- #

# Grab Debian 13 ISO
wget -O $ISO_STORAGE_PATH/debian-13-genericcloud-amd64-20251006-2257.qcow2 https://cloud.debian.org/images/cloud/trixie/20251006-2257/debian-13-genericcloud-amd64-20251006-2257.qcow2

# Grab Cloud Init yml
wget -O $SNIPPET_STORAGE_PATH/cloud-init-debian13-docker-log.yaml https://raw.githubusercontent.com/samssausages/proxmox_scripts_fixes/52620f2ba9b02b38c8d5fec7d42cbcd1e0e30449/cloud-init/docker_graylog.yml


# Generate unique serial and wwn for appdata disk
APP_SERIAL="APPDATA-$VMID"
APP_WWN="$(printf '0x2%015x' "$VMID")"

# Create the VM
qm create $VMID \
  --name $NAME \
  --cores $CPU \
  --cpu host \
  --memory $MEM_MAX \
  --balloon $MEM_MIN \
  --net0 virtio,bridge=vmbr100,queues=$CPU,firewall=1 \
  --scsihw virtio-scsi-single \
  --serial0 socket \
  --vga serial0 \
  --cicustom "vendor=$SNIPPET_STORAGE_NAME:snippets/cloud-init-debian13-docker-log.yaml" \
  --agent 1 \
  --ostype l26 \
  --localtime 0 \
  --tablet 0

qm set $VMID -rng0 source=/dev/urandom,max_bytes=1024,period=1000
qm set $VMID --ciuser admin --ipconfig0 ip=dhcp
qm importdisk $VMID "$ISO_STORAGE_PATH/debian-13-genericcloud-amd64-20251006-2257.qcow2" "$VM_STORAGE_NAME"
qm set $VMID --scsi0 $VM_STORAGE_NAME:vm-$VMID-disk-0,ssd=1,discard=on,iothread=1
qm set $VMID --scsi1 $VM_STORAGE_NAME:$APPDATA_DISK_SIZE,ssd=1,discard=on,iothread=1,backup=1,serial=$APP_SERIAL,wwn=$APP_WWN
qm set $VMID --ide2 $VM_STORAGE_NAME:cloudinit --boot order=scsi0
qm template $VMID
```

</details>

### 2a. Add your SSH keys to the cloud-init YAML file

Open the cloud-init YAML file that you downloaded to your Proxmox snippets folder and add your SSH public keys to the "ssh_authorized_keys:" section.

```
nano $SNIPPET_STORAGE_PATH/cloud-init-debian13-docker.yaml
```

### 2b. If you are using the Docker_graylog.yml file, set your syslog server IP address

### 3.  Set Network info in Proxmox GUI and generate cloud-init config

In the Proxmox GUI, go to the cloud-init section and configure as needed (i.e. set IP address if not using DHCP). SSH keys are set in our snippet file, but I add them here anyways. Keep the user name as "admin". Complex network setups may require you to set your DNS server here.

Click "Generate Cloud-Init Configuration"

Right click the template -> Clone

### 4. Get new VM clone ready to launch

This is your last opportunity to make any last minute changes to the hardware config.  I usually set the MAC address on the NIC and let my DHCP server assign an IP.

### 5. Launch new VM for the first time

Start the new VM and wait.  It may take 2-10 minutes depending on your system and internet speed.  The system will now download packages and update the system.  The VM will turn off when cloud-init is finished.

If the VM doesn't shut down and just sits at a login prompt, then cloud-init likely failed.  Check logs for failure reasons.  Validate cloud-init and try again.

### 6. Remove cloud-init drive from the "hardware" section before starting your new VM

### 7. Access your new VM!

Check logs inside VM to confirm cloud-init completed successfully, they will be in the /home/logs directory

### 8. (Optional) Increase the VM disk size in proxmox GUI, if needed & reboot VM

### 9. Add and Compose up your docker-compose.yml file and enjoy your new Docker Debian 13 VM!

### Troubleshooting:

Check Cloud-Init logs from inside VM.  We dump them to /home/logs  This should be your first step if something is not working as expected and done after first vm boot.

Additional commands to validate config files and check cloud-init logs:

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

### FAQ & Common Reasons for Cloud-Init Failures:

- Incorrect YAML formatting (use a YAML validator to check your file & run cloud-init schema validate commands)
- Network issues preventing package downloads - Your VM can't access the web
- Incorrect SSH key format
- Insufficient VM resources (CPU, RAM)
- Proxmox storage name doesn't match what is in the commands
- Your not using the proxmox mounted "snippet" folder

### Changelog:

11-12-2025
- Made Appdata disk serial unique, generated & detectable by cloud-init
- Hardened docker appdata mount
- Dump cloud-init log into /home/logs on first boot
- Added debug option to logging (disabled by default)
- Made logging more durable by setting limits & queue
- Improved readme
- Improved and expanded proxmox CLI Template Commands
- Greatly simplified setup process