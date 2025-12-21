# Configuration Reference

This document describes all configuration options for Orion-Sentinel-HomeCore.

## Environment Variables

All configuration is done through the `.env` file in the repository root. Copy from the template:

```bash
cp env/.env.example .env
sudo nano .env
```

### General Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `Europe/Amsterdam` | Timezone for all services |
| `HOST_IP` | `0.0.0.0` | IP address to bind services (use LAN IP to restrict access) |
| `DATA_ROOT` | `/srv/orion/homecore` | Root directory for all persistent data |
| `PUID` | `1000` | User ID for file permissions (optional) |
| `PGID` | `1000` | Group ID for file permissions (optional) |

### Home Assistant

| Variable | Default | Description |
|----------|---------|-------------|
| `HA_PORT` | `8123` | Home Assistant web interface port |

### Mosquitto MQTT

| Variable | Default | Description |
|----------|---------|-------------|
| `MQTT_PORT` | `1883` | MQTT broker port |

### Zigbee2MQTT

| Variable | Default | Description |
|----------|---------|-------------|
| `ZIGBEE_PORT` | `8080` | Zigbee2MQTT web interface port |
| `ZIGBEE_DEVICE` | `/dev/ttyUSB0` | Path to Zigbee USB coordinator device |

### Node-RED

| Variable | Default | Description |
|----------|---------|-------------|
| `NODERED_PORT` | `1880` | Node-RED web interface port |

### ESPHome

| Variable | Default | Description |
|----------|---------|-------------|
| `ESPHOME_PORT` | `6052` | ESPHome dashboard port |

### Mealie

| Variable | Default | Description |
|----------|---------|-------------|
| `MEALIE_PORT` | `9000` | Mealie web interface port |
| `MEALIE_DB_PORT` | `5432` | PostgreSQL database port (internal) |
| `POSTGRES_USER` | `mealie` | Database username |
| `POSTGRES_PASSWORD` | (generated) | Database password |
| `POSTGRES_DB` | `mealie` | Database name |
| `MEALIE_SECRET_KEY` | (generated) | Application secret key |

## Profiles

Profiles allow you to enable optional services without editing compose files. Enable profiles in your `.env`:

```bash
COMPOSE_PROFILES=mqtt,zigbee
```

Or pass profiles to orionctl:

```bash
./scripts/orionctl up --profile mqtt --profile zigbee
```

### Available Profiles

| Profile | Services | Description |
|---------|----------|-------------|
| (none) | Home Assistant | Core services only |
| `mqtt` | Mosquitto | MQTT broker |
| `zigbee` | Zigbee2MQTT | Zigbee bridge (requires mqtt) |
| `nodered` | Node-RED | Flow-based automation |
| `esphome` | ESPHome | ESP device management |
| `mealie` | Mealie + Postgres | Recipe manager |
| `ha-hostnet` | Home Assistant (host network) | Enable device discovery |

### Profile Bundles (orionctl shortcuts)

| Bundle | Profiles | Description |
|--------|----------|-------------|
| `core` | (none) | Home Assistant only |
| `homeauto` | mqtt, zigbee, nodered | Full home automation |
| `apps` | mealie | Application services |
| `all` | mqtt, zigbee, nodered, esphome, mealie | Everything |

## Service-Specific Configuration

### Home Assistant

Configuration file: `${DATA_ROOT}/homeassistant/config/configuration.yaml`

```bash
sudo nano /srv/orion/homecore/homeassistant/config/configuration.yaml
```

Example customizations:

```yaml
homeassistant:
  name: Home
  latitude: 52.3676
  longitude: 4.9041
  elevation: 0
  unit_system: metric
  time_zone: Europe/Amsterdam

# MQTT integration
mqtt:
  broker: mosquitto
  port: 1883
  # username: homeassistant
  # password: your_password

# Enable HTTP for reverse proxy (if needed)
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
```

### Mosquitto MQTT

Configuration file: `${DATA_ROOT}/mosquitto/config/mosquitto.conf`

```bash
sudo nano /srv/orion/homecore/mosquitto/config/mosquitto.conf
```

#### Enable Authentication

1. Create a password file:

```bash
docker exec -it mosquitto mosquitto_passwd -c /mosquitto/config/passwords/passwd myuser
```

2. Update mosquitto.conf:

```conf
listener 1883
persistence true
persistence_location /mosquitto/data/

# Enable authentication
allow_anonymous false
password_file /mosquitto/config/passwords/passwd
```

3. Restart Mosquitto:

```bash
./scripts/orionctl restart mqtt
```

#### Add Additional Users

```bash
docker exec -it mosquitto mosquitto_passwd /mosquitto/config/passwords/passwd newuser
```

### Zigbee2MQTT

Configuration file: `${DATA_ROOT}/zigbee2mqtt/data/configuration.yaml`

```bash
sudo nano /srv/orion/homecore/zigbee2mqtt/data/configuration.yaml
```

#### Configure Zigbee Device

Find your device:

```bash
ls -la /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/
```

Update your `.env`:

```bash
ZIGBEE_DEVICE=/dev/serial/by-id/usb-Silicon_Labs_Sonoff_Zigbee_3.0_USB_Dongle_Plus-if00-port0
```

#### Enable MQTT Authentication

If you enabled Mosquitto authentication:

```yaml
mqtt:
  server: mqtt://mosquitto:1883
  user: zigbee2mqtt
  password: your_password
```

#### Enable Device Pairing

In the web interface (http://\<ip\>:8080), click "Permit join" or update configuration.yaml:

```yaml
permit_join: true  # Set to false after pairing
```

### Node-RED

Data directory: `${DATA_ROOT}/nodered/data`

#### Install Additional Nodes

Access Node-RED at http://\<ip\>:1880, then:

1. Click the hamburger menu (☰)
2. Select "Manage palette"
3. Go to "Install" tab
4. Search and install nodes

Recommended nodes:
- `node-red-contrib-home-assistant-websocket` - Home Assistant integration

### ESPHome

Configuration directory: `${DATA_ROOT}/esphome/config`

```bash
sudo nano /srv/orion/homecore/esphome/config/my-device.yaml
```

Example device configuration:

```yaml
esphome:
  name: my-sensor
  platform: ESP8266
  board: nodemcuv2

wifi:
  ssid: "YourWiFi"
  password: "YourPassword"

# Enable logging
logger:

# Enable Home Assistant API
api:

# Enable OTA updates
ota:

sensor:
  - platform: dht
    pin: D1
    temperature:
      name: "Temperature"
    humidity:
      name: "Humidity"
    update_interval: 60s
```

### Mealie

Mealie is configured primarily through the web interface.

Access at: http://\<ip\>:9000

Default credentials are created during first access.

## Network Configuration

### Host Network Mode for Home Assistant

If you need device discovery (mDNS, SSDP), enable host network mode:

```bash
./scripts/orionctl down
./scripts/orionctl up --profile ha-hostnet
```

Note: In host network mode, Home Assistant uses port 8123 directly on the host.

### Firewall Rules (if using UFW)

```bash
# Allow Home Assistant
sudo ufw allow 8123/tcp

# Allow MQTT (if needed from other devices)
sudo ufw allow 1883/tcp

# Allow Zigbee2MQTT web interface
sudo ufw allow 8080/tcp

# Allow Node-RED
sudo ufw allow 1880/tcp
```

## Data Directory Structure

```
/srv/orion/homecore/
├── homeassistant/
│   └── config/               # HA configuration files
├── mosquitto/
│   ├── config/               # Mosquitto config
│   │   ├── mosquitto.conf
│   │   └── passwords/        # Password files
│   ├── data/                 # Persistent data
│   └── log/                  # Log files
├── zigbee2mqtt/
│   └── data/                 # Z2M data and config
├── nodered/
│   └── data/                 # Node-RED flows and settings
├── esphome/
│   └── config/               # ESPHome device configs
└── mealie/
    ├── data/                 # Mealie data
    └── postgres/             # PostgreSQL data
```
