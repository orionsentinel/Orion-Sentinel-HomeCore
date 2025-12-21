# Orion-Sentinel-HomeCore

**A production-ready home automation platform for Raspberry Pi 5.**

Orion-Sentinel-HomeCore provides a modular, Docker-based stack for running Home Assistant and related home automation services. Designed for stability, ease of use, and local-only operation.

## Features

- **Home Assistant** - Core home automation platform
- **Mosquitto MQTT** - Message broker for IoT devices
- **Zigbee2MQTT** - Bridge for Zigbee devices
- **Node-RED** - Flow-based automation
- **ESPHome** - ESP device management
- **Mealie** - Recipe and meal planning

## Quick Start

```bash
# Clone the repository
git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git
cd Orion-Sentinel-HomeCore

# Run bootstrap script
./scripts/bootstrap-homecore.sh

# Start core services (Home Assistant)
./scripts/orionctl up

# Or start the full home automation stack
./scripts/orionctl up homeauto
```

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

| Service | URL | Profile |
|---------|-----|---------|
| Home Assistant | http://\<ip\>:8123 | (default) |
| Mosquitto MQTT | \<ip\>:1883 | mqtt |
| Zigbee2MQTT | http://\<ip\>:8080 | zigbee |
| Node-RED | http://\<ip\>:1880 | nodered |
| ESPHome | http://\<ip\>:6052 | esphome |
| Mealie | http://\<ip\>:9000 | mealie |

## Documentation

- [INSTALL.md](INSTALL.md) - Installation guide
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration reference
- [OPERATIONS.md](OPERATIONS.md) - Operations guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
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

- Raspberry Pi 5 with 8GB RAM (recommended)
- Ubuntu Server 24.04 or Raspberry Pi OS
- Docker Engine 24.0+
- Docker Compose v2
- 32GB+ SSD storage

## License

MIT License - see [LICENSE](LICENSE) for details