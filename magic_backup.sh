#!/bin/bash

# Backup configuration
backup_directory="/mnt/sharing/backups/$(hostname)" # Directory where backup files are stored
elements_to_backup=( # List of files and/or directory to backup
    "/home/user/docker-configs"
    "/home/user/scripts"
    "/etc/cron.daily"
    "/etc/cron.hourly"
)
onefile_backup=true # true: only one backup file, false: backup file for each element
# Compression
compression_enabled=true # Compressed backup
compression_level="9" # Compression level from 1 to 9
# Docker
stop_containers=false # Stop docker containers
container_filter_type="include" # "include" to only stop listed container, "exclude" to keep only listed container running
strict_start_order=true # Restart container in strict order, only for "include" mode
container_filter=( # List of container names
    "portainer_agent"
    "ubuntu"
)
# Detete old backups
days_to_keep=7 # Older backup will be deleted, 0 to disable
# Logs
use_logfile=true # Write logs in a file
log_file="/var/log/magic_backups.log" # File for the logs
# Debug
debug_mode=false # Debug mode, do nothing but print actions

# ==================================================

# Function to log messages
log() {
    current_date="$(date +"%Y-%m-%d %T")"
    echo "$current_date - $1"
    if [ "$use_logfile" = true ]; then
        if [ "$debug_mode" = false ]; then
            echo "$current_date - $1" >>"$log_file"
        fi
    fi
}

# Function to shut down containers
stop_docker_containers() {
    # log "Docker stopping all containers..."
    container_grep_filter=""
    for container in "${container_filter[@]}"; do
        if [ -z "$container_grep_filter" ]; then
            container_grep_filter="$container"
        else
            container_grep_filter="$container_grep_filter|$container"
        fi
    done
    if [ "$container_filter_type" = "include" ]; then # Include container filter
        log "Docker stopping containers => $container_grep_filter"
        if [ "$debug_mode" = false ]; then
            sudo docker stop $(sudo docker ps --all --format '{{.Names}}' | grep --extended-regexp "$container_grep_filter") >/dev/null 2>>"$log_file"
            sleep 1
        fi
    else # Exclude container filter
        log "Docker stopping all containers exept => $container_grep_filter"
        if [ "$debug_mode" = false ]; then
            sudo docker stop $(sudo docker ps --all --format '{{.Names}}' | grep --invert-match --extended-regexp "$container_grep_filter") >/dev/null 2>>"$log_file"
            sleep 1
        fi
    fi
    # log "Docker containers stopped."
}

# Function to start containers
start_docker_containers() {
    # log "Docker starting all containers..."
    container_grep_filter=""
    for container in "${container_filter[@]}"; do
        if [ -z "$container_grep_filter" ]; then
            container_grep_filter="$container"
        else
            container_grep_filter="$container_grep_filter|$container"
        fi
    done
    if [ "$container_filter_type" = "include" ]; then # Include container filter
        log "Docker starting containers => $container_grep_filter"
        if [ "$debug_mode" = false ]; then
            if [ "$strict_start_order" = true ]; then
                for container in "${container_filter[@]}"; do
                    log "Docker starting container => $container"
                    sudo docker start $container >/dev/null 2>>"$log_file"
                    sleep 1
                done
            else
                sudo docker start $(sudo docker ps --all --format '{{.Names}}' | grep --extended-regexp "$container_grep_filter") >/dev/null 2>>"$log_file"
                sleep 1
            fi
        fi
    else # Exclude container filter
        log "Docker starting all containers exept => $container_grep_filter"
        if [ "$debug_mode" = false ]; then
            sudo docker start $(sudo docker ps --all --format '{{.Names}}' | grep --invert-match --extended-regexp "$container_grep_filter") >/dev/null 2>>"$log_file"
            sleep 1
        fi
    fi
    # log "Docker containers started."
}

# Function to perform backup
perform_backup() {
    # log "Docker starting backup process..."

    # Verify backup directory
    if [ ! -d "$backup_directory" ]; then
        log "Backup directory does not exist. Trying to create it..."
        if [ "$debug_mode" = false ]; then
            mkdir -p "$backup_directory"
            if [ $? -ne 0 ]; then
                log "Error: Failed to create backup directory => $backup_directory."
                return 1
            fi
            log "Backup directory created => $backup_directory"
        fi
    fi

    # Verify if backup directory is writable
    if [ ! -w "$backup_directory" ]; then
        log "Error: Backup directory is not writable => $backup_directory"
        if [ "$debug_mode" = false ]; then
            return 1
        fi
    fi

    # compression_arg=""
    if [ "$compression_enabled" = true ]; then
        compression_program="gzip"
        if command -v pigz &>/dev/null; then # Use pigz for compression
            compression_program="pigz"
            log "Backup using pigz for multi-core compression"
        else
            log "Backup using gzip for single-core compression"
        fi
        # compression_arg="--use-compress-program=${compression_program} -${compression_level}"
    fi

    if [ "$onefile_backup" = true ]; then
        # for item in "${elements_to_backup[@]}"; do # Loop through each file/folder to backup
        #     if [ -e "$item" ]; then
        #         items_to_backup="${items_to_backup} ${item}"
        #     else
        #         log "Warning: File or directory $item does not exist. Skipping..."
        #     fi
        # done
        backup_filename="Backup_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz" # Append date to filename
        log "Backup $item => ${backup_directory}/${backup_filename}"
        if [ "$debug_mode" = false ]; then
            # tar --create $compression_arg --exclude-vcs -f "${backup_directory}/${backup_filename}" $items_to_backup >/dev/null 2>>"${log_file}"
            if [ "$compression_enabled" = true ]; then
                tar --create --exclude-vcs "${elements_to_backup[@]}" | $compression_program -${compression_level} >"${backup_directory}/${backup_filename}" 2>>"${log_file}"
            else
                tar --create --exclude-vcs -f "${backup_directory}/${backup_filename}" "${elements_to_backup[@]}" 2>>"${log_file}"
            fi
            if [ $? -ne 0 ]; then
                log "ERROR: An error as occured !"
                if [ "$backup_ok" = true ]; then
                    backup_ok=false
                fi
            fi
        fi
    else
        for item in "${elements_to_backup[@]}"; do # Loop through each file/folder to backup
            if [ -e "$item" ]; then
                backup_filename="${item##*/}_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz" # Append date to filename
                log "Backup $item => ${backup_directory}/${backup_filename}"
                if [ "$debug_mode" = false ]; then
                    # tar --create $compression_arg --exclude-vcs -f "${backup_directory}/${backup_filename}" "${item}" >/dev/null 2>>"${log_file}"
                    if [ "$compression_enabled" = true ]; then
                        tar --create --exclude-vcs "${item}" | $compression_program -${compression_level} >"${backup_directory}/${backup_filename}" 2>>"${log_file}"
                    else
                        tar --create --exclude-vcs -f "${backup_directory}/${backup_filename}" "${item}" 2>>"${log_file}"
                    fi
                    if [ $? -ne 0 ]; then
                        log "ERROR: An error as occured !"
                        if [ "$backup_ok" = true ]; then
                            backup_ok=false
                        fi
                    fi
                fi
            else
                log "Warning: File or directory $item does not exist. Skipping..."
            fi
        done
    fi

    # log "Backup process complete."
}

# Function to delete old backups
delete_old_backups() {
    log "Delete files older than $days_to_keep in directory => $backup_directory"
    if [ "$backup_ok" = true ]; then
        if [ "$debug_mode" = false ]; then
            find "$backup_directory" -type f -daystart -mtime +"$days_to_keep" -delete
        fi
    else
        log "Cannot delete files older than $days_to_keep days in directory $backup_directory, backup error"
    fi
}

# ==================================================
# Main script

start_time=$(date +%s)
backup_ok=true

# Check container_filter_type value
if [ "$container_filter_type" != "include" ] && [ "$container_filter_type" != "exclude" ]; then
    echo "Variable container_filter_type must be 'include' or 'exclude'."
    exit 1
fi

# Check if tar command is available
if ! command -v tar &>/dev/null; then
    sudo apt update
    sudo apt install tar -y
fi

# Shut down containers if enabled
if [ "$stop_containers" = true ]; then
    stop_docker_containers
fi

# Perform backup
perform_backup

# Delete old backups
if [ "$days_to_keep" -ne 0 ]; then
    delete_old_backups
fi

# Start containers if enabled
if [ "$stop_containers" = true ]; then
    start_docker_containers
fi

end_time=$(date +%s)
execution_time=$((end_time - start_time))
log "End script execution time: $execution_time seconds."
