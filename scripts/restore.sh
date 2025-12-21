#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Restore Script
# =============================================================================
# This script restores HomeCore data from a backup.
# Usage: ./scripts/restore.sh <backup_name>
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

# Configuration
DATA_ROOT="${DATA_ROOT:-/srv/orion/homecore}"
BACKUP_DIR="${BACKUP_DIR:-${DATA_ROOT}/backups}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  HomeCore Restore Script                  ${NC}"
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

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

if [ $# -eq 0 ]; then
    log_error "No backup specified"
    echo ""
    echo "Usage: $0 <backup_name>"
    echo ""
    echo "Available backups:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -1 "$BACKUP_DIR" | grep "^homecore_backup_" || echo "  (none found)"
    else
        echo "  Backup directory does not exist: ${BACKUP_DIR}"
    fi
    echo ""
    exit 1
fi

BACKUP_NAME="$1"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# -----------------------------------------------------------------------------
# Validate Backup
# -----------------------------------------------------------------------------

log_info "Validating backup: ${BACKUP_NAME}"

if [ ! -d "$BACKUP_PATH" ]; then
    log_error "Backup not found: ${BACKUP_PATH}"
    exit 1
fi

if [ ! -f "${BACKUP_PATH}/backup_info.txt" ]; then
    log_warn "Backup metadata not found. This may not be a valid backup."
fi

log_success "Backup found: ${BACKUP_PATH}"

# Display backup info
if [ -f "${BACKUP_PATH}/backup_info.txt" ]; then
    echo ""
    echo -e "${YELLOW}Backup Information:${NC}"
    cat "${BACKUP_PATH}/backup_info.txt"
    echo ""
fi

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------

echo -e "${RED}WARNING: This will restore data from the backup.${NC}"
echo -e "${RED}Current data will be backed up to ${DATA_ROOT}/.restore_backup_${TIMESTAMP}${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Restore cancelled by user"
    exit 0
fi

# -----------------------------------------------------------------------------
# Stop Services
# -----------------------------------------------------------------------------

log_info "Stopping HomeCore services..."

cd "$REPO_ROOT"
docker compose down || log_warn "Some services may not have been running"

log_success "Services stopped"

# -----------------------------------------------------------------------------
# Backup Current Data (safety)
# -----------------------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SAFETY_BACKUP="${DATA_ROOT}/.restore_backup_${TIMESTAMP}"

log_info "Creating safety backup of current data..."

mkdir -p "$SAFETY_BACKUP"

# Quick backup of critical directories
for dir in homeassistant/config mosquitto zigbee2mqtt/data nodered/data esphome/config mealie; do
    if [ -d "${DATA_ROOT}/${dir}" ]; then
        cp -a "${DATA_ROOT}/${dir}" "${SAFETY_BACKUP}/" 2>/dev/null || true
    fi
done

log_success "Safety backup created at: ${SAFETY_BACKUP}"

# -----------------------------------------------------------------------------
# Restore Data
# -----------------------------------------------------------------------------

log_info "Restoring data from backup..."

# Restore Home Assistant configuration
if [ -f "${BACKUP_PATH}/homeassistant_config.tar.gz" ]; then
    log_info "Restoring Home Assistant configuration..."
    tar -xzf "${BACKUP_PATH}/homeassistant_config.tar.gz" -C "${DATA_ROOT}/homeassistant"
    log_success "Home Assistant configuration restored"
fi

# Restore Mosquitto
if [ -f "${BACKUP_PATH}/mosquitto.tar.gz" ]; then
    log_info "Restoring Mosquitto..."
    tar -xzf "${BACKUP_PATH}/mosquitto.tar.gz" -C "${DATA_ROOT}"
    # Fix permissions
    sudo chown -R 1883:1883 "${DATA_ROOT}/mosquitto" 2>/dev/null || true
    log_success "Mosquitto restored"
fi

# Restore Zigbee2MQTT configuration
if [ -f "${BACKUP_PATH}/zigbee2mqtt_config.tar.gz" ]; then
    log_info "Restoring Zigbee2MQTT configuration..."
    tar -xzf "${BACKUP_PATH}/zigbee2mqtt_config.tar.gz" -C "${DATA_ROOT}/zigbee2mqtt"
    log_success "Zigbee2MQTT configuration restored"
fi

# Restore Node-RED flows
if [ -f "${BACKUP_PATH}/nodered_flows.tar.gz" ]; then
    log_info "Restoring Node-RED flows..."
    tar -xzf "${BACKUP_PATH}/nodered_flows.tar.gz" -C "${DATA_ROOT}/nodered"
    chown -R 1000:1000 "${DATA_ROOT}/nodered" 2>/dev/null || true
    log_success "Node-RED flows restored"
fi

# Restore ESPHome configurations
if [ -f "${BACKUP_PATH}/esphome_config.tar.gz" ]; then
    log_info "Restoring ESPHome configurations..."
    tar -xzf "${BACKUP_PATH}/esphome_config.tar.gz" -C "${DATA_ROOT}/esphome"
    log_success "ESPHome configurations restored"
fi

# Restore Mealie data
if [ -f "${BACKUP_PATH}/mealie_data.tar.gz" ]; then
    log_info "Restoring Mealie data..."
    tar -xzf "${BACKUP_PATH}/mealie_data.tar.gz" -C "${DATA_ROOT}/mealie"
    log_success "Mealie data restored"
fi

# Restore .env file (ask user first)
if [ -f "${BACKUP_PATH}/.env" ]; then
    echo ""
    read -p "Do you want to restore the .env configuration? (yes/no): " -r
    echo ""
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        cp "${BACKUP_PATH}/.env" "${REPO_ROOT}/.env"
        log_success ".env configuration restored"
    else
        log_info "Skipped .env restoration"
    fi
fi

# -----------------------------------------------------------------------------
# Restore Mealie Database
# -----------------------------------------------------------------------------

if [ -f "${BACKUP_PATH}/mealie_db.sql" ]; then
    echo ""
    echo -e "${YELLOW}Mealie database backup found.${NC}"
    echo "To restore the database:"
    echo "  1. Start the mealie-db container: docker compose --profile mealie up -d mealie-db"
    echo "  2. Wait for database to be ready (check with: docker compose ps)"
    echo "  3. Restore the database:"
    echo "     cat ${BACKUP_PATH}/mealie_db.sql | docker exec -i mealie-db psql -U ${POSTGRES_USER:-mealie} -d ${POSTGRES_DB:-mealie}"
    echo ""
    read -p "Do you want to restore the Mealie database now? (yes/no): " -r
    echo ""
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Starting Mealie database..."
        cd "$REPO_ROOT"
        docker compose --profile mealie up -d mealie-db
        
        log_info "Waiting for database to be ready..."
        sleep 10
        
        log_info "Restoring database..."
        cat "${BACKUP_PATH}/mealie_db.sql" | docker exec -i mealie-db psql -U "${POSTGRES_USER:-mealie}" -d "${POSTGRES_DB:-mealie}"
        log_success "Mealie database restored"
        
        docker compose --profile mealie down
    else
        log_info "Skipped Mealie database restoration"
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Restore Completed!                        ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Data has been restored from: ${BACKUP_PATH}"
echo "Safety backup of previous data: ${SAFETY_BACKUP}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Review restored configurations if needed"
echo "2. Start HomeCore services:"
echo "   ./scripts/orionctl up"
echo "   # Or for specific profiles:"
echo "   ./scripts/orionctl up homeauto"
echo ""
echo "3. Verify services are working correctly:"
echo "   ./scripts/orionctl ps"
echo "   ./scripts/orionctl doctor"
echo ""
echo -e "${YELLOW}If you encounter issues:${NC}"
echo "  - Check logs: ./scripts/orionctl logs <service>"
echo "  - Restore from safety backup: ${SAFETY_BACKUP}"
echo ""
