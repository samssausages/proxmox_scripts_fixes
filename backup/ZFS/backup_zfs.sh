#!/usr/bin/env bash
# Portable ZFS backup script using Sanoid/Syncoid or rsync.
# Requires: zfs, sanoid, syncoid for ZFS replication, rsync for rsync replication.

set -o pipefail

####################
# Source for snapshotting and/or replication
source_pool="apool"          # zpool containing the source dataset, without a leading /mnt/
source_dataset="admin"       # dataset name below the source pool
                              # If autosnapshots=yes, avoid spaces in dataset names because Sanoid config parsing is unreliable with spaces.

####################
# Replication settings
# Valid values: zfs, rsync, none
replication="zfs"

####################
# ZFS replication variables. Used only when replication="zfs".
destination_pool="apool"
parent_destination_dataset="backup_bertha"

####################
# ZFS snapshot settings
autosnapshots="yes"          # yes = create and prune automatic source snapshots with Sanoid; no = skip source autosnapshots

# Source snapshot retention policy
snapshot_hours="24"
snapshot_days="14"
snapshot_weeks="8"
snapshot_months="12"
snapshot_years="2"

# Destination snapshot retention policy for replicated ZFS snapshots.
# Destination pruning does not create destination snapshots; it only prunes replicated Sanoid snapshots.
destination_snapshot_hours="0"
destination_snapshot_days="7"
destination_snapshot_weeks="8"
destination_snapshot_months="12"
destination_snapshot_years="3"

####################
# Remote server variables
# Leave destination_remote="no" for local backups.
destination_remote="no"
remote_user="root"
remote_server="10.1.10.20"

# Syncoid behavior:
# basic = replicate snapshots without deleting extra snapshots on destination.
# strict-mirror = pass --force-delete to syncoid. This can delete snapshots/datasets on destination that are not on source.
syncoid_mode="basic"

# Optional advanced syncoid options. These are intentionally split by the shell when used.
syncoid_send_options=""
syncoid_receive_options=""

####################
# rsync replication variables. Used only when replication="rsync".
parent_destination_folder="/var/backups/rsync_backup"
rsync_type="incremental"     # valid values: incremental, mirror

####################
# Portable paths and command names
# Override these if your binaries or Sanoid defaults live somewhere else.
sanoid_cmd="${sanoid_cmd:-sanoid}"
syncoid_cmd="${syncoid_cmd:-syncoid}"
zfs_cmd="${zfs_cmd:-zfs}"
rsync_cmd="${rsync_cmd:-rsync}"
ssh_cmd="${ssh_cmd:-ssh}"
scp_cmd="${scp_cmd:-scp}"
remote_sanoid_cmd="${remote_sanoid_cmd:-sanoid}"
remote_zfs_cmd="${remote_zfs_cmd:-zfs}"

sanoid_defaults_file="${sanoid_defaults_file:-/etc/sanoid/sanoid.defaults.conf}"
sanoid_config_dir="${sanoid_config_dir:-/etc/sanoid/backup-script}"

####################
# Derived variables
source_path="${source_pool}/${source_dataset}"
zfs_destination_path="${destination_pool}/${parent_destination_dataset}/${source_pool}_${source_dataset//\//_}"
destination_rsync_location="${parent_destination_folder%/}/${source_pool}_${source_dataset//\//_}"
config_name="${source_pool}_${source_dataset//\//_}"
config_name="${config_name// /_}"
sanoid_config_complete_path="${sanoid_config_dir%/}/${config_name}/"
destination_sanoid_config_complete_path="${sanoid_config_dir%/}/${config_name}_destination/"

####################
# Logging and error handling
log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local cmd="$1"
  if ! command -v -- "${cmd}" >/dev/null 2>&1; then
    fail "Required command not found or not executable: ${cmd}"
  fi
}

copy_sanoid_defaults() {
  local target_dir="$1"

  mkdir -p "${target_dir}" || return 1

  if [ ! -f "${target_dir}sanoid.defaults.conf" ]; then
    if [ ! -f "${sanoid_defaults_file}" ]; then
      fail "Sanoid defaults file not found: ${sanoid_defaults_file}. Set sanoid_defaults_file to the correct path."
    fi
    cp "${sanoid_defaults_file}" "${target_dir}sanoid.defaults.conf" || return 1
  fi
}

validate_yes_no() {
  local name="$1"
  local value="$2"
  if [ "${value}" != "yes" ] && [ "${value}" != "no" ]; then
    fail "${name} must be set to either 'yes' or 'no'. Current value: ${value}"
  fi
}

validate_nonnegative_integer() {
  local name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    fail "${name} must be a non-negative integer. Current value: ${value}"
  fi
}

remote_target() {
  printf '%s@%s' "${remote_user}" "${remote_server}"
}

remote_run() {
  "${ssh_cmd}" "$(remote_target)" "$@"
}

get_dataset_mountpoint() {
  local dataset="$1"
  local mountpoint

  mountpoint=$("${zfs_cmd}" get -H -o value mountpoint "${dataset}") || return 1

  case "${mountpoint}" in
    ""|"-"|"none"|"legacy")
      fail "Dataset ${dataset} does not have a normal ZFS mountpoint. Current mountpoint value: ${mountpoint}"
      ;;
  esac

  if [ ! -d "${mountpoint}" ]; then
    fail "Dataset ${dataset} mountpoint does not exist or is not mounted: ${mountpoint}"
  fi

  printf '%s' "${mountpoint}"
}

snapshot_mount_path() {
  local dataset="$1"
  local snapshot_name="$2"
  local mountpoint

  mountpoint=$(get_dataset_mountpoint "${dataset}") || return 1
  printf '%s/.zfs/snapshot/%s' "${mountpoint}" "${snapshot_name}"
}

####################
# Pre-run checks
pre_run_checks() {
  require_command "${zfs_cmd}"

  if [ "${autosnapshots}" = "yes" ] || [ "${replication}" = "zfs" ]; then
    require_command "${sanoid_cmd}"
  fi

  if [ "${replication}" = "zfs" ]; then
    require_command "${syncoid_cmd}"
  fi

  if [ "${replication}" = "rsync" ]; then
    require_command "${rsync_cmd}"
  fi

  if [ "${destination_remote}" = "yes" ]; then
    require_command "${ssh_cmd}"
    if [ "${replication}" = "zfs" ]; then
      require_command "${scp_cmd}"
    fi
  fi

  validate_yes_no "autosnapshots" "${autosnapshots}"
  validate_yes_no "destination_remote" "${destination_remote}"

  case "${replication}" in
    zfs|rsync|none) ;;
    *) fail "replication must be set to 'zfs', 'rsync', or 'none'. Current value: ${replication}" ;;
  esac

  if [ "${replication}" = "rsync" ]; then
    case "${rsync_type}" in
      incremental|mirror) ;;
      *) fail "rsync_type must be set to 'incremental' or 'mirror'. Current value: ${rsync_type}" ;;
    esac
  fi

  for item in \
    "snapshot_hours:${snapshot_hours}" \
    "snapshot_days:${snapshot_days}" \
    "snapshot_weeks:${snapshot_weeks}" \
    "snapshot_months:${snapshot_months}" \
    "snapshot_years:${snapshot_years}" \
    "destination_snapshot_hours:${destination_snapshot_hours}" \
    "destination_snapshot_days:${destination_snapshot_days}" \
    "destination_snapshot_weeks:${destination_snapshot_weeks}" \
    "destination_snapshot_months:${destination_snapshot_months}" \
    "destination_snapshot_years:${destination_snapshot_years}"; do
    validate_nonnegative_integer "${item%%:*}" "${item#*:}"
  done

  if ! "${zfs_cmd}" list -H "${source_path}" >/dev/null 2>&1; then
    fail "Source dataset does not exist: ${source_path}"
  fi

  if [ "${autosnapshots}" = "yes" ] && [[ "${source_path}" == *" "* ]]; then
    fail "Autosnapshots are enabled and source dataset '${source_path}' contains spaces. Rename the dataset or disable autosnapshots."
  fi

  local used
  used=$("${zfs_cmd}" get -H -o value used "${source_path}") || fail "Could not read used size for source dataset: ${source_path}"
  if [ "${used}" = "0B" ]; then
    fail "Source dataset is empty. Nothing to replicate: ${source_path}"
  fi

  if [ "${destination_remote}" = "yes" ]; then
    [ -n "${remote_user}" ] || fail "remote_user must be set when destination_remote=yes."
    [ -n "${remote_server}" ] || fail "remote_server must be set when destination_remote=yes."

    log "Replication target is remote: $(remote_target)"
    if ! "${ssh_cmd}" -o BatchMode=yes -o ConnectTimeout=5 "$(remote_target)" 'echo SSH connection successful' >/dev/null 2>&1; then
      fail "SSH connection failed. Check remote server details and SSH key authentication."
    fi

    if [ "${replication}" = "zfs" ]; then
      if ! remote_run "command -v '${remote_zfs_cmd}' >/dev/null 2>&1"; then
        fail "Remote ZFS command not found: ${remote_zfs_cmd}"
      fi
      if ! remote_run "command -v '${remote_sanoid_cmd}' >/dev/null 2>&1"; then
        fail "Remote Sanoid command not found: ${remote_sanoid_cmd}"
      fi
      if ! remote_run "test -f '${sanoid_defaults_file}'"; then
        fail "Remote Sanoid defaults file not found: ${sanoid_defaults_file}"
      fi
    fi
  else
    log "Replication target is local."
  fi

  if [ "${replication}" = "none" ] && [ "${autosnapshots}" = "no" ]; then
    fail "Both replication=none and autosnapshots=no. There is no work to perform."
  fi

  log "All pre-run checks passed."
}

####################
# Build source Sanoid config
create_sanoid_config() {
  if [ "${autosnapshots}" != "yes" ]; then
    return 0
  fi

  copy_sanoid_defaults "${sanoid_config_complete_path}" || return 1

  local config_file="${sanoid_config_complete_path}sanoid.conf"
  local tmp_config
  tmp_config=$(mktemp "${sanoid_config_complete_path}sanoid.conf.tmp.XXXXXX") || return 1

  cat > "${tmp_config}" <<CONFIG_EOF
[${source_path}]
use_template = production
recursive = yes

[template_production]
hourly = ${snapshot_hours}
daily = ${snapshot_days}
weekly = ${snapshot_weeks}
monthly = ${snapshot_months}
yearly = ${snapshot_years}
autosnap = yes
autoprune = yes
CONFIG_EOF

  if [ -f "${config_file}" ] && cmp -s "${tmp_config}" "${config_file}"; then
    rm -f "${tmp_config}"
    log "Sanoid config unchanged: ${config_file}"
    return 0
  fi

  if [ -f "${config_file}" ]; then
    cp "${config_file}" "${config_file}.bak.$(date +%Y%m%d_%H%M%S)" || {
      rm -f "${tmp_config}"
      return 1
    }
  fi

  mv "${tmp_config}" "${config_file}" || return 1
  log "Sanoid config updated: ${config_file}"
}

####################
# Build destination Sanoid config for pruning replicated snapshots
create_destination_sanoid_config() {
  if [ "${replication}" != "zfs" ]; then
    log "ZFS replication not set. Skipping destination Sanoid config."
    return 0
  fi

  local tmp_config
  tmp_config=$(mktemp) || return 1

  cat > "${tmp_config}" <<CONFIG_EOF
[${zfs_destination_path}]
use_template = destination
recursive = yes

[template_destination]
hourly = ${destination_snapshot_hours}
daily = ${destination_snapshot_days}
weekly = ${destination_snapshot_weeks}
monthly = ${destination_snapshot_months}
yearly = ${destination_snapshot_years}
autosnap = no
autoprune = yes
CONFIG_EOF

  if [ "${destination_remote}" = "yes" ]; then
    local remote_config_dir="${destination_sanoid_config_complete_path}"
    local remote_config_file="${remote_config_dir}sanoid.conf"
    local remote_tmp_config="${remote_config_dir}sanoid.conf.tmp.$$"

    remote_run "mkdir -p '${remote_config_dir}'" || { rm -f "${tmp_config}"; return 1; }
    remote_run "if [ ! -f '${remote_config_dir}sanoid.defaults.conf' ]; then cp '${sanoid_defaults_file}' '${remote_config_dir}sanoid.defaults.conf'; fi" || { rm -f "${tmp_config}"; return 1; }
    "${scp_cmd}" -q "${tmp_config}" "$(remote_target):${remote_tmp_config}" || { rm -f "${tmp_config}"; return 1; }

    remote_run "
      if [ -f '${remote_config_file}' ] && cmp -s '${remote_tmp_config}' '${remote_config_file}'; then
        rm -f '${remote_tmp_config}'
        echo 'Destination Sanoid config unchanged: ${remote_config_file}'
      else
        if [ -f '${remote_config_file}' ]; then
          cp '${remote_config_file}' '${remote_config_file}.bak.'\$(date +%Y%m%d_%H%M%S) || exit 1
        fi
        mv '${remote_tmp_config}' '${remote_config_file}' || exit 1
        echo 'Destination Sanoid config updated: ${remote_config_file}'
      fi
    " || { rm -f "${tmp_config}"; return 1; }

    rm -f "${tmp_config}"
    return 0
  fi

  copy_sanoid_defaults "${destination_sanoid_config_complete_path}" || { rm -f "${tmp_config}"; return 1; }

  local config_file="${destination_sanoid_config_complete_path}sanoid.conf"
  local tmp_config_dest
  tmp_config_dest=$(mktemp "${destination_sanoid_config_complete_path}sanoid.conf.tmp.XXXXXX") || { rm -f "${tmp_config}"; return 1; }
  mv "${tmp_config}" "${tmp_config_dest}" || { rm -f "${tmp_config}" "${tmp_config_dest}"; return 1; }

  if [ -f "${config_file}" ] && cmp -s "${tmp_config_dest}" "${config_file}"; then
    rm -f "${tmp_config_dest}"
    log "Destination Sanoid config unchanged: ${config_file}"
    return 0
  fi

  if [ -f "${config_file}" ]; then
    cp "${config_file}" "${config_file}.bak.$(date +%Y%m%d_%H%M%S)" || {
      rm -f "${tmp_config_dest}"
      return 1
    }
  fi

  mv "${tmp_config_dest}" "${config_file}" || return 1
  log "Destination Sanoid config updated: ${config_file}"
}

####################
# Source autosnapshot
autosnap() {
  if [ "${autosnapshots}" != "yes" ]; then
    log "Autosnapshots disabled. Skipping snapshot creation."
    return 0
  fi

  log "Creating automatic snapshots with Sanoid based on source retention policy."
  if "${sanoid_cmd}" --configdir="${sanoid_config_complete_path}" --take-snapshots; then
    log "Automatic snapshot creation succeeded for source: ${source_path}"
  else
    warn "Automatic snapshot creation failed for source: ${source_path}"
    return 1
  fi
}

####################
# Source autoprune
autoprune() {
  if [ "${autosnapshots}" != "yes" ]; then
    log "Autosnapshots disabled. Skipping source prune."
    return 0
  fi

  log "Pruning automatic source snapshots with Sanoid based on source retention policy."
  if "${sanoid_cmd}" \
    --configdir="${sanoid_config_complete_path}" \
    --prune-snapshots \
    --force-update \
    --verbose; then
    log "Automatic source snapshot pruning succeeded for source: ${source_path}"
  else
    warn "Automatic source snapshot pruning failed for source: ${source_path}"
    return 1
  fi
}

####################
# Destination autoprune for ZFS replication
autoprune_destination() {
  if [ "${replication}" != "zfs" ]; then
    log "ZFS replication not set. Skipping destination prune."
    return 0
  fi

  log "Pruning replicated snapshots on ZFS destination based on destination retention policy."

  if [ "${destination_remote}" = "yes" ]; then
    if ! remote_run "${remote_zfs_cmd} list -H '${zfs_destination_path}' >/dev/null 2>&1"; then
      warn "Destination dataset does not exist on remote server: ${zfs_destination_path}"
      return 1
    fi

    if remote_run "${remote_sanoid_cmd} --configdir='${destination_sanoid_config_complete_path}' --prune-snapshots --force-update --verbose"; then
      log "Destination snapshot pruning succeeded for remote destination: ${zfs_destination_path}"
    else
      warn "Destination snapshot pruning failed for remote destination: ${zfs_destination_path}"
      return 1
    fi
    return 0
  fi

  if ! "${zfs_cmd}" list -H "${zfs_destination_path}" >/dev/null 2>&1; then
    warn "Destination dataset does not exist locally: ${zfs_destination_path}"
    return 1
  fi

  if "${sanoid_cmd}" \
    --configdir="${destination_sanoid_config_complete_path}" \
    --prune-snapshots \
    --force-update \
    --verbose; then
    log "Destination snapshot pruning succeeded for local destination: ${zfs_destination_path}"
  else
    warn "Destination snapshot pruning failed for local destination: ${zfs_destination_path}"
    return 1
  fi
}

####################
# ZFS replication
zfs_replication() {
  if [ "${replication}" != "zfs" ]; then
    log "ZFS replication not set. Skipping ZFS replication."
    return 0
  fi

  local destination
  local parent_dataset="${destination_pool}/${parent_destination_dataset}"

  if [ "${destination_remote}" = "yes" ]; then
    destination="$(remote_target):${zfs_destination_path}"
    if ! remote_run "if ! ${remote_zfs_cmd} list -o name -H '${parent_dataset}' >/dev/null 2>&1; then ${remote_zfs_cmd} create '${parent_dataset}'; fi"; then
      warn "Failed to check or create remote ZFS dataset: ${parent_dataset}"
      return 1
    fi
  else
    destination="${zfs_destination_path}"
    if ! "${zfs_cmd}" list -o name -H "${parent_dataset}" >/dev/null 2>&1; then
      if ! "${zfs_cmd}" create "${parent_dataset}"; then
        warn "Failed to create local ZFS dataset: ${parent_dataset}"
        return 1
      fi
    fi
  fi

  local -a syncoid_flags=("-r")
  case "${syncoid_mode}" in
    strict-mirror)
      syncoid_flags+=("--force-delete")
      ;;
    basic)
      ;;
    *)
      warn "Invalid syncoid_mode. Use 'strict-mirror' or 'basic'. Current value: ${syncoid_mode}"
      return 1
      ;;
  esac

  log "Starting ZFS replication with syncoid mode: ${syncoid_mode}"
  # shellcheck disable=SC2086
  if "${syncoid_cmd}" ${syncoid_send_options} ${syncoid_receive_options} "${syncoid_flags[@]}" "${source_path}" "${destination}"; then
    log "ZFS replication succeeded from ${source_path} to ${destination}"
  else
    warn "ZFS replication failed from ${source_path} to ${destination}"
    return 1
  fi
}

####################
# rsync replication helpers
get_previous_backup() {
  previous_backup=""

  if [ "${rsync_type}" != "incremental" ]; then
    return 0
  fi

  if [ "${destination_remote}" = "yes" ]; then
    previous_backup=$(remote_run "if [ -d '${destination_rsync_location}' ]; then ls -1 '${destination_rsync_location}' | sort -r | head -n 2 | tail -n 1; fi")
  else
    if [ -d "${destination_rsync_location}" ]; then
      previous_backup=$(ls -1 "${destination_rsync_location}" | sort -r | head -n 2 | tail -n 1)
    fi
  fi
}

rsync_one_dataset() {
  local dataset="$1"
  local snapshot_name="$2"
  local rsync_destination="$3"
  local relative_dataset_path="$4"
  local snapshot_mount_point
  local previous_backup=""
  local -a link_dest_arg=()

  log "Creating temporary ZFS snapshot for rsync: ${dataset}@${snapshot_name}"
  if ! "${zfs_cmd}" snapshot "${dataset}@${snapshot_name}"; then
    warn "Failed to create temporary ZFS snapshot: ${dataset}@${snapshot_name}"
    return 1
  fi

  snapshot_mount_point=$(snapshot_mount_path "${dataset}" "${snapshot_name}") || {
    "${zfs_cmd}" destroy "${dataset}@${snapshot_name}" >/dev/null 2>&1
    return 1
  }

  if [ ! -d "${snapshot_mount_point}" ]; then
    warn "Snapshot mount path does not exist: ${snapshot_mount_point}"
    "${zfs_cmd}" destroy "${dataset}@${snapshot_name}" >/dev/null 2>&1
    return 1
  fi

  if [ "${destination_remote}" = "yes" ]; then
    remote_run "mkdir -p '${rsync_destination}'" || {
      "${zfs_cmd}" destroy "${dataset}@${snapshot_name}" >/dev/null 2>&1
      return 1
    }
  else
    mkdir -p "${rsync_destination}" || {
      "${zfs_cmd}" destroy "${dataset}@${snapshot_name}" >/dev/null 2>&1
      return 1
    }
  fi

  get_previous_backup
  if [ -n "${previous_backup}" ]; then
    link_dest_arg=("--link-dest=${destination_rsync_location}/${previous_backup}${relative_dataset_path}")
    log "Using rsync link-dest: ${link_dest_arg[0]}"
  fi

  local status=0
  if [ "${destination_remote}" = "yes" ]; then
    if ! "${rsync_cmd}" -azvh --delete "${link_dest_arg[@]}" -e ssh "${snapshot_mount_point}/" "$(remote_target):${rsync_destination}/"; then
      warn "rsync replication failed from ${dataset} to remote destination: $(remote_target):${rsync_destination}"
      status=1
    fi
  else
    if ! "${rsync_cmd}" -avh --delete "${link_dest_arg[@]}" "${snapshot_mount_point}/" "${rsync_destination}/"; then
      warn "rsync replication failed from ${dataset} to local destination: ${rsync_destination}"
      status=1
    fi
  fi

  log "Deleting temporary ZFS snapshot: ${dataset}@${snapshot_name}"
  if ! "${zfs_cmd}" destroy "${dataset}@${snapshot_name}"; then
    warn "Failed to delete temporary ZFS snapshot: ${dataset}@${snapshot_name}"
    status=1
  fi

  return "${status}"
}

rsync_replication() {
  if [ "${replication}" != "rsync" ]; then
    return 0
  fi

  local snapshot_name="rsync_snapshot_$(date +%Y%m%d_%H%M%S)_$$"
  local backup_date=""
  local destination="${destination_rsync_location}"

  if [ "${rsync_type}" = "incremental" ]; then
    backup_date=$(date +%Y-%m-%d_%H%M%S)
    destination="${destination_rsync_location}/${backup_date}"
  fi

  rsync_one_dataset "${source_path}" "${snapshot_name}" "${destination}" "" || return 1

  local child_datasets
  child_datasets=$("${zfs_cmd}" list -r -H -o name "${source_path}" | tail -n +2)

  local child_dataset
  while IFS= read -r child_dataset; do
    [ -n "${child_dataset}" ] || continue
    local relative_path="${child_dataset#${source_path}/}"
    local child_destination="${destination}/${relative_path}"
    rsync_one_dataset "${child_dataset}" "${snapshot_name}" "${child_destination}" "/${relative_path}" || return 1
  done <<< "${child_datasets}"

  if [ "${destination_remote}" = "yes" ]; then
    log "rsync ${rsync_type} replication succeeded from ${source_path} to remote destination: $(remote_target):${destination}"
  else
    log "rsync ${rsync_type} replication succeeded from ${source_path} to local destination: ${destination}"
  fi
}

####################
# Main
main() {
  pre_run_checks || exit 1
  create_sanoid_config || exit 1
  create_destination_sanoid_config || exit 1
  autosnap || exit 1
  rsync_replication || exit 1
  zfs_replication || exit 1
  autoprune_destination || exit 1
  autoprune || exit 1
}

main "$@"
