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
./scripts/orionctl logs homeassistant --follow  # Follow logs
./scripts/orionctl logs mosquitto

# Restart services
./scripts/orionctl restart

# Validate configuration
./scripts/orionctl validate

# Health check
./scripts/orionctl doctor

# Backup all data
./scripts/orionctl backup
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

### Using the Backup Script (Recommended)

The included backup script handles everything automatically:

```bash
# Create a backup
./scripts/backup.sh
```

This creates a complete backup including:
- Home Assistant configuration
- Mosquitto configuration and data
- Zigbee2MQTT configuration
- Node-RED flows
- ESPHome configurations
- Mealie database dump and data
- `.env` configuration file

Backups are stored in `${DATA_ROOT}/backups` (default: `/srv/orion/homecore/backups`) and are automatically cleaned up (keeps last 7 backups).

### What to Backup

| Path | Description | Frequency |
|------|-------------|-----------|
| `${DATA_ROOT}/homeassistant/config/` | HA configuration | Daily |
| `${DATA_ROOT}/zigbee2mqtt/data/` | Z2M config and device DB | Daily |
| `${DATA_ROOT}/nodered/data/` | Node-RED flows | After changes |
| `${DATA_ROOT}/mealie/` | Mealie data + Postgres dump | Weekly |
| `.env` | Environment configuration | After changes |

### Automated Backups

Add to crontab for automatic daily backups:

```bash
crontab -e
```

Add this line:

```
# Daily backup at 3 AM
0 3 * * * cd /opt/orion/homecore && ./scripts/backup.sh >> /var/log/homecore-backup.log 2>&1
```

### Offsite Backup

Copy backups to external storage:

```bash
# Copy to external drive
rsync -av /srv/orion/homecore/backups/ /mnt/external/homecore-backups/

# Copy to NAS (via rsync)
rsync -av /srv/orion/homecore/backups/ user@nas:/backups/homecore/

# Copy to cloud storage (using rclone)
rclone sync /srv/orion/homecore/backups/ remote:homecore-backups/
```

### Restore from Backup

Use the restore script:

```bash
# List available backups
ls -la /srv/orion/homecore/backups/

# Restore from specific backup
./scripts/restore.sh homecore_backup_20241221_030000
```

The restore script will:
1. Stop all running services
2. Create a safety backup of current data
3. Restore data from the specified backup
4. Optionally restore the database
5. Provide instructions to restart services

**Manual Restore** (if script fails):

```bash
# Stop services
./scripts/orionctl down

# Restore data (example with specific backup)
BACKUP_PATH="/srv/orion/homecore/backups/homecore_backup_20241221_030000"

tar -xzf "${BACKUP_PATH}/homeassistant_config.tar.gz" -C /srv/orion/homecore/homeassistant
tar -xzf "${BACKUP_PATH}/mosquitto.tar.gz" -C /srv/orion/homecore
tar -xzf "${BACKUP_PATH}/zigbee2mqtt_config.tar.gz" -C /srv/orion/homecore/zigbee2mqtt
tar -xzf "${BACKUP_PATH}/nodered_flows.tar.gz" -C /srv/orion/homecore/nodered
tar -xzf "${BACKUP_PATH}/esphome_config.tar.gz" -C /srv/orion/homecore/esphome
tar -xzf "${BACKUP_PATH}/mealie_data.tar.gz" -C /srv/orion/homecore/mealie

# Restore Mealie database
docker compose up -d mealie-db
sleep 10
cat "${BACKUP_PATH}/mealie_db.sql" | docker exec -i mealie-db psql -U mealie mealie

# Restore .env if needed
cp "${BACKUP_PATH}/.env" .

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

## Systemd Service Management

The systemd service provides automatic startup on boot and system-level service management.

### Install systemd Service

Use the provided script to install and enable the service:

```bash
./scripts/install-systemd.sh
```

This automatically configures the service to start the "core" bundle (Home Assistant) on boot.

### Manage with systemd

```bash
# Check service status
sudo systemctl status homecore --no-pager

# Start the service
sudo systemctl start homecore

# Stop the service
sudo systemctl stop homecore

# Restart the service
sudo systemctl restart homecore

# View logs (follow mode)
sudo journalctl -u homecore -f

# View recent logs
sudo journalctl -u homecore -e --no-pager
```

### Change Boot Bundle

By default, the systemd service starts the "core" bundle (Home Assistant only) on boot.

To change which bundle starts automatically:

1. **Edit the systemd unit file**:

```bash
sudo nano /etc/systemd/system/homecore.service
```

2. **Modify the ExecStart and ExecStop lines**:

For example, to start the full home automation stack on boot:

```ini
ExecStart=/bin/bash -c '/path/to/repo/scripts/orionctl up homeauto'
ExecStop=/bin/bash -c '/path/to/repo/scripts/orionctl down homeauto'
ExecReload=/bin/bash -c '/path/to/repo/scripts/orionctl restart homeauto'
```

Available bundles:
- `core` - Home Assistant only (default)
- `homeauto` - Home Assistant + MQTT + Zigbee + Node-RED
- `apps` - Mealie recipe manager
- `all` - All services

3. **Reload systemd and restart the service**:

```bash
sudo systemctl daemon-reload
sudo systemctl restart homecore
```

4. **Verify the changes**:

```bash
sudo systemctl status homecore --no-pager
./scripts/orionctl ps
```

### Uninstall systemd Service

To remove the systemd service:

```bash
./scripts/uninstall-systemd.sh
```

This will stop, disable, and remove the service. HomeCore will need to be started manually after this.

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
| Backup | Daily | `./scripts/orionctl backup` or automated cron |
| Update images | Weekly | `./scripts/orionctl update` |
| Validate config | Before changes | `./scripts/orionctl validate` |
| Docker cleanup | Monthly | `docker system prune -f` |
| Review logs | Weekly | Check for errors/warnings |
| Test restore | Quarterly | `./scripts/restore.sh <backup>` on test system |
| Security review | Quarterly | Review exposed ports: `ss -lntp` |
