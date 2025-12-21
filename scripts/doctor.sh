#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Doctor Script
# =============================================================================
# Health checks and diagnostics for HomeCore.
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

# Load environment if exists
if [ -f "${REPO_ROOT}/.env" ]; then
    # shellcheck source=/dev/null
    set -a
    source "${REPO_ROOT}/.env"
    set +a
fi

# Default values
DATA_ROOT="${DATA_ROOT:-/srv/orion/homecore}"
HA_PORT="${HA_PORT:-8123}"
MQTT_PORT="${MQTT_PORT:-1883}"
ZIGBEE_PORT="${ZIGBEE_PORT:-8080}"
NODERED_PORT="${NODERED_PORT:-1880}"
ESPHOME_PORT="${ESPHOME_PORT:-6052}"
MEALIE_PORT="${MEALIE_PORT:-9000}"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

check_pass() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}[✗]${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((CHECKS_WARNING++))
}

check_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# -----------------------------------------------------------------------------
# System Checks
# -----------------------------------------------------------------------------

echo "System Environment"
echo "────────────────────────────────────────────"

# Check Docker daemon
if docker info &> /dev/null; then
    check_pass "Docker daemon is running"
else
    check_fail "Docker daemon is not running or not accessible"
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    version=$(docker compose version --short)
    check_pass "Docker Compose v2 is available ($version)"
else
    check_fail "Docker Compose v2 is not available"
fi

# Check user in docker group
if groups | grep -q docker; then
    check_pass "Current user is in docker group"
else
    check_warn "Current user is not in docker group (may need sudo)"
fi

# Check disk space
disk_usage=$(df -h "${DATA_ROOT}" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
if [ -n "$disk_usage" ]; then
    if [ "$disk_usage" -lt 80 ]; then
        check_pass "Disk usage is healthy (${disk_usage}% used)"
    elif [ "$disk_usage" -lt 90 ]; then
        check_warn "Disk usage is getting high (${disk_usage}% used)"
    else
        check_fail "Disk usage is critical (${disk_usage}% used)"
    fi
else
    check_warn "Could not check disk usage for ${DATA_ROOT}"
fi

echo ""
echo "Data Directory"
echo "────────────────────────────────────────────"

# Check DATA_ROOT
if [ -d "$DATA_ROOT" ]; then
    check_pass "Data directory exists: ${DATA_ROOT}"
    
    # Check writeability
    if [ -w "$DATA_ROOT" ]; then
        check_pass "Data directory is writable"
    else
        check_fail "Data directory is not writable"
    fi
else
    check_fail "Data directory does not exist: ${DATA_ROOT}"
    check_info "Run: ./scripts/bootstrap-homecore.sh"
fi

# Check subdirectories
for subdir in homeassistant mosquitto zigbee2mqtt nodered esphome mealie; do
    if [ -d "${DATA_ROOT}/${subdir}" ]; then
        check_pass "Directory exists: ${subdir}"
    else
        check_warn "Directory missing: ${subdir}"
    fi
done

echo ""
echo "Docker Network"
echo "────────────────────────────────────────────"

# Check network
if docker network inspect homecore_internal &> /dev/null; then
    check_pass "Docker network 'homecore_internal' exists"
else
    check_warn "Docker network 'homecore_internal' does not exist"
    check_info "Will be created when services start"
fi

echo ""
echo "Port Availability"
echo "────────────────────────────────────────────"

# Function to check if port is in use
check_port() {
    local port="$1"
    local service="$2"
    
    if ss -lntp 2>/dev/null | grep -q ":${port} " || \
       netstat -lntp 2>/dev/null | grep -q ":${port} "; then
        # Check if it's our service
        if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "${port}->"; then
            check_pass "Port ${port} is in use by ${service} (Docker)"
        else
            check_warn "Port ${port} is in use (not by Docker)"
        fi
    else
        check_pass "Port ${port} is available for ${service}"
    fi
}

check_port "$HA_PORT" "Home Assistant"
check_port "$MQTT_PORT" "Mosquitto MQTT"
check_port "$ZIGBEE_PORT" "Zigbee2MQTT"
check_port "$NODERED_PORT" "Node-RED"
check_port "$ESPHOME_PORT" "ESPHome"
check_port "$MEALIE_PORT" "Mealie"

echo ""
echo "Service Status"
echo "────────────────────────────────────────────"

# Check running containers
running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null)

for container in homeassistant mosquitto zigbee2mqtt nodered esphome mealie mealie-db; do
    if echo "$running_containers" | grep -q "^${container}$"; then
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
        if [ "$health" = "healthy" ]; then
            check_pass "Container ${container} is running and healthy"
        elif [ "$health" = "unhealthy" ]; then
            check_fail "Container ${container} is running but unhealthy"
        else
            check_pass "Container ${container} is running"
        fi
    else
        check_info "Container ${container} is not running"
    fi
done

echo ""
echo "USB Devices (Zigbee)"
echo "────────────────────────────────────────────"

# Check for USB devices (for Zigbee coordinators)
ZIGBEE_DEVICE="${ZIGBEE_DEVICE:-/dev/ttyUSB0}"
if [ -e "$ZIGBEE_DEVICE" ]; then
    check_pass "Zigbee device exists: ${ZIGBEE_DEVICE}"
    
    # Check permissions
    if [ -r "$ZIGBEE_DEVICE" ] && [ -w "$ZIGBEE_DEVICE" ]; then
        check_pass "Zigbee device is accessible"
    else
        check_warn "Zigbee device may not be accessible (check dialout group)"
        check_info "Run: sudo usermod -aG dialout \$USER"
    fi
else
    check_info "Zigbee device not found: ${ZIGBEE_DEVICE}"
    check_info "This is normal if you don't have a Zigbee coordinator"
fi

# List available USB devices
if ls /dev/ttyUSB* &> /dev/null || ls /dev/ttyACM* &> /dev/null; then
    check_info "Available serial devices:"
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | while read -r line; do
        echo "        $line"
    done
fi

echo ""
echo "Configuration Files"
echo "────────────────────────────────────────────"

# Check .env file
if [ -f "${REPO_ROOT}/.env" ]; then
    check_pass ".env file exists"
    
    # Check for default passwords
    if grep -q "PASSWORD=changeme" "${REPO_ROOT}/.env" 2>/dev/null; then
        check_warn "Default passwords detected in .env"
        check_info "Run bootstrap script to generate secure passwords"
    fi
else
    check_warn ".env file does not exist"
    check_info "Run: ./scripts/bootstrap-homecore.sh"
fi

# Check Home Assistant config
if [ -f "${DATA_ROOT}/homeassistant/config/configuration.yaml" ]; then
    check_pass "Home Assistant configuration exists"
else
    check_info "Home Assistant configuration not found (will use defaults)"
fi

# Check Mosquitto config
if [ -f "${DATA_ROOT}/mosquitto/config/mosquitto.conf" ]; then
    check_pass "Mosquitto configuration exists"
else
    check_info "Mosquitto configuration not found"
fi

echo ""
echo "────────────────────────────────────────────"
echo "Summary"
echo "────────────────────────────────────────────"
echo -e "${GREEN}Passed:${NC}   ${CHECKS_PASSED}"
echo -e "${YELLOW}Warnings:${NC} ${CHECKS_WARNING}"
echo -e "${RED}Failed:${NC}   ${CHECKS_FAILED}"
echo ""

if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo -e "${RED}Some checks failed. Please address the issues above.${NC}"
    exit 1
elif [ "$CHECKS_WARNING" -gt 0 ]; then
    echo -e "${YELLOW}System is mostly healthy, but there are warnings to review.${NC}"
    exit 0
else
    echo -e "${GREEN}All checks passed! System is healthy.${NC}"
    exit 0
fi
