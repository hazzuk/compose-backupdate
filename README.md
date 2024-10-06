# compose-backupdate
<img src="assets/header.webp">

Bash script for creating scheduled backups, and performing (backed-up) guided updates on Docker compose stacks.

## Why?
Because I needed a tool that was...

- Simple by design
- Doesn't require changes inside my `compose.yaml` files
- Works with both **bind mounts** and **named volumes**
- Can be used to create 🕑scheduled backups
- Can also create ad-hoc backups alongside guided container ⬆️updates
- Not trying to replace existing cloud backup tools (like rclone)

<br>

## Core Functionality

The core focus of *backupdate* is in creating archived backups of your Docker compose stacks.

### How it works

1. 🛑Stop any running containers in the Docker compose stack
1. 📁Create a **.tar.gz** backup of the stacks working directory
1. 📁Create **.tar.gz** backups of any associated named volumes
1. ⬇️Ask to pull any new container images (`-u`)
1. 🔁Recreate the Docker compose stack containers
1. 🗑️Ask to prune any unused container images (`-u`)

Read the official Docker documentation for more details on [Back up, restore, or migrate data volumes](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes).

<br>

## Setup

### Install
> [!WARNING]  
> This script is provided as-is, without any warranty. Use it at your own risk.

> [!IMPORTANT]  
> The install command and the script must be run with root permissions.

```bash
bash -c 'curl -fsSL -o /bin/backupdate https://raw.githubusercontent.com/hazzuk/compose-backupdate/refs/heads/release/backupdate.sh && chmod +x /bin/backupdate'
```

### Expected compose directory structure
The script expects your docker compose working directory to be located at `$docker_dir/$stack_name`:
```
docker/
├─ nginx/
│  └─ compose.yaml
├─ wordpress/
│  └─ compose.yaml
└─ nextcloud/
   └─ compose.yaml
```

<br>

## Options

### Command line
- `-b ""`, `--backup-dir ""`: Backup directory  
- `-d ""`, `--docker-dir ""`: Docker compose directory parent
- `-s ""`, `--stack-name ""`: Docker compose stack name  
- `-u`, `--update`: Update the stack containers *(optional)* 
- `-v`, `--version`: Check the script version for updates *(optional)*


### Environment variables
```bash
# backup directory
export BACKUP_DIR="/path/to/your/backup"
# docker compose directory parent
export DOCKER_DIR="/path/to/your/docker"
# docker compose stack name
export STACK_NAME="nginx"
```

<br>

## Example Usage

### 📀Backups
```bash
backupdate -s "nginx" -d "/path/to/your/docker" -b "/path/to/your/backup"
```
```bash
backupdate --stack-name "nginx" \
    --docker-dir "/very/long/path/to/docker" \
    --backup-dir "/very/long/path/to/the/backup"
```

### ⬆️Updates *(manual only)*
> [!NOTE]  
> Stack updates can only be performed manually. This is by design.

```bash
backupdate -u -s "nginx" -d "/path/to/your/docker" -b "/path/to/your/backup"
```

> [!TIP]
> *backupdate* automatically searches for a `compose.yaml` / `docker-compose.yaml` file inside your current directory (subsequently this won't require `-d` or `-s`).

```bash
cd /path/to/your/docker/nginx

backupdate -u -b "/path/to/your/backup"
```

### 🕑Scheduled backups
You can create a cron job or use another tool like [Cronicle](https://github.com/jhuckaby/Cronicle) to run the following example script periodically to backup your docker compose stacks:

```bash
#!/bin/bash

# set environment variables
export DOCKER_DIR="/path/to/your/docker"
export BACKUP_DIR="/path/to/your/backup"

# set stack names
stack_names=(
    "nginx"
    "portainer"
    "ghost"
    "home-assistant"
)

# create backups
for stack in "${stack_names[@]}"; do
    backupdate -s "$stack"
done

# upload backups to cloud storage
rclone sync $BACKUP_DIR dropbox:backup
```
