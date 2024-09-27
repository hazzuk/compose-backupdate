#!/bin/bash

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
# Bash script to perform backups+updates or regular backups for docker compose stacks
# https://github.com/hazzuk/compose-backupdate


# exit on any error
set -e

# check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error, please run as root"
    exit 1
fi

# user variables
# (can be overridden by env variables or script arguments)
backup_dir=${BACKUP_DIR:-"/home/user/backup"}
docker_dir=${DOCKER_DIR:-"/home/user/docker"}
stack_name=${STACK_NAME:-"nginx"}

# script variables
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
working_dir="$docker_dir/$stack_name"
stack_running=false

main() {
    echo "compose-backupdate $timestamp"
    echo "backup directory: $backup_dir"
    echo -e "working directory: $working_dir\n..."

    # create backup directory
    mkdir -p "$backup_dir" || { echo "Error, failed to create backup directory $backup_dir"; exit 1; }

    # stop stack before backup
    docker_stack_stop

    # backup compose stack working directory
    backup_working_dir

    # backup docker volumes
    backup_stack_volumes

    # start stack again if previously running
    docker_stack_start
}

usage() {
    echo "Usage: $0 [-b backup_dir] [-d docker_dir] [-s stack_name]"
    exit 1
}

parse_args() {
    while getopts ":b:d:s:" opt; do
        case $opt in
            b)
                backup_dir="$OPTARG"
                ;;
            d)
                docker_dir="$OPTARG"
                ;;
            s)
                stack_name="$OPTARG"
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                usage
                ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                usage
                ;;
        esac
    done
}

docker_stack_stop() {
    echo "Stopping docker stack: <$stack_name>"
    cd "$working_dir" || exit
    if docker compose ps --filter "status=running" | grep -q "$stack_name"; then
        stack_running=true
        docker compose stop
    else
        echo "Docker stack <$stack_name> not running, skipping compose stop"
    fi
    echo ...
}

docker_stack_start() {
    if [ "$stack_running" = true ]; then
        echo "Starting docker stack: <$stack_name>"
        cd "$working_dir" || exit
        docker compose up -d
    else
        echo "Docker stack <$stack_name> was previously not running, skipping compose start"
    fi
    echo ...
}

backup_working_dir() {
    echo "Backing up <$stack_name> directory: $working_dir"
    tar -czf "$backup_dir/$stack_name-$timestamp.tar.gz" -C "$working_dir" .
}

backup_stack_volumes() {
    # get all stack volumes
    local stack_volumes
    stack_volumes=$(
        docker volume ls --filter "label=com.docker.compose.project=$stack_name" --format "{{.Name}}"
    )

    # check volumes found
    if [ -z "$stack_volumes" ]; then
        echo "Info, no volumes found for <$stack_name>"
        return 1
    fi

    # backup each volume
    for volume_name in $stack_volumes; do
        backup_volume "$volume_name"
    done
    echo ...
}

backup_volume() {
    local volume_name=$1
    echo "Backing up <$stack_name> volume: <$volume_name>"
    
    # backup volume data with temporary container
    docker run --rm \
        -v "$volume_name":/volume_data \
        -v "$backup_dir":/backup \
        busybox tar czf "/backup/$volume_name-$timestamp.tar.gz" -C /volume_data . || \
        { echo "Error, failed to create backup container"; exit 1; }
}

# run script
parse_args "$@"
main
