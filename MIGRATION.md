# Migration Guide

This document provides guidance for migrating Orion-Sentinel-HomeCore to a new system or from an existing Home Assistant installation.

## Migration Scenarios

### Migrating to a New Raspberry Pi

1. **On the old system**: Create a backup

```bash
cd /opt/orion/homecore

# Stop services
./scripts/orionctl down

# Create backup
BACKUP_FILE="/tmp/homecore-migration-$(date +%Y%m%d).tar.gz"
sudo tar -czf "$BACKUP_FILE" -C /srv/orion homecore
cp .env /tmp/homecore-env.backup

# Transfer to new system
scp "$BACKUP_FILE" user@new-pi:/tmp/
scp /tmp/homecore-env.backup user@new-pi:/tmp/
```

2. **On the new system**: Restore

```bash
# Install prerequisites (see INSTALL.md)
# Clone repository
git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git /opt/orion/homecore
cd /opt/orion/homecore

# Restore data
sudo mkdir -p /srv/orion
sudo tar -xzf /tmp/homecore-migration-*.tar.gz -C /srv/orion

# Restore environment
cp /tmp/homecore-env.backup .env

# Update HOST_IP if needed
sudo nano .env

# Start services
./scripts/orionctl up
```

### Migrating from Existing Home Assistant

If you have an existing Home Assistant installation (HAOS, Core, or Docker):

1. **Export from existing installation**:

```bash
# Stop Home Assistant
# Copy configuration directory
tar -czf ha-config-backup.tar.gz -C /path/to/existing config/
```

2. **Import to HomeCore**:

```bash
# Run bootstrap
./scripts/bootstrap-homecore.sh

# Extract your config
sudo tar -xzf ha-config-backup.tar.gz -C /srv/orion/homecore/homeassistant/

# Start Home Assistant
./scripts/orionctl up
```

3. **Review integrations**: Some integrations may need reconfiguration after migration.

### Migrating Zigbee Network

To preserve your Zigbee device pairings:

1. **Backup Zigbee2MQTT data**:

```bash
# Stop Zigbee2MQTT
docker compose stop zigbee2mqtt

# Backup data
tar -czf z2m-backup.tar.gz -C /srv/orion/homecore zigbee2mqtt
```

2. **Restore on new system**:

```bash
# Extract backup
sudo tar -xzf z2m-backup.tar.gz -C /srv/orion/homecore/

# Update device path in .env if changed
sudo nano .env

# Start services
./scripts/orionctl up --profile mqtt --profile zigbee
```

**Important**: Use the same Zigbee coordinator hardware, or devices will need to be re-paired.

## Database Migration (Mealie)

To migrate Mealie with its database:

```bash
# On old system
docker exec mealie-db pg_dump -U mealie mealie > mealie-db-backup.sql

# On new system (after services are started)
docker exec -i mealie-db psql -U mealie mealie < mealie-db-backup.sql
```

## Post-Migration Checklist

- [ ] Update HOST_IP in `.env` for new network
- [ ] Verify all services start successfully
- [ ] Check Home Assistant integrations
- [ ] Verify Zigbee devices are connected
- [ ] Test MQTT connectivity
- [ ] Update any external systems pointing to old IP

## Future Enhancements

This guide will be expanded with:

- Automated migration scripts
- Cross-platform migration paths
- Rollback procedures
- High availability configurations
