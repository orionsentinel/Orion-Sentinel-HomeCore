#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore systemd Uninstallation Script
# =============================================================================
# Removes the HomeCore systemd service.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
# Uninstall systemd service
# -----------------------------------------------------------------------------

UNIT_FILE="homecore.service"
TARGET_UNIT="/etc/systemd/system/${UNIT_FILE}"

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Uninstalling HomeCore systemd service    ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Check if we need sudo
if [ -w "/etc/systemd/system" ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# Check if unit file exists
if [ ! -f "$TARGET_UNIT" ]; then
    log_warn "Unit file not found: ${TARGET_UNIT}"
    log_info "Service may not be installed"
    exit 0
fi

# Stop the service
log_info "Stopping service..."
if $SUDO_CMD systemctl stop "$UNIT_FILE" 2>/dev/null; then
    log_success "Service stopped"
else
    log_warn "Service was not running or already stopped"
fi

# Disable the service
log_info "Disabling service..."
if $SUDO_CMD systemctl disable "$UNIT_FILE" 2>/dev/null; then
    log_success "Service disabled"
else
    log_warn "Service was not enabled"
fi

# Remove the unit file
log_info "Removing unit file..."
if $SUDO_CMD rm -f "$TARGET_UNIT"; then
    log_success "Unit file removed: ${TARGET_UNIT}"
else
    log_error "Failed to remove unit file"
    exit 1
fi

# Reload systemd daemon
log_info "Reloading systemd daemon..."
if $SUDO_CMD systemctl daemon-reload; then
    log_success "systemd daemon reloaded"
else
    log_error "Failed to reload systemd daemon"
    exit 1
fi

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Uninstallation Complete!                 ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

log_success "HomeCore systemd service has been removed"
echo ""
echo "The service will no longer start automatically on boot."
echo ""
echo "To manage HomeCore manually, use:"
echo "  ./scripts/orionctl up"
echo "  ./scripts/orionctl down"
echo ""
