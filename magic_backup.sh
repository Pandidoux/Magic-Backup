#!/bin/bash

# User-defined variables
debug_mode=false
backup_directory="/mnt/sharing/backups/$(hostname)"
files_to_backup=(
    "/home/user/docker-volumes"
    "/home/user/scripts"
    "/etc/cron.daily"
    "/etc/cron.hourly"
)
days_to_keep=7
shutdown_containers=true
container_filter_include_exclude="exclude"
container_filter=(
    "portainer_agent"
    "ubuntu"
)
log_file="/var/log/magic_backups.log"

# ==================================================

# Function to log messages
log() {
    current_date="$(date +"%Y-%m-%d %T")"
    echo "$current_date - $1"
    if [ "$debug_mode" = false ]; then
        echo "$current_date - $1" >>"$log_file"
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
    if [ "$container_filter_include_exclude" = "include" ]; then # Include container filter
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
    if [ "$container_filter_include_exclude" = "include" ]; then # Include container filter
        log "Docker starting containers => $container_grep_filter"
        if [ "$debug_mode" = false ]; then
            sudo docker start $(sudo docker ps --all --format '{{.Names}}' | grep --extended-regexp "$container_grep_filter") >/dev/null 2>>"$log_file"
            sleep 1
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
        return 1
    fi

    use_pigz=false
    if command -v pigz &>/dev/null; then # Use pigz for compression
        use_pigz=true
        log "Backup using pigz for multi-core compression"
    else
        log "Backup using gzip for single-core compression"
    fi

    # Loop through each file/folder to backup
    for item in "${files_to_backup[@]}"; do
        if [ -e "$item" ]; then
            backup_filename="${item##*/}_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz" # Append date to filename
            log "Backup $item => $backup_directory/$backup_filename"
            if [ "$debug_mode" = false ]; then
                if [ "$use_pigz" = true ]; then # Use pigz for compression
                    tar --create --use-compress-program="pigz -9" -f "$backup_directory/$backup_filename" "$item" >/dev/null 2>>"$log_file"
                    if [ $? -ne 0 ] && [ "$backup_ok" = true ]; then
                        backup_ok=false
                    fi
                else # Use gzip for compression
                    tar --create --use-compress-program="gzip -9" -f "$backup_directory/$backup_filename" "$item" >/dev/null 2>>"$log_file"
                    if [ $? -ne 0 ] && [ "$backup_ok" = true ]; then
                        backup_ok=false
                    fi
                fi
            fi
        else
            log "Warning: File or directory $item does not exist. Skipping..."
        fi
    done

    # log "Backup process complete."
}

# Function to delete old backups
delete_old_backups() {
    if [ "$backup_ok" = true ]; then
        log "Delete files older than $days_to_keep in directory => $backup_directory"
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

# Check container_filter_include_exclude value
if [ "$container_filter_include_exclude" != "include" ] && [ "$container_filter_include_exclude" != "exclude" ]; then
    echo "Variable container_filter_include_exclude must be 'include' or 'exclude'."
    exit 1
fi

# Check if tar command is available
if ! command -v tar &>/dev/null; then
    sudo apt update
    sudo apt install tar -y
fi

# Shut down containers if enabled
if [ "$shutdown_containers" = true ]; then
    stop_docker_containers
fi

# Perform backup
perform_backup

# Delete old backups
if [ "$days_to_keep" -ne 0 ]; then
    delete_old_backups
fi

# Start containers if enabled
if [ "$shutdown_containers" = true ]; then
    start_docker_containers
fi

end_time=$(date +%s)
execution_time=$((end_time - start_time))
log "End script execution time: $execution_time seconds."
