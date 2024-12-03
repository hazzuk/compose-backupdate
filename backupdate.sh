#!/bin/bash
version="1.1.0"

# Copyright (c) 2024 hazzuk
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

# variables
# ---

# required
backup_dir=${BACKUP_DIR:-"null"}                # -b "/opt/backup"
docker_dir=${DOCKER_DIR:-"null"}                # -d "/opt/docker"
stack_name=${STACK_NAME:-"null"}                # -s "nginx"

# optional
backup_blocklist=${BACKUP_BLOCKLIST:-"null"}    # -l "media_vol,/media-bind"
update_requested=false                          # -u
version_requested=false                         # -v

# internal
timestamp=$(date +"%Y%m%d-%H%M%S")
stack_running=false
working_dir="null"
volume_blocklist=()
path_blocklist=()
running_container_ids=""
running_container_names=""

# script
# ---

main() {
    # script version check
    if [ "$version_requested" = true ]; then
        script_update_check
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

    # restart stack again if previously running
    echo "(restart)"
    docker_stack_start

    # prune unused docker images
    if [ "$update_requested" = true ]; then
        echo "(prune)"
        # new images must be associated with a running stack
        if [ "$stack_running" = true ]; then
            docker_image_prune
        else
            echo "- Docker stack not running, skipping image prune"
            echo
        fi
    fi

    echo -e "backupdate complete!\n\n"
    exit 0
}

# utilities
# ---

usage() {
    echo "Usage: $0 [-b backup_dir] [-d docker_dir] [-s stack_name] [-l backup_blocklist] [-u] [-v]"
    echo "       --backup-dir --docker-dir --stack-name --backup-blocklist --update --version"
    exit 1
}

parse_args() {
    local OPTIONS=b:d:s:l:uv
    local LONGOPTS=backup-dir:,docker-dir:,stack-name:,backup-blocklist:,update,version

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
            -l|--backup-blocklist)
                backup_blocklist="$2"
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
    # check required inputs
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
    echo "- working_dir: $working_dir"

    # check backup blocklist
    if [ "$backup_blocklist" != "null" ]; then
        # convert string to array
        IFS=',' read -r -a blockarray <<< "$backup_blocklist"

        # process items in array
        for item in "${blockarray[@]}"; do
            if [[ $item == /* ]]; then
                # item starts with slash
                item="${item#/}"
                path_blocklist+=("$item")
            else
                volume_blocklist+=("$item")
            fi
        done

        # echo volume blocklist
        if [ ${#volume_blocklist[@]} -gt 0 ]; then
            echo "- volume_blocklist:"
            for vol in "${volume_blocklist[@]}"; do
                echo -e "\t- $vol"
            done
        fi

        # echo path blocklist
        if [ ${#path_blocklist[@]} -gt 0 ]; then
            echo "- path_blocklist:"
            for path in "${path_blocklist[@]}"; do
                echo -e "\t- $path"
            done
        fi
    fi

    echo
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

script_update_check() {
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

# docker
# ---

docker_stack_stop() {
    local container_ids
    local container_names

    echo "Stopping Docker stack: <$stack_name>"
    cd "$working_dir" || exit
    
    # check stack running, with at least one container running
    if docker compose ls --quiet --filter "name=$stack_name" | grep -q "$stack_name"; then
        stack_running=true

        # get running containers ids
        container_ids=$(docker compose ps --quiet --filter "status=running")

        # get running containers names
        if [ -n "$container_ids" ]; then
            # shellcheck disable=SC2086
            container_names=$(docker inspect --format '{{.Name}}' $container_ids | sed 's|^/||' | tr -d '\r')

            # print container names
            for name in $container_names; do
                echo "- $name"
            done

            # set global variables
            running_container_ids=$container_ids
            running_container_names=$container_names

        else
            echo "Error, stack running but no container IDs found!"
            exit 1
        fi

        # stop stack
        docker compose --progress "quiet" stop

    else
        stack_running=false
        echo "- Docker stack <$stack_name> not running, skipping docker stop"
    fi
    echo
}

docker_stack_start() {
    echo "Resuming Docker stack: <$stack_name>"

    # check stack was previously running
    if [ "$stack_running" = true ]; then
        cd "$working_dir" || exit

        # restart only previously running containers
        if [ -n "$running_container_ids" ]; then

            # print container names
            for name in $running_container_names; do
                echo "- $name"
            done

            # restart containers
            echo
            # shellcheck disable=SC2086
            docker start $running_container_ids
        fi

    else
        echo "- Docker stack <$stack_name> not previously running, skipping docker start"
    fi
    echo
}

docker_stack_dir() {
    # possible compose file names
    local compose_files=("compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml")
    # current directory name
    local current_dir
    current_dir=$(basename "$PWD") # "nginx"?

    # check neither $docker_dir or $stack_name were provided
    if [[ "$docker_dir" == "null" && "$stack_name" == "null" ]]; then
        echo "Info, neither docker_dir or stack_name were provided, using current directory"
    # but if $docker_dir was provided alone (likely as an environment variable), and is correct 
    elif [[ "$docker_dir/$current_dir" = "$(pwd)" && "$stack_name" == "null" ]]; then
        echo "Info, stack_name was not provided, using current directory"
    # otherwise something was provided, do not use current directory
    else
        # update working_dir with provided options
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

# backups
# ---

backup_working_dir() {
    local exclude_opts=""
    local exclude_info=""

    echo "Backup <$stack_name> directory: $working_dir"

    # set blocklist options
    if [ ${#path_blocklist[@]} -gt 0 ]; then
        for path in "${path_blocklist[@]}"; do
            exclude_opts+="--exclude=$path "
            exclude_info+="$path "
        done
        echo "- Skipping blocklisted paths: $exclude_info"
    fi

    # create archive with exclude options
    eval tar -czf "$backup_dir/$stack_name/d-$stack_name-$timestamp.tar.gz" "$exclude_opts" -C "$working_dir" .
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
        echo "Backup volume: <$volume_name>"

        # skip blocklisted volumes
        if [[ " ${volume_blocklist[*]} " == *" $volume_name "* ]]; then
            echo "- Skipping blocklisted volume"
            continue
        fi
        # create backup
        backup_volume "$volume_name"
    done
    echo
}

backup_volume() {
    local volume_name=$1

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
# ---

parse_args "$@"
main
