# Operations Guide

This document covers daily operations, maintenance, and best practices for Orion-Sentinel-HomeCore.

## Service Management

### Using orionctl

The `orionctl` command is your primary interface for managing services.

```bash
# Show help
./scripts/orionctl help

# Check service status
./scripts/orionctl ps

# Start services
./scripts/orionctl up              # Start core (Home Assistant)
./scripts/orionctl up homeauto     # Start home automation stack
./scripts/orionctl up --profile mqtt --profile zigbee

# Stop services
./scripts/orionctl down            # Stop all services
./scripts/orionctl down mqtt       # Stop specific stack

# View logs
./scripts/orionctl logs homeassistant
./scripts/orionctl logs mosquitto

# Restart services
./scripts/orionctl restart

# Health check
./scripts/orionctl doctor
```

### Using Make (Alternative)

```bash
make up                      # Start services
make down                    # Stop services
make ps                      # Show status
make logs SERVICE=homeassistant
make doctor
```

### Direct Docker Compose

```bash
docker compose ps
docker compose up -d
docker compose down
docker compose logs -f homeassistant
```

## Updates

### Update All Images

```bash
./scripts/orionctl update
```

This command:
1. Pulls the latest images for all services
2. Restarts running services with new images

### Update Specific Service

```bash
docker compose pull homeassistant
docker compose up -d homeassistant
```

### Check for Updates

```bash
docker compose pull --dry-run
```

## Backups

### What to Backup

| Path | Description | Frequency |
|------|-------------|-----------|
| `${DATA_ROOT}/homeassistant/config/` | HA configuration | Daily |
| `${DATA_ROOT}/zigbee2mqtt/data/` | Z2M config and device DB | Daily |
| `${DATA_ROOT}/nodered/data/` | Node-RED flows | After changes |
| `${DATA_ROOT}/mealie/` | Mealie data + Postgres | Weekly |
| `.env` | Environment configuration | After changes |

### Manual Backup

```bash
# Set backup directory
BACKUP_DIR="/backup/homecore/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Stop services for consistent backup
./scripts/orionctl down

# Backup data
sudo tar -czf "$BACKUP_DIR/homecore-data.tar.gz" -C /srv/orion homecore

# Backup configuration
cp .env "$BACKUP_DIR/"

# Restart services
./scripts/orionctl up
```

### Automated Backup Script

Create a backup script:

```bash
sudo nano /opt/orion/scripts/backup.sh
```

```bash
#!/bin/bash
set -e

BACKUP_ROOT="/backup/homecore"
DATA_ROOT="/srv/orion/homecore"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"

mkdir -p "$BACKUP_DIR"

# Backup Home Assistant (hot backup is safe)
tar -czf "${BACKUP_DIR}/homeassistant.tar.gz" -C "$DATA_ROOT" homeassistant

# Backup Zigbee2MQTT
tar -czf "${BACKUP_DIR}/zigbee2mqtt.tar.gz" -C "$DATA_ROOT" zigbee2mqtt

# Backup Node-RED
tar -czf "${BACKUP_DIR}/nodered.tar.gz" -C "$DATA_ROOT" nodered

# Backup Mealie with database dump
docker exec mealie-db pg_dump -U mealie mealie > "${BACKUP_DIR}/mealie.sql"
tar -czf "${BACKUP_DIR}/mealie.tar.gz" -C "$DATA_ROOT" mealie

# Cleanup old backups (keep 7 days)
find "$BACKUP_ROOT" -type d -mtime +7 -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR"
```

Add to crontab:

```bash
sudo crontab -e
```

```
# Daily backup at 3 AM
0 3 * * * /opt/orion/scripts/backup.sh >> /var/log/homecore-backup.log 2>&1
```

### Restore from Backup

```bash
# Stop services
./scripts/orionctl down

# Restore data
sudo tar -xzf /backup/homecore/20240101/homecore-data.tar.gz -C /srv/orion

# Restore environment
cp /backup/homecore/20240101/.env .

# Restore Mealie database (if needed)
docker compose up -d mealie-db
sleep 10
docker exec -i mealie-db psql -U mealie mealie < /backup/homecore/20240101/mealie.sql

# Start services
./scripts/orionctl up
```

## Monitoring

### Health Checks

Run the doctor command regularly:

```bash
./scripts/orionctl doctor
```

### Container Health

```bash
# Check container health status
docker ps --format "table {{.Names}}\t{{.Status}}"

# Detailed health info
docker inspect --format='{{.State.Health.Status}}' homeassistant
```

### Resource Usage

```bash
# Container resource usage
docker stats --no-stream

# System resources
htop
df -h
```

### Logs

```bash
# Follow all logs
docker compose logs -f

# Last 100 lines of specific service
docker compose logs --tail=100 homeassistant

# Since specific time
docker compose logs --since="1h" homeassistant
```

## Common Operations

### Restart a Stuck Service

```bash
docker compose restart homeassistant
```

### Clear Service Data (Reset)

⚠️ **Warning**: This deletes all data for the service!

```bash
# Stop the service
docker compose stop homeassistant

# Remove the container
docker compose rm -f homeassistant

# Clear data
sudo rm -rf /srv/orion/homecore/homeassistant/config/*

# Restore defaults and start
./scripts/bootstrap-homecore.sh
./scripts/orionctl up
```

### Add Zigbee Device

1. Open Zigbee2MQTT web interface: http://\<ip\>:8080
2. Click "Permit join" (or toggle in top right)
3. Put your Zigbee device in pairing mode
4. Device should appear within 60 seconds
5. Click "Disable join" when done

### Factory Reset Zigbee Network

⚠️ **Warning**: All devices will need to be re-paired!

```bash
# Stop Zigbee2MQTT
docker compose stop zigbee2mqtt

# Remove coordinator data
sudo rm /srv/orion/homecore/zigbee2mqtt/data/coordinator_backup.json
sudo rm /srv/orion/homecore/zigbee2mqtt/data/database.db

# Restart
docker compose up -d zigbee2mqtt
```

## Systemd Service

### Enable Auto-Start

```bash
# Copy service file
sudo cp systemd/homecore.service /etc/systemd/system/

# Edit paths if needed
sudo nano /etc/systemd/system/homecore.service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable homecore
```

### Manage with systemd

```bash
# Start
sudo systemctl start homecore

# Stop
sudo systemctl stop homecore

# Status
sudo systemctl status homecore

# View logs
sudo journalctl -u homecore -f
```

## Performance Tuning

### Reduce Memory Usage

For Raspberry Pi with limited RAM:

1. Limit concurrent services (use fewer profiles)
2. Add swap space:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Optimize Home Assistant

Edit `${DATA_ROOT}/homeassistant/config/configuration.yaml`:

```yaml
recorder:
  # Reduce database size
  purge_keep_days: 7
  commit_interval: 30

logger:
  default: warning
  logs:
    homeassistant.core: info
```

### Docker Cleanup

```bash
# Remove unused containers, networks, images
docker system prune -f

# Remove unused volumes (careful!)
docker volume prune -f

# Check disk usage
docker system df
```

## Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Health check | Daily | `./scripts/orionctl doctor` |
| Update images | Weekly | `./scripts/orionctl update` |
| Backup | Daily | Automated script |
| Docker cleanup | Monthly | `docker system prune -f` |
| Review logs | Weekly | Check for errors/warnings |
| Test restore | Quarterly | Restore backup to test system |
