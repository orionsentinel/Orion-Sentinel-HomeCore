# Implementation Summary: Multi-Node Orion Ops Plane

## What Was Implemented

This implementation adds a comprehensive monitoring and dashboard solution across all Orion nodes (HomeCore, DataAICore, DNS, NetSec).

### 1. HomeCore Changes (This Repository)

#### New Stacks

**Portal Stack** (`stacks/portal/`)
- Homepage dashboard with Docker auto-discovery
- Local docker-socket-proxy for safe Docker API access
- Multi-node configuration ready (discovers services from all nodes)
- Profile: `portal`
- Port: 3001 (configurable via `HOMEPAGE_PORT`)

**Status Stack** (`stacks/status/`)
- Uptime Kuma for service monitoring
- Status page integration with Homepage
- Profile: `status`
- Port: 3001 (configurable via `KUMA_PORT`)

#### Homepage Labels Added

All existing services now have Homepage auto-discovery labels:
- Home Assistant
- Mosquitto MQTT
- Zigbee2MQTT
- Node-RED
- ESPHome
- Mealie

Labels include:
- `homepage.group` - Grouping (HomeCore, DataAICore, etc.)
- `homepage.name` - Display name
- `homepage.icon` - Icon identifier
- `homepage.href` - Service URL
- `homepage.description` - Short description
- `homepage.weight` - Ordering within group
- `homepage.instance` - Instance identifier (homecore, dataaicore, etc.)

#### Configuration Files

**Homepage Configs** (`${DATA_ROOT}/homepage/`)
- `settings.yaml` - Dashboard settings, theme, layout
- `services.yaml` - Manual service links (Observability stack)
- `widgets.yaml` - Dashboard widgets (datetime, resources, search)
- `docker.yaml` - Multi-node Docker endpoints

#### Environment Variables

New variables in `.env.example`:
```bash
# Homepage
HOMEPAGE_IMAGE_TAG=latest
HOMEPAGE_PORT=3001

# Uptime Kuma
KUMA_IMAGE_TAG=1
KUMA_PORT=3001
KUMA_STATUS_SLUG=

# Multi-Node IPs
HOMECORE_NODE_IP=127.0.0.1
DATAAICORE_NODE_IP=192.168.1.10
DNS_NODE_IP=192.168.1.11
NETSEC_NODE_IP=192.168.1.12
REMOTE_DOCKER_PROXY_PORT=2376

# Observability (on DataAICore)
GRAFANA_PORT=3000
PROM_PORT=9090
LOKI_PORT=3100
```

#### Scripts Updated

**orionctl**
- New stack commands: `portal`, `status`
- New bundle: `ui` (portal + status)
- Updated help text

**bootstrap-homecore.sh**
- Creates Homepage directory
- Creates Uptime Kuma directory
- Copies default Homepage configs
- Prints Homepage and Kuma URLs

#### Documentation

- **INSTALL.md** - Homepage setup section with multi-node instructions
- **CONFIGURATION.md** - Homepage labels, widgets, multi-node config
- **OPERATIONS.md** - Homepage operations, config updates, troubleshooting
- **TROUBLESHOOTING.md** - Comprehensive Homepage troubleshooting
- **SECURITY.md** - Docker proxy security, firewall rules, multi-node security
- **MULTI-NODE-SETUP.md** - Complete multi-node setup guide (NEW!)
- **README.md** - Updated features and quick start

### 2. DataAICore Setup (Documented for Separate Implementation)

**Agent Stack** (`stacks/agent/compose.yaml`)
- docker-socket-proxy exposed on port 2376 (LAN-restricted)
- Firewall-restricted to accept only from HomeCore IP

**Observability Stack** (`stacks/observability/compose.yaml`)
- Grafana (port 3000)
- Prometheus (port 9090) with multi-node scraping
- Loki (port 3100) for log aggregation

All configurations provided in MULTI-NODE-SETUP.md.

### 3. DNS and NetSec Setup (Documented for Separate Implementation)

**Orion Agent** (`stacks/orion-agent/compose.yaml`)
- docker-socket-proxy (port 2376, firewall-restricted)
- node_exporter (port 9100) for Prometheus scraping
- promtail for shipping logs to Loki on DataAICore

All configurations provided in MULTI-NODE-SETUP.md.

## How to Use

### Single Node (HomeCore Only)

```bash
# Start Homepage and Uptime Kuma
./scripts/orionctl up ui

# Access
# Homepage: http://<homecore-ip>:3001
# Uptime Kuma: http://<homecore-ip>:3001
```

Homepage will auto-discover all running containers on HomeCore.

### Multi-Node Setup

1. **On HomeCore:**
```bash
# Edit .env and set node IPs
sudo nano .env

# Start Homepage
./scripts/orionctl up ui
```

2. **On DataAICore:**
```bash
# Set up agent and observability stacks
# See MULTI-NODE-SETUP.md for complete setup
./scripts/orionctl up agent observability

# Configure firewall
sudo ufw allow from <HOMECORE_IP> to any port 2376
```

3. **On DNS and NetSec:**
```bash
# Set up orion-agent stack
# See MULTI-NODE-SETUP.md for complete setup
docker compose -f stacks/orion-agent/compose.yaml up -d

# Configure firewall
sudo ufw allow from <HOMECORE_IP> to any port 2376
sudo ufw allow from <DATAAICORE_IP> to any port 9100
```

4. **Configure Uptime Kuma:**
- Create monitors for all services
- Create a Status Page
- Set `KUMA_STATUS_SLUG` in HomeCore .env
- Restart Homepage: `./scripts/orionctl restart portal`

## Security Features

### Docker Socket Proxy
- Read-only mount of docker.sock
- Restricted API endpoints (no writes, no secrets)
- Internal network only (local proxy)
- Firewall-restricted (remote proxies)

### Firewall Configuration
```bash
# On remote nodes - restrict docker proxy to HomeCore only
sudo ufw allow from <HOMECORE_IP> to any port 2376
sudo ufw deny 2376
```

### Network Isolation
- Homepage on homecore_internal + homecore_lan
- docker-socket-proxy on homecore_internal only (local)
- Remote proxies firewall-restricted via ufw

## File Structure

```
Orion-Sentinel-HomeCore/
├── stacks/
│   ├── portal/
│   │   ├── compose.yaml                    # Homepage + docker proxy
│   │   └── homepage/
│   │       └── config/
│   │           ├── settings.yaml           # Dashboard settings
│   │           ├── services.yaml           # Manual links
│   │           ├── widgets.yaml            # Widgets config
│   │           └── docker.yaml             # Multi-node Docker endpoints
│   ├── status/
│   │   └── compose.yaml                    # Uptime Kuma
│   └── [existing stacks with Homepage labels]
├── scripts/
│   ├── orionctl                            # Updated with portal/status
│   └── bootstrap-homecore.sh               # Creates homepage directories
├── env/
│   └── .env.example                        # Multi-node variables
├── MULTI-NODE-SETUP.md                     # Complete multi-node guide
└── [updated documentation]
```

## Testing the Implementation

### Verify Compose Configuration
```bash
docker compose config > /dev/null && echo "✓ Valid"
```

### Start Homepage
```bash
./scripts/orionctl up ui
```

### Check Services
```bash
# Should show homepage and docker proxy
docker compose ps | grep -E "(homepage|dockerproxy)"

# Check logs
docker compose logs orion_home_homepage --tail=50
```

### Access Homepage
```bash
# Open in browser
http://<homecore-ip>:3001
```

You should see all HomeCore services auto-discovered and grouped under "HomeCore".

## Next Steps

1. **Configure node IPs** in `.env` for multi-node discovery
2. **Set up docker-socket-proxy** on remote nodes (see MULTI-NODE-SETUP.md)
3. **Configure firewalls** on remote nodes to restrict access
4. **Set up Uptime Kuma** monitors and status page
5. **Deploy observability stack** on DataAICore (optional)
6. **Add node agents** on DNS and NetSec nodes (optional)

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for comprehensive troubleshooting, including:
- Homepage not showing services
- Remote node discovery issues
- Firewall blocking docker proxy
- Configuration not applied
- Uptime Kuma widget not working

## References

- [Homepage Documentation](https://gethomepage.dev/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy)
- [MULTI-NODE-SETUP.md](MULTI-NODE-SETUP.md) - Complete implementation guide
