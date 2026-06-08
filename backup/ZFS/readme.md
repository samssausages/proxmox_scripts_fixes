# Script to use with Sanoid Backups on linux

FYI, I don't use this script day to day, I use another version that I made specifically for unraid.  If you run into unexpected behavior with this version, let me know and I'll have a look at it!
This script is designed to be used with Sanoid to facilitate backups of ZFS datasets. It automates the process of creating snapshots and managing backup retention by generating a Sanoid configuration file for you.
The script is made to backup just one dataset at a time, so you will need to create multiple scripts if you have multiple datasets to back up.
Use iterate_backups.sh to iterate through multiple scripts, by placing them all in one directory and running iterate_backups.sh with that directory as an argument.

Default script behavior is to send a ZFS sanpshot.  But the script also has an "Rsync Mode" that can be enabled by setting the "replication" variable to "rsync".  In this mode, the script will use rsync to copy files from the source dataset to the destination dataset instead of using ZFS send/receive.  This can be useful if you are backing up to a non-ZFS filesystem.

Script can also send to remote systems via SSH.

## Prerequisites
- Linux with ZFS
- Sanoid installed

## Installation
1. Download the script from this repository to a suitable directory on your server, e.g., `/usr/local/bin/backups/`.
2. Make the script executable:

   ```
   bash
   chmod +x /usr/local/bin/backups/backup_zfs.sh
    ```
(if using multiple scripts, make all of them executable, including iterate_bbackups.sh)

Changelog:
6-8-2026
- Script would not overwrite sanoid.conf if it already exists, making snapshot retention changes via the script impossible.  It now overrides sanoid.conf when you change the retention limits in the script.
- Improved logging around snapshot pruning.
- Added Destination Pruning, with it's own retention policy.  Only works with replication="zfs" and locally.  Not configured for remote SSH destination pruning.
- made script more portable by replacing hardcoded /usr/local/sbin/sanoid with portable variables.
