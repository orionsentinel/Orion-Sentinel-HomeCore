#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Backup Script
# =============================================================================
# This script creates backups of critical HomeCore data.
# Backups are stored in ${BACKUP_DIR} (default: ${DATA_ROOT}/backups).
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="homecore_backup_${TIMESTAMP}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  HomeCore Backup Script                   ${NC}"
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
# Prerequisites
# -----------------------------------------------------------------------------

log_info "Checking prerequisites..."

# Check if DATA_ROOT exists
if [ ! -d "$DATA_ROOT" ]; then
    log_error "Data directory does not exist: ${DATA_ROOT}"
    exit 1
fi

# Create backup directory
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    log_success "Created backup directory: ${BACKUP_DIR}"
fi

# Check available disk space (require at least 1GB free)
available_space=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 1 ]; then
    log_error "Insufficient disk space. At least 1GB required, ${available_space}GB available."
    exit 1
fi

log_success "Prerequisites check passed"

# -----------------------------------------------------------------------------
# Create Backup
# -----------------------------------------------------------------------------

BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
mkdir -p "$BACKUP_PATH"

log_info "Creating backup at: ${BACKUP_PATH}"

# Backup Home Assistant configuration
if [ -d "${DATA_ROOT}/homeassistant/config" ]; then
    log_info "Backing up Home Assistant configuration..."
    tar -czf "${BACKUP_PATH}/homeassistant_config.tar.gz" \
        -C "${DATA_ROOT}/homeassistant" config
    log_success "Home Assistant configuration backed up"
fi

# Backup Mosquitto configuration and data
if [ -d "${DATA_ROOT}/mosquitto" ]; then
    log_info "Backing up Mosquitto..."
    tar -czf "${BACKUP_PATH}/mosquitto.tar.gz" \
        -C "${DATA_ROOT}" mosquitto/config mosquitto/data
    log_success "Mosquitto backed up"
fi

# Backup Zigbee2MQTT configuration
if [ -d "${DATA_ROOT}/zigbee2mqtt/data" ]; then
    log_info "Backing up Zigbee2MQTT configuration..."
    tar -czf "${BACKUP_PATH}/zigbee2mqtt_config.tar.gz" \
        -C "${DATA_ROOT}/zigbee2mqtt" data
    log_success "Zigbee2MQTT configuration backed up"
fi

# Backup Node-RED flows
if [ -d "${DATA_ROOT}/nodered/data" ]; then
    log_info "Backing up Node-RED flows..."
    tar -czf "${BACKUP_PATH}/nodered_flows.tar.gz" \
        -C "${DATA_ROOT}/nodered" data
    log_success "Node-RED flows backed up"
fi

# Backup ESPHome configurations
if [ -d "${DATA_ROOT}/esphome/config" ]; then
    log_info "Backing up ESPHome configurations..."
    tar -czf "${BACKUP_PATH}/esphome_config.tar.gz" \
        -C "${DATA_ROOT}/esphome" config
    log_success "ESPHome configurations backed up"
fi

# Backup Mealie (if running)
if docker ps --format '{{.Names}}' | grep -q "^mealie-db$"; then
    log_info "Backing up Mealie database..."
    
    # Create database dump
    docker exec mealie-db pg_dump -U "${POSTGRES_USER:-mealie}" "${POSTGRES_DB:-mealie}" \
        > "${BACKUP_PATH}/mealie_db.sql"
    
    # Backup Mealie data directory
    if [ -d "${DATA_ROOT}/mealie/data" ]; then
        tar -czf "${BACKUP_PATH}/mealie_data.tar.gz" \
            -C "${DATA_ROOT}/mealie" data
    fi
    
    log_success "Mealie backed up"
elif [ -d "${DATA_ROOT}/mealie" ]; then
    log_warn "Mealie database not running, backing up data directory only..."
    tar -czf "${BACKUP_PATH}/mealie_data.tar.gz" \
        -C "${DATA_ROOT}/mealie" data 2>/dev/null || true
fi

# Backup Immich database (if running). The photo library itself is too large
# for this archive - it needs its own off-device copy (see MEDIA.md).
if docker ps --format '{{.Names}}' | grep -q "^immich_postgres$"; then
    log_info "Backing up Immich database..."
    # pipefail so a failed dump aborts instead of leaving an empty .gz behind
    (
        set -o pipefail
        docker exec immich_postgres pg_dumpall --clean --if-exists \
            --username="${IMMICH_DB_USERNAME:-postgres}" | gzip > "${BACKUP_PATH}/immich_db.sql.gz"
    )
    log_success "Immich database backed up (library not included)"
fi

# Backup Jellyfin configuration (metadata images are re-downloadable)
if [ -d "${DATA_ROOT}/jellyfin/config" ]; then
    log_info "Backing up Jellyfin configuration..."
    tar -czf "${BACKUP_PATH}/jellyfin_config.tar.gz" \
        --exclude="config/metadata" \
        -C "${DATA_ROOT}/jellyfin" config
    log_success "Jellyfin configuration backed up"
fi

# Backup Navidrome database (users, playlists, play counts; cache is rebuildable)
if [ -d "${DATA_ROOT}/navidrome/data" ]; then
    log_info "Backing up Navidrome data..."
    tar -czf "${BACKUP_PATH}/navidrome_data.tar.gz" \
        --exclude="data/cache" \
        -C "${DATA_ROOT}/navidrome" data
    log_success "Navidrome data backed up"
fi

# Backup Audiobookshelf (database with listening progress, covers, its own backups)
if [ -d "${DATA_ROOT}/audiobookshelf/config" ]; then
    log_info "Backing up Audiobookshelf..."
    tar -czf "${BACKUP_PATH}/audiobookshelf.tar.gz" \
        --exclude="metadata/cache" --exclude="metadata/logs" \
        -C "${DATA_ROOT}/audiobookshelf" config metadata
    log_success "Audiobookshelf backed up"
fi

# Backup the *arr apps' config and databases (cover-art caches are rebuildable)
if [ -d "${DATA_ROOT}/arr" ]; then
    log_info "Backing up download automation config..."
    tar -czf "${BACKUP_PATH}/arr_config.tar.gz" \
        --exclude="*/MediaCover" --exclude="*/logs" --exclude="*/cache" \
        -C "${DATA_ROOT}" arr
    log_success "Download automation config backed up"
fi

# Backup .env file (contains configuration)
if [ -f "${REPO_ROOT}/.env" ]; then
    log_info "Backing up .env configuration..."
    cp "${REPO_ROOT}/.env" "${BACKUP_PATH}/.env"
    log_success ".env configuration backed up"
fi

# Create backup metadata
cat > "${BACKUP_PATH}/backup_info.txt" << EOF
Backup created: $(date)
Hostname: $(hostname)
HomeCore version: $(git -C "$REPO_ROOT" describe --tags --always 2>/dev/null || echo "unknown")
Data root: ${DATA_ROOT}
EOF

# -----------------------------------------------------------------------------
# Cleanup Old Backups
# -----------------------------------------------------------------------------

log_info "Cleaning up old backups (keeping last 7)..."

# Keep only the 7 most recent backups
cd "$BACKUP_DIR"
ls -dt homecore_backup_* 2>/dev/null | tail -n +8 | xargs rm -rf 2>/dev/null || true

log_success "Old backups cleaned up"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Backup Completed Successfully!           ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Backup location: ${BACKUP_PATH}"
echo "Backup size: ${BACKUP_SIZE}"
echo ""
echo -e "${YELLOW}What was backed up:${NC}"
echo "  - Home Assistant configuration"
echo "  - Mosquitto configuration and data"
echo "  - Zigbee2MQTT configuration"
echo "  - Node-RED flows"
echo "  - ESPHome configurations"
echo "  - Mealie database and data (if available)"
echo "  - Immich database (if running - NOT the photo library)"
echo "  - Jellyfin configuration (if present)"
echo "  - Navidrome and Audiobookshelf databases (if present)"
echo "  - Sonarr, Radarr, Prowlarr, Bazarr, Seerr, qBittorrent config (if present)"
echo "  - .env configuration file"
echo ""
echo -e "${YELLOW}To restore from this backup:${NC}"
echo "  ./scripts/restore.sh ${BACKUP_NAME}"
echo ""
echo -e "${YELLOW}To copy backup to another location:${NC}"
echo "  rsync -av ${BACKUP_PATH} /path/to/external/backup/"
echo ""
