# compose-backupdate
<img src="header.webp">

Bash script to perform backups with updates, and scheduled backups for docker compose stacks.

See offical Docker documentation for more details on ['Back up, restore, or migrate data volumes'](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes).

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

### Run script
```bash
backupdate
```

### Run script with arguments
`-b`: desired backup directory \
`-d`: docker compose collection directory \
`-s`: docker compose stack name
```bash
backupdate -b "/path/to/your/backup" -d "/path/to/your/docker" -s "nginx"
```

### Alternatively configure with environment variables
```bash
# desired backup directory
export BACKUP_DIR="/path/to/your/backup"
# docker compose collection directory
export DOCKER_DIR="/path/to/your/docker"
# docker compose stack name
export STACK_NAME="nginx"
```
