#!/bin/bash
#set -x
# Special thanks to SpaceinvaderOne for providing the framework that this script is built on!
# Main Variables
#
####################
# Source for snapshotting and/or replication
source_pool="rpool"  #this is the zpool in which your source dataset resides (note the does NOT start with /mnt/)
source_dataset="ROOT"   #this is the name of the dataset you want to snapshot and/or replicate
#If using auto snapshots souce pool CAN NOT contain spaces. This is because sanoid config doesnt handle them
#
####################
#
#zfs snapshot settings
autosnapshots="yes" # set to "yes" to have script auto snapshot your source dataset. Set to "no" to skip snapshotting.
#
#snapshot retention policy (default below works well, but change to suit)
snapshot_hours="24"
snapshot_days="30"
snapshot_weeks="8"
snapshot_months="12"
snapshot_years="1"
#
####################
#
# remote server variables (leave as is (set to "no") if not backing up to another server)
destination_remote="yes" # set to "no" for local backup to "yes" for a remote backup (remote location should be accessable paired with ssh with shared keys)
remote_user="root"  #remote user
remote_server="10.1.2.20" #remote servers name or ip
#
####################
#
### replication settings
#
replication="zfs"   #this is set to the method for how you want to have the sourcedataset replicated - "zfs" , "rsync" or "none"
#
####################
#
# zfs replication variables. You do NOT need these if replication set to "rsync" or "none"
destination_pool="disk22"  #this is the zpool in which your destination dataset will be created
parent_destination_dataset="backup_proxmox" #this is the parent dataset in which a child dataset will be created containing the replicated data (zfs replication)
# For ZFS replication syncoid is used. The below variable sets some options for that.
# "strict-mirror" Strict mirroring that both mirrors the source and repairs mismatches (uses --force-delete flag).This will delete snapshots in the destination which are not in the source.
# "basic" Basic replication without any additional flags will not delete snapshots in destination if not in the source
syncoid_mode="basic"
# Optional Advanced flags for syncoid send and receive options. Leave empty or customize for your dataset and cold storage requirements
syncoid_send_options="" # "--sendoptions=w" is useful for encrypted datasets and sends raw encrypted dataset
syncoid_receive_options="" # can add things like: --recvoptions=o recordsize=1M o compression=zstd-19 Must consider this when restoring, as may want to change that back
#
####################
#
# rsync replication variables. You do not need these if replication set to zfs or no
parent_destination_folder="/mnt/user/rsync_backup" # This is the parent directory in which a child directory will be created containing the replicated data (rsync)
rsync_type="incremental" # set to "incremental" for dated incremental backups or "mirror" for mirrored backups
#
####################
#
#Advanced variables you do not need to change these unless your sanoid config dir doesn't align properly.
source_path="$source_pool"/"$source_dataset"
zfs_destination_path="$destination_pool"/"$parent_destination_dataset"/"$source_pool"_"$source_dataset"
destination_rsync_location="$parent_destination_folder"/"$source_pool"_"$source_dataset"
sanoid_config_dir="/sanoid/"
sanoid_config_complete_path="$sanoid_config_dir""$source_pool"_"$source_dataset"/
#
####################################################################################################
####################################################################################################
#
# This function performs pre-run checks.
pre_run_checks() {
  # check for essential utilities
  if [ ! -x "$(which zfs)" ]; then
    msg='ZFS utilities are not found. Please ensure you are using the correct ZFS version.'
    echo "$msg"
    exit 1
  fi
  #
  if [ ! -x /usr/sbin/sanoid ]; then
    msg='Sanoid is not found or not executable. Please install Sanoid and try again.'
    echo "$msg"
    exit 1
  fi
  #
  if [ "$replication" = "zfs" ] && [ ! -x /usr/sbin/syncoid ]; then
    msg='Syncoid is not found or not executable. Please install Syncoid and try again.'
    echo "$msg"
    exit 1
  fi
  #
  # check if the dataset and pool exist
  if ! zfs list -H "${source_path}" &>/dev/null; then
    msg="Error: The source dataset '${source_dataset}' does not exist."
    echo "$msg"
    exit 1
  fi
  #
  # check if autosnapshots is set to "yes" and source_dataset has a space in its name
  if [[ "${autosnapshots}" == "yes" && "${source_dataset}" == *" "* ]]; then
    msg="Error: Autosnapshots is enabled and the source dataset name '${source_dataset}' contains spaces. Rename the dataset without spaces and try again. This is because although ZFS does support spaces in dataset names sanoid config file doesnt parse them correctly"
    echo "$msg"
    exit 1
  fi
  #
  local used
  used=$(zfs get -H -o value used "${source_path}")
  if [[ ${used} == 0B ]]; then
    msg="The source dataset '${source_path}' is empty. Nothing to replicate."
    echo "$msg"
    exit 1
  fi
  #
  if [ "$destination_remote" = "yes" ]; then
    echo "Replication target is a remote server. I will check if it is available..."
    # Attempt an SSH connection. If it fails, print an error message and exit.
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${remote_user}@${remote_server}" echo 'SSH connection successful' &>/dev/null; then
      msg='SSH connection failed. Please check your remote server details and ensure ssh keys are exchanged.'
      echo "$msg"
      exit 1
    fi
  else
    echo "Replication target is a local/same server."
  fi
  #
  # check script configuration variables
  if [ "$replication" != "zfs" ] && [ "$replication" != "rsync" ] && [ "$replication" != "none" ]; then
    msg="$replication is not a valid replication method. Please set it to either 'zfs', 'rsync', or 'none'."
    echo "$msg"
    exit 1
  fi

  if [ "$autosnapshots" != "yes" ] && [ "$autosnapshots" != "no" ]; then
    msg="The 'autosnapshots' variable is not set to a valid value. Please set it to either 'yes' or 'no'."
    echo "$msg"
    exit 1
  fi
  #
  if [ "$destination_remote" != "yes" ] && [ "$destination_remote" != "no" ]; then
    msg="The 'destination_remote' variable is not set to a valid value. Please set it to either 'yes' or 'no'."
    echo "$msg"
    exit 1
  fi
  #
  if [ "$destination_remote" = "yes" ]; then
    if [ -z "$remote_user" ] || [ -z "$remote_server" ]; then
      msg="The 'remote_user' and 'remote_server' must be set when 'destination_remote' is set to 'yes'."
      echo "$msg"
      exit 1
    fi
  fi
  #
  if [ "$replication" = "none" ] && [ "$autosnapshots" = "no" ]; then
    msg='Both replication and autosnapshots are set to "none". Please configure them so that the script can perform some work.'
    echo "$msg"
    exit 1
  fi
  #
  if [ "$replication" = "rsync" ]; then
    if [ "$rsync_type" != "incremental" ] && [ "$rsync_type" != "mirror" ]; then
      msg='Invalid rsync_type. Please set it to either "incremental" or "mirror".'
      echo "$msg"
      exit 1
    fi
  fi
  # If all checks passed print below
  echo "All pre-run checks passed. Continuing..."
}
#
####################
#
# This function will build a Sanoid config file for use with the script
create_sanoid_config() {
  # only make config if autosnapshots is set to "yes"
  if [ "${autosnapshots}" != "yes" ]; then
    return
  fi
  #
  # check if the configuration directory exists, if not create it
  if [ ! -d "${sanoid_config_complete_path}" ]; then
    mkdir -p "${sanoid_config_complete_path}"
  fi
  #
  # check if the sanoid.defaults.conf file exists in the configuration directory, if not copy it from the default location
  if [ ! -f "${sanoid_config_complete_path}sanoid.defaults.conf" ]; then
    cp /etc/sanoid/sanoid.defaults.conf "${sanoid_config_complete_path}sanoid.defaults.conf"
  fi
  #
  # check if a configuration file has already been created from a previous run, if so exit the function
  if [ -f "${sanoid_config_complete_path}sanoid.conf" ]; then
    return
  fi
#
# this  creates the new configuration file based off variables for retention
  echo "[${source_path}]" > "${sanoid_config_complete_path}sanoid.conf"
  echo "use_template = production" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "recursive = yes" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "[template_production]" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "hourly = ${snapshot_hours}" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "daily = ${snapshot_days}" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "weekly = ${snapshot_weeks}" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "monthly = ${snapshot_months}" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "yearly = ${snapshot_years}" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "autosnap = yes" >> "${sanoid_config_complete_path}sanoid.conf"
  echo "autoprune = yes" >> "${sanoid_config_complete_path}sanoid.conf"
}
#
####################
#
# This fuction will autosnapshot the source dataset using Sanoid
autosnap() {
  # check if autosnapshots is set to "yes" before creating snapshots
  if [[ "${autosnapshots}" == "yes" ]]; then
    # Create the snapshots on the source directory using Sanoid if required
    echo "creating the automatic snapshots using sanoid based off retention policy"
    /usr/sbin/sanoid --configdir="${sanoid_config_complete_path}" --take-snapshots
    #
    # check the exit status of the sanoid command 
    if [ $? -eq 0 ]; then
      tune="2"
      echo "Automatic snapshot creation using Sanoid was successful for source: ${source_path}" "success"
    else
      echo "Automatic snapshot creation using Sanoid failed for source: ${source_path}" "failure"
    fi
  #
  else
    echo "Autosnapshots are not set to 'yes', skipping..."
  fi
}
#
####################
#
# This fuction will autoprune the source dataset using sanoid
autoprune() {
  # rheck if autosnapshots is set to "yes" before creating snapshots
  if [[ "${autosnapshots}" == "yes" ]]; then
   echo "pruning the automatic snapshots using sanoid based off retention policy"
# run Sanoid to prune snapshots based on retention policy
/usr/sbin/sanoid --configdir="${sanoid_config_complete_path}" --prune-snapshots
  else
    echo "Autosnapshots are not set to 'yes', skipping..."
  fi
}
#
####################
#
# This function  does the zfs replication
zfs_replication() {
  # Check if replication method is set to ZFS
  if [ "$replication" = "zfs" ]; then
    # Check if the destination location was set to remote
    if [ "$destination_remote" = "yes" ]; then
      destination="${remote_user}@${remote_server}:${zfs_destination_path}"
      # check if the parent destination ZFS dataset exists on the remote server. If not, create it.
      ssh "${remote_user}@${remote_server}" "if ! zfs list -o name -H '${destination_pool}/${parent_destination_dataset}' &>/dev/null; then zfs create '${destination_pool}/${parent_destination_dataset}'; fi"
      if [ $? -ne 0 ]; then
        echo "Failed to check or create ZFS dataset on remote server: ${destination}" "failure"
        return 1
      fi
    else
      destination="${zfs_destination_path}"
      # check if the parent destination ZFS dataset exists locally. If not, create it.
      if ! zfs list -o name -H "${destination_pool}/${parent_destination_dataset}" &>/dev/null; then
        zfs create "${destination_pool}/${parent_destination_dataset}"
        if [ $? -ne 0 ]; then
          echo "Failed to check or create local ZFS dataset: ${destination_pool}/${parent_destination_dataset}" "failure"
          return 1
        fi
      fi
    fi
    # calc which syncoid flags to use, based on syncoid_mode
    local -a syncoid_flags=("-r")
    case "${syncoid_mode}" in
      "strict-mirror")
        syncoid_flags+=("--force-delete")
        ;;
      "basic")
        # No additional flags other than -r
        ;;
      *)
        echo "Invalid syncoid_mode. Please set it to 'strict-mirror', or 'basic'."
        exit 1
        ;;
    esac
    #
    # Use syncoid to replicate snapshot to the destination dataset
    echo "Starting ZFS replication using syncoid with mode: ${syncoid_mode}"
    /usr/sbin/syncoid "$syncoid_send_options" "$syncoid_receive_options" "${syncoid_flags[@]}" "${source_path}" "${destination}"
    if [ $? -eq 0 ]; then
      if [ "$destination_remote" = "yes" ]; then
        echo "ZFS replication was successful from source: ${source_path} to remote destination: ${destination}" "success"
      else
        echo "ZFS replication was successful from source: ${source_path} to local destination: ${destination}" "success"
      fi
    else
      echo "ZFS replication failed from source: ${source_path} to ${destination}" "failure"
      return 1
    fi
  else
    echo "ZFS replication not set. Skipping ZFS replication."
  fi
}
#
####################
#
# These below functions do the rsync replication
#
# Gets the most recent backup to compare against (used by below funcrions)
get_previous_backup() {
    if [ "$rsync_type" = "incremental" ]; then
        if [ "$destination_remote" = "yes" ]; then
            echo "Running: ssh ${remote_user}@${remote_server} \"ls ${destination_rsync_location} | sort -r | head -n 2 | tail -n 1\""
            previous_backup=$(ssh "${remote_user}@${remote_server}" "ls \"${destination_rsync_location}\" | sort -r | head -n 2 | tail -n 1")
        else
            previous_backup=$(ls "${destination_rsync_location}" | sort -r | head -n 2 | tail -n 1)
        fi
    fi
}
#
rsync_replication() {
    local previous_backup  # declare variable 

    IFS=$'\n'
    if [ "$replication" = "rsync" ]; then
        local snapshot_name="rsync_snapshot"
        if [ "$rsync_type" = "incremental" ]; then
            backup_date=$(date +%Y-%m-%d_%H:%M)
            destination="${destination_rsync_location}/${backup_date}"
        else
            destination="${destination_rsync_location}"
        fi
        #
        do_rsync() {
            local snapshot_mount_point="$1"
            local rsync_destination="$2"
            local relative_dataset_path="$3"
            get_previous_backup
            local link_dest_path="${destination_rsync_location}/${previous_backup}${relative_dataset_path}"
            [ -z "$previous_backup" ] && local link_dest="" || local link_dest="--link-dest=${link_dest_path}"
            echo "Link dest value is: $link_dest"
            # Log the link_dest value for debugging
            echo "Link dest value is: $link_dest"
            #
            if [ "$destination_remote" = "yes" ]; then
                # Create the remote directory 
                [ "$rsync_type" = "incremental" ] && ssh "${remote_user}@${remote_server}" "mkdir -p \"${rsync_destination}\""
                # Rsync the snapshot to the remote destination with link-dest
                #rsync -azvvv --delete $link_dest -e ssh "${snapshot_mount_point}/" "${remote_user}@${remote_server}:${rsync_destination}/"
                echo "Executing remote rsync: rsync -azvh --delete $link_dest -e ssh \"${snapshot_mount_point}/\" \"${remote_user}@${remote_server}:${rsync_destination}/\""
rsync -azvh --delete "$link_dest" -e ssh "${snapshot_mount_point}/" "${remote_user}@${remote_server}:${rsync_destination}/"

                if [ $? -ne 0 ]; then
                    echo "Rsync replication failed from source: ${source_path} to remote destination: ${remote_user}@${remote_server}:${rsync_destination}" "failure"
                    return 1
                fi
            else
                # Ensure the backup directory exists
                [ "$rsync_type" = "incremental" ] && mkdir -p "${rsync_destination}"
                # Rsync the snapshot to the local destination with link-dest
              #  rsync -avv --delete $link_dest "${snapshot_mount_point}/" "${rsync_destination}/"
              echo "Executing local rsync: rsync -avh --delete $link_dest \"${snapshot_mount_point}/\" \"${rsync_destination}/\""
rsync -avh --delete "$link_dest" "${snapshot_mount_point}/" "${rsync_destination}/"

                if [ $? -ne 0 ]; then
                    echo "Rsync replication failed from source: ${source_path} to local destination: ${rsync_destination}" "failure"
                    return 1
                fi
            fi
        }
        #
        echo "making a temporary zfs snapshot for rsync"
        zfs snapshot "${source_path}@${snapshot_name}"
        if [ $? -ne 0 ]; then
            echo "Failed to create ZFS snapshot for rsync: ${source_path}@${snapshot_name}" "failure"
            return 1
        fi
        #
        local snapshot_mount_point="/mnt/${source_path}/.zfs/snapshot/${snapshot_name}"
        do_rsync "${snapshot_mount_point}" "${destination}" ""
        #
        echo "deleting temporary snapshot"
        zfs destroy "${source_path}@${snapshot_name}"
        if [ $? -ne 0 ]; then
            echo "Failed to delete ZFS snapshot after rsync: ${source_path}@${snapshot_name}" "failure"
            return 1
        fi
        #
        # Replication for child sub-datasets
        local child_datasets=$(zfs list -r -H -o name "${source_path}" | tail -n +2)
        #
        for child_dataset in ${child_datasets}; do
            local relative_path=$(echo "${child_dataset}" | sed "s|^${source_path}/||g")
            echo "making a temporary zfs snapshot (child) for rsync"
            zfs snapshot "${child_dataset}@${snapshot_name}"
            snapshot_mount_point="/mnt/${child_dataset}/.zfs/snapshot/${snapshot_name}"
            child_destination="${destination}/${relative_path}"
            do_rsync "${snapshot_mount_point}" "${child_destination}" "/${relative_path}"
            zfs destroy "${child_dataset}@${snapshot_name}"
        done
        #
        # Send a single success Unraid notification after all datasets (main and child) have been processed.
        if [ "$destination_remote" = "yes" ]; then
            echo "Rsync ${rsync_type} replication was successful from source: ${source_path} to remote destination: ${remote_user}@${remote_server}:${destination}" "success"
        else
            echo "Rsync ${rsync_type} replication was successful from source: ${source_path} to local destination: ${destination}" "success"
        fi
    fi
}

#
########################################
#
# run the above functions 
pre_run_checks
create_sanoid_config
autosnap
rsync_replication
zfs_replication
autoprune