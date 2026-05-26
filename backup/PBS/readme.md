# Proxmox Backup Server

Basic info on how to run a manual host backup and send it to PBS.  (Backup the Proxmox hypervisor to PBS using CLI)

Restoring Proxmox is quite simple.  You only need to backup the Proxmox database mounted to /etc/pve and any of the custom system files you may have changed in /etc/, such as a custom syslog server and networking config files.  (You can't just copy the /etc/pve, it's a mounted database & can cause corruption.  Use PBS or stop PVE services first)
VM disks and CT's are not backed up by this, they are handled by the normal PBS backup jobs.

## Prep:

Create new user account in PBS that only has the "DatastoreBackup" Role.

  1.  PBS > Access Control > User Management > Add > username & Password & Realm = PBS
  2.  Permissions > Add > Path of your datastore & User & Role = DatastoreBackup

Get connection information.
  1.  Datastore > Your Datastore > Show Connection Information > Note Fingerprint, server & user info.
  2.  If using encryption, create key or use keyfile. (see docs)

## Raw syntax example used to run the backup.

Example for my setup, where I have server "hv4" with user accoung account "backup-hv4", that is under Realm "pbs", and is backing up to datastore "pbs-ext4"
(Not my real Password & Fingerprint)


```
export PBS_AUTH_ID='backup-hv4@pbs'
export PBS_SERVER='pbs.mydomain.tdl'  # If you use an IP replace with something like '10.1.2.60'
export PBS_DATASTORE='pbs-ext4'
export PBS_PASSWORD='l38y79yhfdsa87t72t8#@^g789t9df'
export PBS_FINGERPRINT='74:59:56:dd:2b:1b:7f:5e:dd:0a:da:65:b6:77:01:4a:55:c6:c7:92:63:b6:c6:c3:61:7b:2f:f6:46:d6:03:23'
proxmox-backup-client backup \
  root.pxar:/ \
  pve-config.pxar:/etc/pve \
  --backup-type host \
  --backup-id "$(hostname)" \
  --exclude /dev \
  --exclude /proc \
  --exclude /sys \
  --exclude /run \
  --exclude /tmp \
  --exclude /mnt \
  --exclude /media \
  --exclude /var/tmp \
  --exclude /var/lib/vz/dump \
  --exclude /var/lib/vz/images \
  --exclude /var/lib/vz/template
```

## Example Username:
```
user@pbs
root@pam
backup@pbs!token
```

## Optional:

PBS_ENCRYPTION_PASSWORD if you want to use encryption.  Also note docs for:
PBS_ENCRYPTION_PASSWORD_FILE

https://pbs.proxmox.com/docs/backup-client.html#encryption

- If you don't want to type a password in the CLI, refer to this:

https://pbs.proxmox.com/docs/backup-client.html#system-and-service-credentials

- How to Restore:

https://pbs.proxmox.com/docs/backup-client.html#restoring-data

- Full proxmox-backup-client documentation:

https://pbs.proxmox.com/docs/backup-client.html#