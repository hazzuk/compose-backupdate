#!/bin/bash
version="1.0.0"

# Copyright (c) 2024 hazzuk. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.


#                                    _           _             _     _       
#  ___ ___ _____ ___ ___ ___ ___ ___| |_ ___ ___| |_ _ _ ___ _| |___| |_ ___ 
# |  _| . |     | . | . |_ -| -_|___| . | .'|  _| '_| | | . | . | .'|  _| -_|
# |___|___|_|_|_|  _|___|___|___|   |___|__,|___|_,_|___|  _|___|__,|_| |___|
#               |_|                                     |_|                  
#
# Bash script for creating scheduled backups, and performing (backed-up) guided updates on Docker compose stacks
# https://github.com/hazzuk/compose-backupdate


# exit on any error
set -e

# check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error, please run as root!"
    exit 1
fi

# user variables
# (can be overridden by env variables or script arguments)
backup_dir=${BACKUP_DIR:-"null"} # -b "/opt/backup"
docker_dir=${DOCKER_DIR:-"null"} # -d "/opt/docker"
stack_name=${STACK_NAME:-"null"} # -s "nginx"
update_requested=false           # -u
version_requested=false          # -v

# script variables
timestamp=$(date +"%Y%m%d-%H%M%S")
stack_running=false
working_dir="null"

main() {
    # script version check
    if [ "$version_requested" = true ]; then
        check_for_update
        exit 0
    fi
    
    # check current directory for compose file
    docker_stack_dir

    # check script variables before continuing
    verify_config

    # create backup directory
    mkdir -p "$backup_dir/$stack_name" || { echo "Error, failed to create backup directory $backup_dir!"; exit 1; }

    # stop stack before backup
    echo "(stop)"
    docker_stack_stop

    # backup compose stack working directory
    echo "(backups)"
    backup_working_dir

    # backup docker volumes
    backup_stack_volumes

    # update if requested
    if [ "$update_requested" = true ]; then
        echo "(updates)"

        # print stack changelog url
        # print_changelog_url

        # update compose stack
        docker_stack_update
    fi

    # start stack again if previously running
    echo "(recreate)"
    docker_stack_start

    # prune unused docker images
    if [ "$update_requested" = true ]; then
        echo "(prune)"
        docker_image_prune
    fi

    echo -e "backupdate complete!\n "
    exit 0
}

usage() {
    echo "Usage: $0 [-b backup_dir] [-d docker_dir] [-s stack_name] [-u] [-v]"
    echo "       --backup-dir --docker-dir --stack-name --update --version"
    exit 1
}

parse_args() {
    local OPTIONS=b:d:s:uv
    local LONGOPTS=backup-dir:,docker-dir:,stack-name:,update,version

    # parse options
    if ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@"); then
        exit 2
    fi

    # evaluate parsed options
    eval set -- "$PARSED"

    # Now handle the options
    while true; do
        case "$1" in
            -b|--backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            -d|--docker-dir)
                docker_dir="$2"
                shift 2
                ;;
            -s|--stack-name)
                stack_name="$2"
                shift 2
                ;;
            -u|--update)
                update_requested=true
                shift
                ;;
            -v|--version)
                version_requested=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown option: $1"
                exit 3
                ;;
        esac
    done
}

verify_config() {
    # check script variables
    if [ "$backup_dir" = "null" ]; then
        echo "Error, backup_dir not provided!"
        usage
    fi
    if [ "$working_dir" = "null/$stack_name" ]; then
        echo "Error, docker_dir not provided!"
        usage
    fi
    if [ "$stack_name" = "null" ]; then
        echo "Error, stack_name not provided!"
        usage
    fi
    if [ "$working_dir" = "null" ]; then
        echo "Error, working_dir not set!"
        exit 1
    fi
    # echo script config
    echo "backupdate <$stack_name> $timestamp"
    echo "- backup_dir: $backup_dir"
    echo -e "- working_dir: $working_dir\n "
}

confirm() {
    local prompt="$1"
    read -r -p "${prompt} (y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

check_for_update() {
    local repo="hazzuk/compose-backupdate"
    local raw_url="https://raw.githubusercontent.com/$repo/refs/heads/release/backupdate.sh"
    local latest_version_line
    local latest_version

    # fetch second line (version="X.Y.Z") from the script hosted on github
    latest_version_line=$(curl -s "$raw_url" | sed -n '2p')
    # extract version from the fetched line
    latest_version=$(echo "$latest_version_line" | grep -oP '(?<=version=")[^"]+')

    if [[ $latest_version == "" ]]; then
        echo "Warn, could not check for updates"
        return 0
    fi

    # compare local version with the latest version
    if [[ "$version" != "$latest_version" ]]; then
        echo "A new version (v$latest_version) is available! You are using backupdate-v$version"
    else
        echo "Running backupdate-v$version"
    fi
}

docker_stack_stop() {
    echo "Stopping Docker stack: <$stack_name>"
    cd "$working_dir" || exit
    if docker compose ps --filter "status=running" | grep -q "$stack_name"; then
        stack_running=true
        docker compose stop
    else
        echo "- Docker stack <$stack_name> not running, skipping compose stop"
    fi
    echo
}

docker_stack_start() {
    echo "Resuming Docker stack: <$stack_name>"
    if [ "$stack_running" = true ]; then
        cd "$working_dir" || exit
        docker compose up -d
    else
        echo "- Docker stack <$stack_name> not previously running, skipping compose up"
    fi
    echo
}

docker_stack_dir() {
    # possible compose file names
    local compose_files=("compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml")
    # current directory name
    local current_dir
    current_dir=$(basename "$PWD") # "nginx"?

    # check neither $docker_dir or $stack_name were passed
    if [[ "$docker_dir" == "null" && "$stack_name" == "null" ]]; then
        echo "Info, neither docker_dir or stack_name were passed, using current directory"
    # but if $docker_dir was passed alone (likely as an environment variable), and is correct 
    elif [[ "$docker_dir/$current_dir" = "$(pwd)" && "$stack_name" == "null" ]]; then
        echo "Info, stack_name was not passed, using current directory"
    # otherwise something was passed, do not use current directory
    else
        # update working_dir with passed options
        working_dir="$docker_dir/$stack_name"
        return 0
    fi

    # search current directory for compose file
    for file in "${compose_files[@]}"; do
        if [[ -f "$file" ]]; then
            # update working_dir and stack_name to current directory
            working_dir="$(pwd)"
            stack_name=$current_dir
            echo -e "Found <$stack_name> $file in current directory\n "
            return 0
        fi
    done
    echo "Error, compose file not found in current directory!"
    usage
}

docker_stack_update() {
    if confirm "Are you sure you want to update <$stack_name>?"; then
        echo "Updating Docker stack..."
        docker compose pull
    else
        echo "- Update canceled"
    fi
    echo
}

docker_image_prune() {
    local docker_images
    local docker_images_unused=()

    echo "Searching for unused docker images..."
    # collect docker images output
    docker_images=$(
        docker images --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}" | \
        tail -n +2
    )

    # process images output
    while read -r image_id repository tag size; do
        # skip unused busybox image
        if [[ "$repository" == "busybox" ]]; then
            continue
        fi
        # check the image is not being used by a running/stopped container
        if [[ -z $(docker ps -a --filter "ancestor=$image_id" --format '{{.ID}}') ]]; then
            # append unused image_id to array
            docker_images_unused+=("$image_id")
            # print unused image details
            printf "%-16s %-45s %-10s\n" "- $image_id" "$repository:$tag" "$size"
        fi
    done <<< "$docker_images" # avoid subshell
    
    # check no unused images found
    if [[ ${#docker_images_unused[@]} -eq 0 ]]; then
        echo -e "- No unused images found\n "
        return 0
    else
        # prompt user for confirmation before proceeding
        if confirm "Do you want to prune unused images?"; then
            # prune unused images
            for image_id in "${docker_images_unused[@]}"; do
                echo "- Removing $image_id"
                docker rmi "$image_id" -f
            done
        else
            echo "- Prune cancelled"
        fi
    fi
    echo
}

backup_working_dir() {
    echo "Backup <$stack_name> directory: $working_dir"
    tar -czf "$backup_dir/$stack_name/d-$stack_name-$timestamp.tar.gz" -C "$working_dir" .
    echo "- Directory backup complete"
}

backup_stack_volumes() {
    # get all stack volumes
    local stack_volumes
    stack_volumes=$(
        docker volume ls --filter "label=com.docker.compose.project=$stack_name" --format "{{.Name}}"
    )

    # check volumes found
    if [ -z "$stack_volumes" ]; then
        echo -e "Info, no related volumes found for <$stack_name>\n "
        return 0
    fi

    # backup each volume
    for volume_name in $stack_volumes; do
        backup_volume "$volume_name"
    done
    echo
}

backup_volume() {
    local volume_name=$1
    echo "Backup volume: <$volume_name>"
    
    # backup volume data with temporary container
    docker run --rm \
        -v "$volume_name":/volume_data \
        -v "$backup_dir":/backup \
        busybox tar czf "/backup/$stack_name/v-$volume_name-$timestamp.tar.gz" -C /volume_data . || \
        { echo "Error, failed to create busybox backup container!"; exit 1; }
    echo "- Volume backup complete"
}

# print_changelog_url() {
#     local changelog_file="$working_dir/changelog.url"

#     # check changelog.url exists
#     if [[ -f "$changelog_file" ]]; then
#         echo "Link to read the <$stack_name> changelog: "
#         cat "$changelog_file"
#     else
#         # ask user to create changelog.url
#         echo "File $changelog_file does not exist"
#         read -r -p "Please provide a URL (or press Enter to continue without): " user_input

#         if [[ $user_input == http* ]]; then
#             # create changelog.url with user input
#             echo "$user_input" > "$changelog_file"
#             echo "- $changelog_file created"
#         else
#             echo "- No valid URL provided. Continuing without the <$stack_name> changelog"
#         fi
#     fi
# }

# run script
parse_args "$@"
main
