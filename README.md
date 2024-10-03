# compose-backupdate
<img src="header.webp">

Bash script to perform backups with updates, or scheduled backups for docker compose stacks.

See the offical Docker documentation for more details on ['Back up, restore, or migrate data volumes'](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes).

## Setup

### Install
> [!WARNING]  
> This script is provided as-is, without any warranty. Use it at your own risk.

> [!NOTE]  
> Install command and script must be run with root permissions.

```bash
bash -c 'curl -fsSL -o /bin/backupdate https://raw.githubusercontent.com/hazzuk/compose-backupdate/refs/heads/main/backupdate.sh && chmod +x /bin/backupdate'
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

## Usage

### Script options
- `-b ""`, `--backup-dir ""`: Desired backup directory  
- `-d ""`, `--docker-dir ""`: Docker Compose directories parent
- `-s ""`, `--stack-name ""`: Docker Compose stack name  
- `-u`, `--update`: Update Docker stack (optional)  
- `-v`, `--version`: Check script version for updates (optional)


### Environment variables
```bash
# desired backup directory
export BACKUP_DIR="/path/to/your/backup"
# docker compose collection directory
export DOCKER_DIR="/path/to/your/docker"
# docker compose stack name
export STACK_NAME="nginx"
```

### Examples

#### Backups
```bash
backupdate -s "nginx" -d "/path/to/your/docker" -b "/path/to/your/backup"
```
```bash
backupdate --stack-name "nginx" \
    --docker-dir "/very/long/path/to/docker" \
    --backup-dir "/very/long/path/to/the/backup"
```

#### Updates (manual)
> [!TIP]
> backupdate automatically searches for a `compose.yaml` file inside your current directory (won't require `-d` or `-s`).

```bash
cd /path/to/your/docker/nginx

backupdate -u -b "/path/to/your/backup"
```

#### Scheduled backups
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
