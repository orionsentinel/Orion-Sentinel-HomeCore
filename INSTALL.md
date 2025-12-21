# Installation Guide

This guide walks you through installing Orion-Sentinel-HomeCore on a Raspberry Pi 5 (or similar Linux system).

## Prerequisites

### Hardware

- **Raspberry Pi 5** with 8GB RAM (recommended)
  - 4GB works but limits concurrent services
- **SSD storage** (32GB minimum, 128GB+ recommended)
  - Use USB 3.0 or NVMe via HAT
  - SD cards are NOT recommended for production
- **Zigbee coordinator** (optional, for Zigbee profile)
  - Sonoff Zigbee 3.0 USB Dongle Plus
  - ConBee II
  - Similar USB coordinators

### Software

- **Ubuntu Server 24.04 LTS** (recommended)
- **Raspberry Pi OS Lite 64-bit** (alternative)
- **Docker Engine 24.0+**
- **Docker Compose v2**

## Step 1: Prepare the Operating System

### Ubuntu Server (Recommended)

1. Flash Ubuntu Server 24.04 to your SSD using Raspberry Pi Imager
2. Boot the Pi and complete initial setup
3. Update the system:

```bash
sudo apt update && sudo apt upgrade -y
```

4. Set a static IP address (recommended):

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Example configuration:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
          - 8.8.8.8
```

Apply changes:
```bash
sudo netplan apply
```

### Raspberry Pi OS

1. Flash Raspberry Pi OS Lite 64-bit to your SSD
2. Enable SSH and configure hostname via Raspberry Pi Imager
3. Boot and run:

```bash
sudo apt update && sudo apt upgrade -y
```

## Step 2: Install Docker

### Automated Installation (Recommended)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
exit
```

After logging back in, verify Docker:

```bash
docker --version
docker compose version
```

### Manual Installation (Ubuntu)

```bash
# Install prerequisites
sudo apt install -y apt-transport-https ca-certificates curl gnupg

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
```

## Step 3: Clone the Repository

```bash
# Clone to /opt/orion/homecore (recommended location)
sudo mkdir -p /opt/orion
sudo chown $USER:$USER /opt/orion

git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git /opt/orion/homecore
cd /opt/orion/homecore
```

Or clone to your home directory:

```bash
git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git
cd Orion-Sentinel-HomeCore
```

## Step 4: Run Bootstrap

The bootstrap script prepares your environment:

```bash
./scripts/bootstrap-homecore.sh
```

This script will:
- Verify Docker and Docker Compose are installed
- Create the data directory structure (`/srv/orion/homecore` by default)
- Generate secure passwords/secrets automatically
- Copy default configuration files
- Create the Docker networks

## Step 5: Configure Environment

Review and customize the environment file:

```bash
sudo nano .env
```

**Important settings to review:**

```bash
# Set your timezone
TZ=Europe/Amsterdam

# Set your LAN IP for service binding (default: 127.0.0.1 for localhost-only)
# Change to your machine's LAN IP (e.g., 192.168.1.100) for LAN access
# Or use 0.0.0.0 to bind to all interfaces (understand security implications)
HOST_IP=127.0.0.1

# Data storage location (created by bootstrap script)
DATA_ROOT=/srv/orion/homecore

# User/Group IDs (optional, for fine-grained permissions)
# PUID=1000
# PGID=1000
```

**Security Note**: The default `HOST_IP=127.0.0.1` makes services accessible only from the host machine. This is the most secure configuration. Change only if you need LAN access.

See [CONFIGURATION.md](CONFIGURATION.md) for all available settings and [SECURITY.md](SECURITY.md) for security best practices.

## Step 6: Start Services

### Start Home Assistant Only (Core)

```bash
./scripts/orionctl up
```

### Start Home Automation Stack

```bash
./scripts/orionctl up homeauto
```

This starts Home Assistant, Mosquitto, Zigbee2MQTT, and Node-RED.

### Start Individual Profiles

```bash
# Home Assistant + MQTT
./scripts/orionctl up --profile mqtt

# Home Assistant + MQTT + Zigbee
./scripts/orionctl up --profile mqtt --profile zigbee
```

## Step 7: Access Services

**Default Configuration (Localhost-only)**:

With the default `HOST_IP=127.0.0.1`, services are only accessible from the host machine:

| Service | URL |
|---------|-----|
| Home Assistant | http://localhost:8123 |
| Zigbee2MQTT | http://localhost:8080 |
| Node-RED | http://localhost:1880 |
| ESPHome | http://localhost:6052 |
| Mealie | http://localhost:9000 |

**LAN Access Configuration**:

If you set `HOST_IP` to your machine's IP (e.g., `192.168.1.100`), services will be accessible from your LAN:

| Service | URL |
|---------|-----|
| Home Assistant | http://192.168.1.100:8123 |
| Zigbee2MQTT | http://192.168.1.100:8080 |
| Node-RED | http://192.168.1.100:1880 |

**Verify Port Exposure**:

Check what ports are exposed and how:

```bash
# List container ports
docker ps --format '{{.Names}}\t{{.Ports}}'

# List listening ports on host
ss -lntp | grep -E ':(8123|1883|8080|1880|6052|9000)'
```

Expected output with `HOST_IP=127.0.0.1`:
- All ports should show `127.0.0.1:<port>` (not `0.0.0.0:<port>`)

See [SECURITY.md](SECURITY.md) for network exposure policies and best practices.

## Step 8: Initial Setup

### Home Assistant

1. Open http://\<ip\>:8123 in your browser
2. Create your admin account
3. Set your home location and preferences
4. Start adding integrations

### Zigbee2MQTT (if enabled)

1. Open http://\<ip\>:8080
2. Click "Permit join" to allow new devices to pair
3. Put your Zigbee device in pairing mode
4. Device should appear in the interface

## Optional: Enable Auto-Start on Boot

### Using systemd

```bash
# Copy service file
sudo cp systemd/homecore.service /etc/systemd/system/

# Edit to match your installation path
sudo nano /etc/systemd/system/homecore.service
```

Update `WorkingDirectory` if you didn't install to `/opt/orion/homecore`.

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable homecore
sudo systemctl start homecore

# Check status
sudo systemctl status homecore
```

## Verify Installation

Run the doctor command to check your installation:

```bash
./scripts/orionctl doctor
```

This checks:
- Docker daemon status
- Network configuration
- Port availability
- Directory permissions
- Service health

## Next Steps

- [CONFIGURATION.md](CONFIGURATION.md) - Customize your setup
- [OPERATIONS.md](OPERATIONS.md) - Learn daily operations (backup, update, etc.)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Fix common issues
- [SECURITY.md](SECURITY.md) - Security best practices and exposure policies
