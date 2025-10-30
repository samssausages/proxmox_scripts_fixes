Cloud init:

## Updated for Debian 13

## Docker.yml
- Installs Docker
- Sets some reasonable defaults
- Disable Root Login
- Disable Password Authentication (SSH Only! Add your SSH keys in the file)
- Installs Unattended Upgrades (Security Updates Only)
- Installs qemu-guest-agent
- Installs cloud-guest-utils (for growpart, to auto grow disk if you expand it later)
- Installs systemd-zram-generator for swap (to reduce disk I/O and improve performance on VMs with low RAM)
- Shuts down the VM after cloud-init is complete

## Docker_graylog.yml

- Installs Docker
- Sets some reasonable defaults
- Disable Root Login
- Disable Password Authentication (SSH Only! Add your SSH keys in the file)
- Installs Unattended Upgrades (Security Updates Only)
- Installs qemu-guest-agent
- Installs cloud-guest-utils (for growpart, to auto grow disk if you expand it later)
- Installs systemd-zram-generator for swap (to reduce disk I/O and improve performance on VMs with low RAM)
- Configures Remote Logging for Docker to Graylog using GELF (DOCKER MUST BE ABLE OT ACCESS GELF SERVER OR ERROR WILL BE PRODUCED WHEN YOU COMPOSE UP)
- Configures VM with rsyslog and forwards to log server using rsyslog
- Persistent Local Logging is disabled!  We forward all logs to external syslog and we save local logs to memory only.  (To reduce disk utilization)  This means logs will be lost on reboot and will live on your syslog server only.
- Shuts down the VM after cloud-init is complete
NOTE: Make sure you set your syslog IP address in the .yml file, or it will use the default IP causing it to fail. 

## Step By Step Guide to using these files:

### 1. Download the Cloud Init Image for Debian 13

Find newest version here:
https://cloud.debian.org/images/cloud/trixie/

As of writing this, the most current amd64 is: 
https://cloud.debian.org/images/cloud/trixie/20251006-2257/debian-13-genericcloud-amd64-20251006-2257.qcow2

Save to your proxmox server, e.g.:
`/mnt/pve/smb/template/iso/debian-13-genericcloud-amd64-20251006-2257.qcow2`

### 2. Create the cloud init snippet file

Create a file in your proxmox server at e.g.:
`/mnt/pve/smb/snippets/cloud-init-debian13-docker.yaml`

Copy/Paste Content from docker.yml or docker_graylog.yml

### 3. Create a new VM in Proxmox: (note path to the cloud-init from step 1 and path to snipped file created in step 2)

```
# Choose a VM ID
VMID=9100
# Choose a name
NAME=debian13-docker
# Storage to use
ST=apool
# Path to Cloud Init Image from step 1
IMG=/mnt/pve/smb/template/iso/debian-13-genericcloud-amd64-20251006-2257.qcow2
# Storage location for the cloud init drive from step 2: (note must show proxmox storage type, and path)
YML=user=smb:snippets/cloud-init-debian13-docker.yaml

# VM Settings
qm create $VMID --name $NAME --cores 2 --memory 2048 --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci --agent 1
qm importdisk $VMID $IMG $ST
qm set $VMID --scsi0 $ST:vm-$VMID-disk-0
qm set $VMID --ide2 $ST:cloudinit --boot order=scsi0
# Storage location for the cloud init drive from step 2:
qm set $VMID --cicustom "$YML"
qm template $VMID

```
### 4. Deploy a new VM from the template we just created

- Go to the Template you just created in the Proxmox GUI and config the cloud-init settings as needed (e.g. set hostname, set IP address if not using DHCP)  (SSH keys are set in out snippet file)

- Click "Generate Cloud-Init Configuration"

- Right click the template -> Clone

### 5. Start the new VM & allow enough time for cloud-init to complete 

It may take 5-10 minutes depending on your internet speed, as it downloads packages and updates the system.  The VM will turn off when cloud-init is completed.
You can kind of monitor progress by looking at the VM console output in Proxmox GUI.  But sometimes that doesnt' refresh properly, so best to just wait until it shuts down.
If the VM doesn't shut down and just sits at a login prompt, then cloud-init likely failed.  Check troubleshooting section below.

### 7. Remove cloud-init drive to prevent re-running cloud-init on boot

### 8. Access your new VM

- check logs inside VM to confirm cloud-init completed successfully:

```
sudo cloud-init status --long
```

### 9. Increase the VM disk size if needed & reboot VM (optional)

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