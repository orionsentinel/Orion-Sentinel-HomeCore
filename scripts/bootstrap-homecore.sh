#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Bootstrap Script
# =============================================================================
# This script prepares the environment for running HomeCore services.
# It is idempotent and can be re-run safely.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_DATA_ROOT="/srv/orion/homecore"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Orion-Sentinel-HomeCore Bootstrap        ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

generate_secret() {
    openssl rand -base64 32 | tr -d '\n' | head -c 32
}

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

log_info "Checking prerequisites..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root. Consider using a non-root user with sudo access."
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed."
    echo ""
    echo "Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker \$USER"
    echo "  # Log out and back in for group changes to take effect"
    echo ""
    exit 1
fi
log_success "Docker is installed: $(docker --version)"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose v2 is not available."
    echo ""
    echo "Docker Compose v2 should be included with Docker. Please ensure you have:"
    echo "  - Docker Engine 20.10.0 or later"
    echo "  - Docker Desktop includes Compose by default"
    echo ""
    exit 1
fi
log_success "Docker Compose is available: $(docker compose version --short)"

# Check if user is in docker group
if ! groups | grep -q docker; then
    log_warn "Current user is not in the docker group."
    echo "  You may need to run: sudo usermod -aG docker \$USER"
    echo "  Then log out and back in."
fi

# Check openssl for secret generation
if ! command -v openssl &> /dev/null; then
    log_warn "openssl not found. Will use alternative secret generation."
fi

# -----------------------------------------------------------------------------
# Environment Setup
# -----------------------------------------------------------------------------

log_info "Setting up environment..."

ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE="${REPO_ROOT}/env/.env.example"

if [ -f "$ENV_FILE" ]; then
    log_info "Found existing .env file. Loading configuration..."
    # shellcheck source=/dev/null
    source "$ENV_FILE"
else
    log_info "Creating .env file from template..."
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    log_success "Created .env file"
fi

# Load environment
# shellcheck source=/dev/null
source "$ENV_FILE"

# Set defaults if not defined
DATA_ROOT="${DATA_ROOT:-$DEFAULT_DATA_ROOT}"

# -----------------------------------------------------------------------------
# Generate Secrets
# -----------------------------------------------------------------------------

log_info "Checking secrets..."

SECRETS_UPDATED=false

# Generate POSTGRES_PASSWORD if it's the default
if grep -q "POSTGRES_PASSWORD=changeme" "$ENV_FILE" 2>/dev/null; then
    NEW_SECRET=$(generate_secret)
    sed -i "s/POSTGRES_PASSWORD=changeme/POSTGRES_PASSWORD=${NEW_SECRET}/" "$ENV_FILE"
    log_success "Generated POSTGRES_PASSWORD"
    SECRETS_UPDATED=true
fi

# Generate MEALIE_SECRET_KEY if it's the default
if grep -q "MEALIE_SECRET_KEY=changeme" "$ENV_FILE" 2>/dev/null; then
    NEW_SECRET=$(generate_secret)
    sed -i "s/MEALIE_SECRET_KEY=changeme/MEALIE_SECRET_KEY=${NEW_SECRET}/" "$ENV_FILE"
    log_success "Generated MEALIE_SECRET_KEY"
    SECRETS_UPDATED=true
fi

if [ "$SECRETS_UPDATED" = true ]; then
    log_warn "Secrets have been generated. Review your .env file."
fi

# Reload environment after secret generation
# shellcheck source=/dev/null
source "$ENV_FILE"

# -----------------------------------------------------------------------------
# Directory Structure
# -----------------------------------------------------------------------------

log_info "Creating data directories under ${DATA_ROOT}..."

# Create main data directory
if [ ! -d "$DATA_ROOT" ]; then
    sudo mkdir -p "$DATA_ROOT"
    sudo chown "$(id -u):$(id -g)" "$DATA_ROOT"
    log_success "Created ${DATA_ROOT}"
else
    log_info "Data directory already exists: ${DATA_ROOT}"
fi

# Create service directories
DIRECTORIES=(
    "homeassistant/config"
    "mosquitto/config"
    "mosquitto/data"
    "mosquitto/log"
    "zigbee2mqtt/data"
    "nodered/data"
    "esphome/config"
    "mealie/data"
    "mealie/postgres"
)

for dir in "${DIRECTORIES[@]}"; do
    full_path="${DATA_ROOT}/${dir}"
    if [ ! -d "$full_path" ]; then
        mkdir -p "$full_path"
        log_success "Created ${full_path}"
    fi
done

# Copy default configs if they don't exist
log_info "Copying default configurations..."

# Home Assistant config
if [ ! -f "${DATA_ROOT}/homeassistant/config/configuration.yaml" ]; then
    cp "${REPO_ROOT}/stacks/homeassistant/config/configuration.yaml" "${DATA_ROOT}/homeassistant/config/"
    cp "${REPO_ROOT}/stacks/homeassistant/config/automations.yaml" "${DATA_ROOT}/homeassistant/config/"
    cp "${REPO_ROOT}/stacks/homeassistant/config/scenes.yaml" "${DATA_ROOT}/homeassistant/config/"
    cp "${REPO_ROOT}/stacks/homeassistant/config/scripts.yaml" "${DATA_ROOT}/homeassistant/config/"
    log_success "Copied Home Assistant default config"
fi

# Mosquitto config
if [ ! -f "${DATA_ROOT}/mosquitto/config/mosquitto.conf" ]; then
    cp "${REPO_ROOT}/stacks/mqtt/config/mosquitto.conf" "${DATA_ROOT}/mosquitto/config/"
    mkdir -p "${DATA_ROOT}/mosquitto/config/passwords"
    log_success "Copied Mosquitto default config"
fi

# Zigbee2MQTT config
if [ ! -f "${DATA_ROOT}/zigbee2mqtt/data/configuration.yaml" ]; then
    cp "${REPO_ROOT}/stacks/zigbee/config/configuration.yaml" "${DATA_ROOT}/zigbee2mqtt/data/"
    log_success "Copied Zigbee2MQTT default config"
fi

# Fix permissions for services that run as non-root
log_info "Setting directory permissions..."
chmod -R 755 "${DATA_ROOT}"

# Mosquitto runs as user 1883 inside the container
sudo chown -R 1883:1883 "${DATA_ROOT}/mosquitto" 2>/dev/null || true

# Node-RED runs as user 1000 inside the container
chown -R 1000:1000 "${DATA_ROOT}/nodered" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Docker Network
# -----------------------------------------------------------------------------

log_info "Checking Docker network..."

if ! docker network inspect homecore_internal &> /dev/null; then
    docker network create homecore_internal
    log_success "Created homecore_internal network"
else
    log_info "Network homecore_internal already exists"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Bootstrap Complete!                       ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Data directory: ${DATA_ROOT}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Review and customize your configuration:"
echo "   sudo nano ${ENV_FILE}"
echo ""
echo "2. (Optional) Set your LAN IP for service binding:"
echo "   Edit HOST_IP in .env (default: 0.0.0.0)"
echo ""
echo "3. Start Home Assistant (core services):"
echo "   ./scripts/orionctl up"
echo ""
echo "4. (Optional) Enable additional profiles:"
echo "   ./scripts/orionctl up --profile mqtt --profile zigbee"
echo ""
echo "5. Access services at:"
echo "   Home Assistant: http://<your-ip>:${HA_PORT:-8123}"
echo "   Mosquitto MQTT: <your-ip>:${MQTT_PORT:-1883} (profile: mqtt)"
echo "   Zigbee2MQTT:    http://<your-ip>:${ZIGBEE_PORT:-8080} (profile: zigbee)"
echo "   Node-RED:       http://<your-ip>:${NODERED_PORT:-1880} (profile: nodered)"
echo "   ESPHome:        http://<your-ip>:${ESPHOME_PORT:-6052} (profile: esphome)"
echo "   Mealie:         http://<your-ip>:${MEALIE_PORT:-9000} (profile: mealie)"
echo ""
echo "For troubleshooting, run:"
echo "   ./scripts/orionctl doctor"
echo ""
