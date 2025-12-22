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
# Check networks exist
docker network ls | grep homecore

# Check containers are on the networks
docker network inspect homecore_internal
docker network inspect homecore_lan

# Test connectivity between containers
docker exec homeassistant ping -c 3 mosquitto
```

**Solutions**:

1. Recreate the networks:
```bash
./scripts/orionctl down
docker network rm homecore_internal homecore_lan
docker network create homecore_internal
docker network create homecore_lan
./scripts/orionctl up
```

2. Re-run bootstrap to ensure networks exist:
```bash
./scripts/bootstrap-homecore.sh
```

### Services Not Accessible from LAN

**Symptom**: Can't access services from other devices on your network.

**Diagnosis**:
```bash
# Check HOST_IP setting
grep HOST_IP .env

# Verify port bindings
docker ps --format '{{.Names}}\t{{.Ports}}'

# Check what's listening on host
ss -lntp | grep -E ':(8123|1883|8080|1880|6052|9000)'
```

**Solutions**:

1. If `HOST_IP=127.0.0.1` (default), change to your LAN IP or 0.0.0.0:
```bash
sudo nano .env
# Change: HOST_IP=127.0.0.1
# To: HOST_IP=192.168.1.100  (your machine's IP)
# Or: HOST_IP=0.0.0.0  (all interfaces - less secure)
```

2. Restart services:
```bash
./scripts/orionctl down
./scripts/orionctl up
```

3. Verify new bindings:
```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
# Should show your IP or 0.0.0.0 instead of 127.0.0.1
```

### Services Accessible But Not Wanted on LAN

**Symptom**: Services are exposed on LAN but you want localhost-only.

**Diagnosis**:
```bash
# Check current bindings
docker ps --format '{{.Names}}\t{{.Ports}}'
ss -lntp | grep -E ':(8123|1883|8080|1880|6052|9000)'
```

**Solution**:

1. Set HOST_IP to localhost:
```bash
sudo nano .env
# Change HOST_IP to: 127.0.0.1
```

2. Restart services:
```bash
./scripts/orionctl down
./scripts/orionctl up
```

3. Verify security:
```bash
# Should show 127.0.0.1:<port> for all services
docker ps --format '{{.Names}}\t{{.Ports}}'
```

See [SECURITY.md](SECURITY.md) for network exposure policies.

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

## Homepage and Uptime Kuma Issues

### Homepage Not Showing Services

**Symptom**: Homepage dashboard is empty or missing services.

**Diagnosis**:
```bash
# Check Homepage is running
docker compose ps | grep homepage

# Check docker-socket-proxy is healthy
docker inspect orion_home_dockerproxy | grep -i health

# Test Docker API access
docker exec orion_home_homepage wget -q -O - http://orion_home_dockerproxy:2375/containers/json
```

**Solutions**:

1. Verify docker-socket-proxy is running and healthy:
```bash
docker compose ps orion_home_dockerproxy
docker compose restart orion_home_dockerproxy
```

2. Check docker.yaml configuration:
```bash
cat ${DATA_ROOT}/homepage/docker.yaml
# Should have orion_home_dockerproxy endpoint
```

3. Verify containers have Homepage labels:
```bash
docker inspect homeassistant | grep homepage
# Should show homepage.* labels
```

4. Restart Homepage:
```bash
./scripts/orionctl restart portal
```

### Remote Node Services Not Appearing

**Symptom**: Services from DataAICore, DNS, or NetSec nodes don't appear in Homepage.

**Diagnosis**:
```bash
# Test remote docker proxy from HomeCore
curl http://<remote-node-ip>:2376/containers/json

# Check if port is open
nc -zv <remote-node-ip> 2376
```

**Solutions**:

1. On remote node, check docker-socket-proxy is running:
```bash
docker ps | grep dockerproxy
```

2. On remote node, check port is published:
```bash
ss -lntp | grep 2376
```

3. On remote node, verify firewall allows HomeCore:
```bash
sudo ufw status numbered
# Should show: allow from <HOMECORE_IP> to any port 2376
```

4. Add firewall rule on remote node if missing:
```bash
sudo ufw allow from <HOMECORE_IP> to any port 2376
sudo ufw reload
```

5. Verify docker.yaml has correct remote node IP:
```bash
cat ${DATA_ROOT}/homepage/docker.yaml
# Check IPs match actual node IPs
```

6. Update .env with correct node IPs:
```bash
sudo nano .env
# Set DATAAICORE_NODE_IP, DNS_NODE_IP, NETSEC_NODE_IP
```

### Homepage Configuration Not Applied

**Symptom**: Changes to Homepage configs don't appear.

**Solutions**:

1. Restart Homepage after config changes:
```bash
./scripts/orionctl restart portal
```

2. Check file permissions:
```bash
ls -la ${DATA_ROOT}/homepage/
# Files should be readable
```

3. Check for YAML syntax errors:
```bash
docker compose logs orion_home_homepage | grep -i error
docker compose logs orion_home_homepage | grep -i yaml
```

4. Verify config file exists:
```bash
ls -la ${DATA_ROOT}/homepage/settings.yaml
ls -la ${DATA_ROOT}/homepage/docker.yaml
```

### Uptime Kuma Widget Not Working

**Symptom**: Uptime Kuma status not showing in Homepage.

**Diagnosis**:
```bash
# Check Uptime Kuma is running
docker compose ps | grep uptime-kuma

# Check KUMA_STATUS_SLUG is set
grep KUMA_STATUS_SLUG .env
```

**Solutions**:

1. Create a Status Page in Uptime Kuma:
   - Open http://<homecore-ip>:3001
   - Go to Settings → Status Pages
   - Create new status page
   - Add monitors to the page
   - Copy the slug from URL

2. Set the slug in .env:
```bash
sudo nano .env
# Add: KUMA_STATUS_SLUG=your-slug-here
```

3. Uncomment Status section in services.yaml:
```bash
sudo nano ${DATA_ROOT}/homepage/services.yaml
# Uncomment the Status section
```

4. Restart Homepage:
```bash
./scripts/orionctl restart portal
```

### Homepage Can't Access Docker Socket Proxy

**Symptom**: Homepage logs show connection errors to docker proxy.

**Diagnosis**:
```bash
# Check logs
docker compose logs orion_home_homepage | grep -i proxy

# Check network connectivity
docker exec orion_home_homepage ping orion_home_dockerproxy

# Check proxy is on same network
docker inspect orion_home_homepage | grep Networks
docker inspect orion_home_dockerproxy | grep Networks
```

**Solutions**:

1. Ensure both containers are on homecore_internal network:
```bash
docker network inspect homecore_internal
# Should list both containers
```

2. Recreate containers:
```bash
./scripts/orionctl down portal
./scripts/orionctl up portal
```

3. Check docker-socket-proxy healthcheck:
```bash
docker inspect orion_home_dockerproxy --format='{{.State.Health.Status}}'
# Should be "healthy"
```

### Firewall Blocking Docker Proxy on Remote Node

**Symptom**: curl from HomeCore to remote docker proxy times out or is refused.

**Diagnosis**:
```bash
# From HomeCore
curl -v http://<remote-ip>:2376/version

# On remote node
sudo ufw status numbered
ss -lntp | grep 2376
```

**Solutions**:

1. On remote node, add firewall rule:
```bash
sudo ufw allow from <HOMECORE_IP> to any port 2376 comment 'Homepage docker proxy'
sudo ufw reload
```

2. Verify rule is active:
```bash
sudo ufw status | grep 2376
```

3. Test again from HomeCore:
```bash
curl http://<remote-ip>:2376/containers/json
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
| Homepage | `docker compose logs orion_home_homepage` | N/A (container logs only) |
| Uptime Kuma | `docker compose logs uptime-kuma` | N/A (container logs only) |

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
- [Homepage Documentation](https://gethomepage.dev/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)

