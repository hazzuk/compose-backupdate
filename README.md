# compose-backupdate
 Bash script to perform backups+updates or regular backups for docker compose stacks

> [!WARNING]  
> This script is provided as-is, without any warranty. Use it at your own risk.

## Setup

### Install
> [!NOTE]  
> Install command and script must be run as root.
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
