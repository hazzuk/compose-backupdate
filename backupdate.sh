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
    echo "Please run as root"
    exit 1
fi


# user variables
backup_dir="/home/user/backup/temp"
docker_dir="/home/user/docker"
stack_name="outline"

# global variables
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
stack_dir="$docker_dir/$stack_name"

# create backup directory
mkdir -p "$backup_dir"


backup_directory() {
    local stack=$1 # e.g. 'outline'
    local path=$2 # e.g. '/home/user/docker/outline'

    echo "Stop docker stack: $stack"
    cd "$path" || exit
    if docker compose ps --filter "status=running" | grep -q "$stack"; then
        docker compose stop
    else
        echo "Docker stack $stack not running, skip stop"
    fi

    echo "Backup stack directory: $path"
    tar -czf "$backup_dir/$stack-$timestamp.tar.gz" -C "$path" .
}

backup_volume() {
    local volume=$1 # e.g. 'outline_database-data'
    local container=$2 # e.g. 'outline-postgres-1'
    local mount=$3 # e.g. '/var/lib/postgresql/data'

    echo "Backup docker volume: $container $volume"
    docker run --rm \
        --volumes-from "$container" \
        -v "$backup_dir":/backup \
        busybox tar czf "/backup/$volume-$timestamp.tar.gz" "$mount"
}


# main backup
backup_directory "$stack_name" "$stack_dir"

# user volume backups
backup_volume 'outline_storage-data' 'outline-outline-1' '/var/lib/outline/data'
backup_volume 'outline_database-data' 'outline-postgres-1' '/var/lib/postgresql/data'

# temporary fix to restart stack
cd "$stack_dir" || exit
docker compose up -d
