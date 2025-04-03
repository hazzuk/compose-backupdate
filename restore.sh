#!/bin/bash

# Copyright (c) 2025 hazzuk

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# exit on any error
set -e

# check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error, please run as root!"
    exit 1
fi

# notes
# ---
# - we assume backups are in the current directory
# - we assume this is a fresh restore, and the container(s) does not exist
# - we assume this is a fresh restore, and the volume(s) does not exist
# - we assume docker stack dir is /home/user/docker/stackname
# - later, we should assume backups are stored in ~/backups/stack_name
# - script should ask if user wants to backup compose.yaml (might be using git)
# - Or potentially could avoid restoring compose.yaml

# variables
# ---

stack_name="null"
echo "Please provide the stack name (e.g. zitadel):"
read -r stack_name

echo "Please provide the docker compose directory path (e.g. /home/user/docker):"
read -r docker_dir
stack_dir=$docker_dir/"$stack_name"
echo "[Stack directory: $stack_dir]"

# script
# ---

main() {
    read -r -p "Press Enter to restore the directory (or Ctrl+C to exit):"
    # restore directory backup
    restore_directory

    # # recreate stack
    # restore_stack

    read -r -p "Press Enter to restore volumes (or Ctrl+C to exit):"
    # restore volume backups
    restore_volumes

    echo "Backupdate restore complete."
}

restore_directory() {
    local dir_backup_file

    echo "### DIRECTORY RESTORE ###"

    # check directory exists
    if [ ! -d "$stack_dir" ]; then
        echo "$stack_dir does not exist. Creating it."
        mkdir -p "$stack_dir"
    # check directory empty
    elif [ "$(ls -A "$stack_dir")" ]; then
        echo "Error: $stack_dir exists and is not empty."
        exit 1
    else
        echo "$stack_dir already exists (but is empty), continuing."
    fi

    # find directory backup
    echo "Locating directory backup..."
    dir_backup_file=$(find "." -name "d-*.tar.gz" -print -quit) # assume only one directory backup exists
    echo "Detected directory backup:"
    echo "- $dir_backup_file"

    # check directory backup exists
    if [ -z "$dir_backup_file" ]; then
        echo "Error: No directory backup found in $stack_dir."
        exit 1
    fi

    echo "Starting directory restore..."
    # extract directory backup
    tar -xzf "$dir_backup_file" -C "$stack_dir" # -xvzf: extract, gzip, filename. -C: extract to directory
    echo "[Directory '$stack_name' restored]"
    tree -L 1 -n --noreport "$stack_dir"
}

# restore_stack() {
#     # this approach creates the container and volumes
#     echo "Restoring Docker stack..."

#     echo "This assumes your container and volumes do not exist."
#     read -r -p "Press Enter to continue or Ctrl+C to exit:"

#     echo "- Creating Docker stack..."
#     docker compose -f "$stack_dir/compose.yaml" up -d

#     echo "- Stopping Docker stack..."
#     docker compose -f "$stack_dir/compose.yaml" down

#     echo "- List of Docker volumes:"
#     docker volume ls
# }

restore_volumes() {
    local vol_backup_paths=()
    local vol_backup_files=()
    local vol_names=()

    echo "### VOLUME RESTORE ###"

    # find volume backups
    echo "Locating volume backups..."
    while IFS= read -r file; do
        vol_backup_paths+=( "$file" )
    done < <(find . -type f -name 'v-*.tar.gz' -print)

    # clear file paths
    for file in "${vol_backup_paths[@]}"; do
        # remove anything before, but not including the last "/"
        vol_backup_files+=( "/${file##*/}" )
    done

    echo "Detected volume backups:"
    for file in "${vol_backup_files[@]}"; do
        echo "- ...$file"
    done

    # get volume names
    # v-caddy_config-20250331-230416.tar.gz -> caddy_config
    for file in "${vol_backup_files[@]}"; do
        # remove everything up to and including "/v-"
        vol_name="${file#*\/v-}"
        # extract everything before the first dash "-"
        vol_name="${vol_name%%-*}"
        vol_names+=( "$vol_name" )
    done

    echo "Docker volume names:"
    for name in "${vol_names[@]}"; do
        echo "- $name"
    done

    echo "Please confirm the values above are correct."
    read -r -p "Press Enter to continue (or Ctrl+C to exit):"

    # check volumes exist
    # remove each volume if it exists

    # restore each volumes
    echo "Starting volume restore"
    local i=0
    for file in "${vol_backup_files[@]}"; do
        # create volume
        # ONLY DO THIS IF THE VOLUME DOESN'T EXIST
        # DO NOT RUN restore_stack()
        # com.docker.compose.project	alpine
        # com.docker.compose.version	2.29.7 (not used)
        # com.docker.compose.volume 	alpine_data
        echo "Creating volume..."
        echo "- ($stack_name) $(
            docker volume create \
                --label com.docker.compose.project="$stack_name" \
                --label com.docker.compose.volume="${vol_names[$i]}" \
                "${vol_names[$i]}"
        )"

        # restore volume
        # run busybox container to extract volume backup
        # -v: bind mount volume to container
        # -v: bind mount backup dir to container
        echo "Restoring volume..."
        docker run --rm \
            -v "${vol_names[$i]}":/volume_data \
            -v .:/backup \
            busybox tar xzf /backup"$file" -C /volume_data
        echo "[Volume '${vol_names[$i]}' restored]"
        i=$((i + 1))
    done
}

main
