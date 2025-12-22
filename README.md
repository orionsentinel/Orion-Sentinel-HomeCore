# Orion-Sentinel-HomeCore

**A production-ready home automation platform for Raspberry Pi 5.**

Orion-Sentinel-HomeCore provides a modular, Docker-based stack for running Home Assistant and related home automation services. Designed for stability, ease of use, and **local-only operation by default** with strong security practices.

## Features

### Core Services
- **Home Assistant** - Core home automation platform
- **Mosquitto MQTT** - Message broker for IoT devices
- **Zigbee2MQTT** - Bridge for Zigbee devices
- **Node-RED** - Flow-based automation
- **ESPHome** - ESP device management
- **Mealie** - Recipe and meal planning

### Monitoring & Dashboard (New!)
- **Homepage** - Unified dashboard with auto-discovery across all Orion nodes
- **Uptime Kuma** - Service uptime monitoring and status pages
- **Multi-node Discovery** - Auto-discover containers from HomeCore, DataAICore, DNS, and NetSec

See [MULTI-NODE-SETUP.md](MULTI-NODE-SETUP.md) for complete multi-node configuration.

## Security First

- **Local-only by default**: Services bind to `127.0.0.1` (localhost) for maximum security
- **Network isolation**: Dual network architecture (internal + LAN)
- **Strong secrets**: Auto-generated secure passwords
- **Resource limits**: Memory reservations and logging controls
- **Production hardening**: init processes, graceful shutdowns, health checks

See [SECURITY.md](SECURITY.md) for complete security policies.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git
cd Orion-Sentinel-HomeCore

# Run bootstrap script (creates directories, generates secrets)
./scripts/bootstrap-homecore.sh

# Start core services (Home Assistant)
./scripts/orionctl up

# Start the full home automation stack
./scripts/orionctl up homeauto

# Start Homepage dashboard and monitoring
./scripts/orionctl up ui
```

**Default Access** (localhost-only):
- Home Assistant: http://localhost:8123
- Homepage: http://localhost:3001 (with `ui` profile)
- Uptime Kuma: http://localhost:3001 (with `ui` profile)

For LAN access, edit `.env` and change `HOST_IP=127.0.0.1` to your machine's IP.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Raspberry Pi 5                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │  Home Assistant │  │  Mosquitto  │  │   Zigbee2MQTT   │ │
│  │     :8123       │  │    :1883    │  │      :8080      │ │
│  └────────┬────────┘  └──────┬──────┘  └────────┬────────┘ │
│           │                  │                   │          │
│           └──────────────────┼───────────────────┘          │
│                              │                              │
│  ┌─────────────┐  ┌──────────┴──────────┐  ┌─────────────┐ │
│  │  Node-RED   │  │  homecore_internal  │  │   ESPHome   │ │
│  │    :1880    │  │   (Docker Network)  │  │    :6052    │ │
│  └─────────────┘  └─────────────────────┘  └─────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                      Mealie                              ││
│  │                      :9000                               ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Service URLs

**Default Configuration** (localhost-only, most secure):

| Service | URL | Profile |
|---------|-----|---------|
| Home Assistant | http://localhost:8123 | (default) |
| Homepage | http://localhost:3001 | portal |
| Uptime Kuma | http://localhost:3001 | status |
| Mosquitto MQTT | localhost:1883 | mqtt |
| Zigbee2MQTT | http://localhost:8080 | zigbee |
| Node-RED | http://localhost:1880 | nodered |
| ESPHome | http://localhost:6052 | esphome |
| Mealie | http://localhost:9000 | mealie |

**Quick bundles:**
- `./scripts/orionctl up ui` - Homepage + Uptime Kuma (monitoring dashboard)
- `./scripts/orionctl up homeauto` - Full home automation (HA + MQTT + Zigbee + Node-RED)

**For LAN Access**: Set `HOST_IP` in `.env` to your machine's IP (e.g., `192.168.1.100`). See [SECURITY.md](SECURITY.md) for details.

## Documentation

- [INSTALL.md](INSTALL.md) - Complete installation guide
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration reference
- [OPERATIONS.md](OPERATIONS.md) - Daily operations, backup, and maintenance
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [SECURITY.md](SECURITY.md) - Security policies and best practices
- [MULTI-NODE-SETUP.md](MULTI-NODE-SETUP.md) - **NEW!** Multi-node ops plane setup
- [MIGRATION.md](MIGRATION.md) - Migration guide

## Directory Structure

```
Orion-Sentinel-HomeCore/
├── compose.yaml              # Main compose orchestrator
├── env/
│   ├── .env.example          # Environment template
│   └── profiles.example      # Profile documentation
├── scripts/
│   ├── bootstrap-homecore.sh # Bootstrap script
│   ├── orionctl             # Operator CLI
│   └── doctor.sh            # Health checks
├── stacks/
│   ├── homeassistant/       # Home Assistant stack
│   ├── mqtt/                # Mosquitto stack
│   ├── zigbee/              # Zigbee2MQTT stack
│   ├── nodered/             # Node-RED stack
│   ├── esphome/             # ESPHome stack
│   └── mealie/              # Mealie stack
└── systemd/
    └── homecore.service     # Systemd service file
```

## Requirements

- Raspberry Pi 5 with 8GB RAM (recommended) or 4GB (limited services)
- Ubuntu Server 24.04 or Raspberry Pi OS (64-bit)
- Docker Engine 24.0+
- Docker Compose v2
- 32GB+ SSD storage (SD cards not recommended)

## Key Operational Commands

```bash
# Validate configuration
./scripts/orionctl validate

# Health check
./scripts/orionctl doctor

# Backup all data
./scripts/orionctl backup

# Update all services
./scripts/orionctl update

# View service status
./scripts/orionctl ps

# View logs
./scripts/orionctl logs homeassistant --follow
```

## License

MIT License - see [LICENSE](LICENSE) for details