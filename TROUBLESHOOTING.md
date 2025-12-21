# Troubleshooting Guide

This document helps diagnose and resolve common issues with Orion-Sentinel-HomeCore.

## Quick Diagnostics

Always start with the doctor command:

```bash
./scripts/orionctl doctor
```

This checks:
- Docker daemon status
- Docker Compose availability
- Network configuration
- Port availability
- Directory permissions
- Service health

## Common Issues

### Port Conflicts

**Symptom**: Service fails to start with "port already in use" error.

**Diagnosis**:
```bash
# Check what's using a port
sudo ss -tlnp | grep :8123
sudo lsof -i :8123
```

**Solutions**:

1. Change the port in `.env`:
```bash
sudo nano .env
# Change HA_PORT=8123 to another port
```

2. Stop the conflicting service:
```bash
# If it's another Docker container
docker stop <container_name>

# If it's a system service
sudo systemctl stop <service_name>
```

### USB/Serial Device Access (Zigbee)

**Symptom**: Zigbee2MQTT can't access the USB coordinator.

**Diagnosis**:
```bash
# List available devices
ls -la /dev/ttyUSB* /dev/ttyACM*

# Check device permissions
stat /dev/ttyUSB0

# Check your user groups
groups
```

**Solutions**:

1. Add user to dialout group:
```bash
sudo usermod -aG dialout $USER
# Log out and back in
```

2. Update device path in `.env`:
```bash
sudo nano .env
# Set ZIGBEE_DEVICE to correct path

# Find stable device path
ls -la /dev/serial/by-id/
# Use the by-id path for reliability
ZIGBEE_DEVICE=/dev/serial/by-id/usb-Silicon_Labs_...
```

3. Check for udev rules (Raspberry Pi):
```bash
# Create udev rule for persistent permissions
sudo nano /etc/udev/rules.d/99-zigbee.rules
```

```
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", MODE="0666"
```

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

4. Restart with proper permissions:
```bash
./scripts/orionctl down
./scripts/orionctl up --profile mqtt --profile zigbee
```

### Storage Permission Issues

**Symptom**: Service fails with permission denied errors.

**Diagnosis**:
```bash
# Check directory ownership
ls -la /srv/orion/homecore/

# Check if directories are writable
touch /srv/orion/homecore/test && rm /srv/orion/homecore/test
```

**Solutions**:

1. Fix ownership:
```bash
sudo chown -R $USER:$USER /srv/orion/homecore
```

2. Fix specific service directories:
```bash
# Mosquitto runs as user 1883
sudo chown -R 1883:1883 /srv/orion/homecore/mosquitto

# Node-RED runs as user 1000
sudo chown -R 1000:1000 /srv/orion/homecore/nodered
```

3. Re-run bootstrap:
```bash
./scripts/bootstrap-homecore.sh
```

### Docker Network Issues

**Symptom**: Services can't communicate with each other.

**Diagnosis**:
```bash
# Check network exists
docker network ls | grep homecore

# Check containers are on the network
docker network inspect homecore_internal

# Test connectivity between containers
docker exec homeassistant ping -c 3 mosquitto
```

**Solutions**:

1. Recreate the network:
```bash
./scripts/orionctl down
docker network rm homecore_internal
docker network create homecore_internal
./scripts/orionctl up
```

2. Ensure services use the correct network name in compose files.

### Home Assistant Not Starting

**Symptom**: Home Assistant container keeps restarting or won't start.

**Diagnosis**:
```bash
# Check container logs
docker compose logs homeassistant

# Check container status
docker inspect homeassistant --format='{{.State.Status}} - {{.State.ExitCode}}'

# Check configuration
docker exec homeassistant hass --script check_config -c /config
```

**Solutions**:

1. Fix configuration syntax:
```bash
sudo nano /srv/orion/homecore/homeassistant/config/configuration.yaml
# Fix YAML syntax errors
```

2. Reset to default configuration:
```bash
docker compose stop homeassistant
sudo rm -rf /srv/orion/homecore/homeassistant/config/*
./scripts/bootstrap-homecore.sh
docker compose up -d homeassistant
```

3. Check for incompatible integrations:
```bash
# Look for error messages about specific integrations
docker compose logs homeassistant | grep -i error
```

### Mosquitto Won't Start

**Symptom**: Mosquitto container fails to start.

**Diagnosis**:
```bash
docker compose logs mosquitto
```

**Solutions**:

1. Fix configuration file permissions:
```bash
sudo chown -R 1883:1883 /srv/orion/homecore/mosquitto/
sudo chmod 644 /srv/orion/homecore/mosquitto/config/mosquitto.conf
```

2. Validate configuration:
```bash
docker run --rm -v /srv/orion/homecore/mosquitto/config:/mosquitto/config eclipse-mosquitto:2 mosquitto -c /mosquitto/config/mosquitto.conf -t
```

3. Reset configuration:
```bash
cp stacks/mqtt/config/mosquitto.conf /srv/orion/homecore/mosquitto/config/
```

### Zigbee2MQTT Connection Issues

**Symptom**: Zigbee2MQTT can't connect to MQTT broker.

**Diagnosis**:
```bash
docker compose logs zigbee2mqtt | grep -i mqtt
```

**Solutions**:

1. Ensure Mosquitto is running:
```bash
docker compose ps mosquitto
```

2. Check MQTT credentials in Zigbee2MQTT config:
```bash
sudo nano /srv/orion/homecore/zigbee2mqtt/data/configuration.yaml
```

```yaml
mqtt:
  server: mqtt://mosquitto:1883
  # If authentication is enabled:
  user: zigbee2mqtt
  password: your_password
```

3. Verify MQTT connectivity:
```bash
docker exec mosquitto mosquitto_sub -t '#' -v -C 1
```

### Mealie Database Issues

**Symptom**: Mealie can't connect to PostgreSQL.

**Diagnosis**:
```bash
docker compose logs mealie-db
docker compose logs mealie
```

**Solutions**:

1. Ensure database is healthy:
```bash
docker compose ps mealie-db
docker exec mealie-db pg_isready -U mealie
```

2. Reset database (⚠️ data loss):
```bash
docker compose down mealie mealie-db
sudo rm -rf /srv/orion/homecore/mealie/postgres/*
./scripts/orionctl up --profile mealie
```

3. Check environment variables:
```bash
grep POSTGRES .env
# Ensure POSTGRES_PASSWORD matches
```

### Service Not Accessible from Network

**Symptom**: Can't access service from another device on LAN.

**Diagnosis**:
```bash
# Check service is running
docker compose ps

# Check ports are published
docker port homeassistant

# Check firewall
sudo ufw status
sudo iptables -L -n | grep 8123
```

**Solutions**:

1. Check HOST_IP in `.env`:
```bash
# For LAN access, use 0.0.0.0 or your specific LAN IP
HOST_IP=0.0.0.0
```

2. Open firewall port:
```bash
sudo ufw allow 8123/tcp
```

3. Restart with correct binding:
```bash
./scripts/orionctl down
./scripts/orionctl up
```

### Out of Disk Space

**Symptom**: Services fail with "no space left on device" errors.

**Diagnosis**:
```bash
df -h
docker system df
```

**Solutions**:

1. Clean Docker resources:
```bash
docker system prune -a -f
docker volume prune -f
```

2. Clear old logs:
```bash
sudo truncate -s 0 /srv/orion/homecore/mosquitto/log/mosquitto.log
```

3. Reduce Home Assistant database:
```bash
# Edit configuration.yaml
recorder:
  purge_keep_days: 3
```

### Container Keeps Restarting

**Symptom**: Container restarts repeatedly.

**Diagnosis**:
```bash
# Check restart count
docker inspect --format='{{.RestartCount}}' homeassistant

# Check exit code
docker inspect --format='{{.State.ExitCode}}' homeassistant

# Check logs
docker compose logs --tail=50 homeassistant
```

**Solutions**:

1. Check resource limits:
```bash
free -h
docker stats --no-stream
```

2. Increase swap (if low memory):
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

3. Check for OOM kills:
```bash
dmesg | grep -i oom
```

## Log Analysis

### Finding Errors

```bash
# All errors
docker compose logs 2>&1 | grep -i error

# Specific service errors
docker compose logs homeassistant 2>&1 | grep -i error

# Recent errors
docker compose logs --since="1h" 2>&1 | grep -i error
```

### Common Log Locations

| Service | Container Logs | Persistent Logs |
|---------|---------------|-----------------|
| Home Assistant | `docker compose logs homeassistant` | `/srv/orion/homecore/homeassistant/config/home-assistant.log` |
| Mosquitto | `docker compose logs mosquitto` | `/srv/orion/homecore/mosquitto/log/mosquitto.log` |
| Zigbee2MQTT | `docker compose logs zigbee2mqtt` | `/srv/orion/homecore/zigbee2mqtt/data/log/` |

## Getting Help

### Information to Include

When asking for help, include:

1. Output of `./scripts/orionctl doctor`
2. Relevant logs: `docker compose logs <service> --tail=50`
3. Your `.env` file (with secrets redacted)
4. Operating system and version
5. Docker and Docker Compose versions

### Community Resources

- [Home Assistant Community](https://community.home-assistant.io/)
- [Zigbee2MQTT Documentation](https://www.zigbee2mqtt.io/)
- [Docker Documentation](https://docs.docker.com/)
