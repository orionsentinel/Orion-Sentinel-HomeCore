# Security Policy

## Overview

Orion-Sentinel-HomeCore is designed for **local-only operation** by default. This document outlines security best practices and exposure policies.

## Network Exposure Policy

### Default Configuration (Local-Only)

By default, all services bind to `127.0.0.1` (localhost), making them accessible only from the host machine:

- **Home Assistant**: `127.0.0.1:8123`
- **Mosquitto MQTT**: `127.0.0.1:1883`
- **Zigbee2MQTT**: `127.0.0.1:8080`
- **Node-RED**: `127.0.0.1:1880`
- **ESPHome**: `127.0.0.1:6052`
- **Mealie**: `127.0.0.1:9000`

### LAN Access

To expose services on your local network, edit `.env` and set `HOST_IP` to your machine's LAN IP address:

```bash
# Example: Make services accessible on LAN
HOST_IP=192.168.1.100

# OR bind to all interfaces (understand security implications)
HOST_IP=0.0.0.0
```

**Important**: Only change `HOST_IP` if you understand the security implications. Your LAN should be trusted.

### Internet Exposure

**⚠️ WARNING**: Do NOT expose HomeCore services directly to the internet without proper security measures.

If you need remote access:

1. **Recommended**: Use a VPN (WireGuard, Tailscale, etc.)
   - Secure, encrypted access to your LAN
   - No exposed ports to the internet
   - Easy to set up and manage

2. **Alternative**: Use Home Assistant Cloud (Nabu Casa)
   - Official remote access solution
   - Supports Home Assistant only
   - Paid subscription

3. **Not Recommended**: Port forwarding with reverse proxy
   - Requires significant security expertise
   - Requires SSL/TLS certificates
   - Requires regular security updates
   - Single point of failure

## Service-Specific Security

### Home Assistant

- **Authentication**: Required by default after initial setup
- **Best Practice**: Enable two-factor authentication
- **Exposure**: Can be safely exposed behind a reverse proxy with proper SSL/TLS

### Mosquitto MQTT

- **Authentication**: Configure username/password in `mosquitto.conf`
- **Best Practice**: Use ACLs to limit client permissions
- **Exposure**: Should remain internal-only; use MQTT over websockets through Home Assistant if needed

### Zigbee2MQTT

- **Authentication**: Basic auth available
- **Best Practice**: Keep on internal network only
- **Exposure**: Should never be exposed to internet

### Node-RED

- **Authentication**: Configurable in settings.js
- **Best Practice**: Enable authentication and HTTPS
- **Exposure**: Should remain internal-only or behind VPN

### ESPHome

- **Authentication**: Web dashboard has basic auth
- **Best Practice**: Use API encryption for devices
- **Exposure**: Should remain internal-only

### Mealie

- **Authentication**: User accounts required
- **Database**: PostgreSQL with generated password
- **Exposure**: Can be exposed with proper authentication, but VPN recommended

### Homepage

- **Authentication**: None by default (LAN-only dashboard)
- **Docker Access**: Uses docker-socket-proxy with restricted read-only permissions
- **Best Practice**: Keep LAN-only; firewall restrict docker-socket-proxy
- **Exposure**: Should remain internal-only or behind VPN

### Uptime Kuma

- **Authentication**: User account required after initial setup
- **Database**: SQLite (local file)
- **Best Practice**: Enable 2FA if available
- **Exposure**: Can be exposed with authentication, but VPN recommended

## Multi-Node Security (Orion Ops Plane)

### Docker Socket Proxy Security

The docker-socket-proxy provides read-only access to Docker API for Homepage auto-discovery. This is significantly safer than mounting raw `/var/run/docker.sock`.

**Security measures:**
- Read-only socket mount (`/var/run/docker.sock:ro`)
- Restricted endpoints (no container creation/deletion)
- Environment variables limit permissions:
  - POST=0 (no writes)
  - AUTH=0, SECRETS=0, CONFIGS=0 (no sensitive data access)

### Firewall Configuration for Remote Nodes

Each remote node (DataAICore, DNS, NetSec) runs docker-socket-proxy on port 2376. This port MUST be firewall-restricted to allow only HomeCore.

#### On Each Remote Node:

```bash
# Allow ONLY HomeCore IP to access docker-socket-proxy
sudo ufw allow from <HOMECORE_IP> to any port 2376 comment 'Homepage docker proxy'

# Explicitly deny all other access
sudo ufw deny 2376

# Reload firewall
sudo ufw reload

# Verify rule is active
sudo ufw status numbered
```

**Example:**
```bash
# If HomeCore is at 192.168.1.100
sudo ufw allow from 192.168.1.100 to any port 2376 comment 'Homepage docker proxy'
sudo ufw deny 2376
```

#### Verification:

```bash
# On remote node - check listening ports
ss -lntp | grep 2376
# Should show 0.0.0.0:2376 or <HOST_IP>:2376

# From HomeCore - should work
curl http://<remote-node-ip>:2376/containers/json

# From any other LAN device - should be blocked
curl http://<remote-node-ip>:2376/containers/json
# Should timeout or be refused
```

### Node Exporter and Promtail

For observability stack, additional ports need firewall rules:

```bash
# On all nodes: Allow DataAICore to scrape metrics
sudo ufw allow from <DATAAICORE_IP> to any port 9100 comment 'Prometheus scraping'
sudo ufw deny 9100

# Loki port on DataAICore (for Promtail pushes from all nodes)
# On DataAICore only:
sudo ufw allow from <HOMECORE_IP> to any port 3100 comment 'Loki logs from HomeCore'
sudo ufw allow from <DNS_NODE_IP> to any port 3100 comment 'Loki logs from DNS'
sudo ufw allow from <NETSEC_NODE_IP> to any port 3100 comment 'Loki logs from NetSec'
sudo ufw deny 3100
```

### Network Segmentation Best Practices

1. **Docker Socket Proxy**: Only accessible from Homepage (HomeCore IP only)
2. **Node Exporter**: Only accessible from Prometheus (DataAICore IP only)
3. **Loki**: Only accessible from Promtail agents (known node IPs only)
4. **Grafana/Prometheus**: LAN-only or VPN-only access

### Inter-Node Communication Matrix

| Source | Destination | Port | Purpose | Firewall Rule |
|--------|-------------|------|---------|---------------|
| HomeCore | All nodes | 2376 | Docker discovery | Allow from HomeCore IP |
| DataAICore | All nodes | 9100 | Metrics scraping | Allow from DataAICore IP |
| All nodes | DataAICore | 3100 | Log shipping | Allow from each node IP |
| LAN | HomeCore | 3001 | Homepage access | Allow from LAN (or restrict) |
| LAN | DataAICore | 3000,9090 | Grafana, Prom | Allow from LAN (or restrict) |

### Auditing and Monitoring

Monitor for unauthorized access attempts:

```bash
# Check firewall logs
sudo tail -f /var/log/ufw.log | grep DPT=2376

# Check failed connection attempts
sudo journalctl -u docker --since "1 hour ago" | grep -i refused

# Check docker-socket-proxy logs for unexpected access
docker logs orion_home_dockerproxy | grep -i error
```

## Network Isolation

HomeCore uses two Docker networks:

1. **homecore_internal**: For inter-service communication
   - Database services (mealie-db) are ONLY on this network
   - Not accessible from host or LAN
   - Docker socket proxy is ONLY on this network

2. **homecore_lan**: For LAN-accessible services
   - UI services are on BOTH internal and LAN networks
   - Port bindings controlled by `HOST_IP` variable

## Secrets Management

### Generated Secrets

Use the provided script to generate secure secrets:

```bash
./scripts/gen-secrets.sh
```

This generates:
- PostgreSQL passwords (32 characters)
- Application secrets (32 characters)

### Secret Storage

- Secrets are stored in `${DATA_ROOT}/secrets/` or `./secrets/`
- Both locations are gitignored
- Secrets have restrictive permissions (600)

### Environment Variables

The `.env` file contains sensitive configuration:
- Never commit `.env` to version control
- Use `.env.example` as a template
- Regenerate secrets when rotating credentials

## Data Protection

### Backups

Regular backups protect against:
- Hardware failure
- Accidental deletion
- Ransomware (if backups are offline)

```bash
# Create backup
./scripts/backup.sh

# Store backup offline or on separate storage
rsync -av /srv/orion/homecore/backups /path/to/external/storage/
```

### Backup Security

- Backups contain sensitive data (configurations, databases)
- Encrypt backups if storing off-site
- Limit access to backup storage
- Test restore procedures regularly

## Updates and Patching

### Container Images

```bash
# Update all container images
./scripts/orionctl update
```

Update frequency recommendations:
- **Home Assistant**: Monthly (check release notes)
- **Mosquitto**: Quarterly (stable releases)
- **Other services**: When security updates are released

### Host System

Keep the host OS updated:

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# Raspberry Pi OS
sudo apt update && sudo apt full-upgrade -y
```

### Docker Engine

```bash
# Check Docker version
docker --version

# Update Docker (Ubuntu/Debian)
sudo apt update && sudo apt install docker-ce docker-ce-cli
```

## Security Checklist

### Initial Setup

- [ ] Run bootstrap script to generate secrets
- [ ] Review `.env` configuration
- [ ] Set `HOST_IP` appropriately (default: `127.0.0.1`)
- [ ] Enable authentication on all services
- [ ] Change default passwords
- [ ] Enable Home Assistant 2FA

### Regular Maintenance

- [ ] Monthly: Update container images
- [ ] Monthly: Update host system
- [ ] Quarterly: Review user access
- [ ] Quarterly: Test backup/restore
- [ ] Quarterly: Review exposed ports (`ss -lntp`)
- [ ] Yearly: Rotate secrets and passwords

### Port Exposure Verification

Check what's exposed:

```bash
# List listening ports
ss -lntp

# List container ports
docker ps --format '{{.Names}}\t{{.Ports}}'

# Verify network bindings
docker compose ps
```

Expected output (default config):
- All ports should show `127.0.0.1:<port>` (not `0.0.0.0:<port>`)

## Incident Response

### Suspected Compromise

1. **Immediately**:
   - Stop all services: `./scripts/orionctl down`
   - Disconnect from network
   - Review logs: `./scripts/orionctl logs <service>`

2. **Investigate**:
   - Check Docker logs for unusual activity
   - Review Home Assistant audit logs
   - Check system logs: `journalctl -xe`

3. **Recover**:
   - Rotate all secrets: `./scripts/gen-secrets.sh`
   - Update `.env` with new secrets
   - Restore from known-good backup if needed
   - Update all container images
   - Review and tighten network exposure

## Reporting Security Issues

If you discover a security vulnerability in HomeCore configurations or scripts:

1. **Do NOT** open a public GitHub issue
2. Contact the maintainer privately via GitHub
3. Provide details about the vulnerability
4. Allow time for a fix before public disclosure

For vulnerabilities in upstream services (Home Assistant, etc.), report to those projects directly.

## Best Practices Summary

1. **Default to Local**: Keep `HOST_IP=127.0.0.1` unless you need LAN access
2. **Use VPN**: For remote access, use VPN instead of port forwarding
3. **Enable Authentication**: On all services that support it
4. **Regular Updates**: Keep containers and host system updated
5. **Backup Regularly**: Use `./scripts/backup.sh` and store offline
6. **Monitor Logs**: Check for suspicious activity
7. **Principle of Least Privilege**: Only expose what's necessary
8. **Defense in Depth**: Use multiple security layers (network isolation, authentication, encryption)

## Additional Resources

- [Home Assistant Security](https://www.home-assistant.io/docs/configuration/securing/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP IoT Security](https://owasp.org/www-project-internet-of-things/)
