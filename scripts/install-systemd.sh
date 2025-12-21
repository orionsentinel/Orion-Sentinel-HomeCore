#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore systemd Installation Script
# =============================================================================
# Installs and enables the HomeCore systemd service for automatic startup.
# This script is idempotent and can be run multiple times safely.
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

show_docker_group_help() {
    echo "  sudo usermod -aG docker \$USER"
    if [ -n "${1:-}" ]; then
        echo "$1"
    fi
}

# -----------------------------------------------------------------------------
# Determine repository root (absolute path)
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)"

log_info "Repository root: ${REPO_ROOT}"

# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------

echo ""
log_info "Validating prerequisites..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    echo ""
    echo "Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    show_docker_group_help
    echo ""
    exit 1
fi

log_success "Docker is installed"

# Check if Docker Compose v2 is available
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose v2 is not available"
    echo ""
    echo "Please install Docker Compose v2:"
    echo "  https://docs.docker.com/compose/install/"
    echo ""
    exit 1
fi

log_success "Docker Compose v2 is available"

# Check if user can run Docker (or is root)
if [ "$EUID" -ne 0 ] && ! docker ps &> /dev/null; then
    log_warn "Current user cannot run Docker without sudo"
    echo ""
    echo "Please add your user to the docker group:"
    show_docker_group_help "  # Then log out and log back in"
    echo ""
    echo "Or run this script with sudo (not recommended for service installation)."
    echo ""
fi

# Check if .env exists
if [ ! -f "${REPO_ROOT}/.env" ]; then
    log_error ".env file not found in ${REPO_ROOT}"
    echo ""
    echo "Please create .env file first:"
    echo "  cd ${REPO_ROOT}"
    echo "  cp env/.env.example .env"
    echo "  nano .env"
    echo ""
    echo "Or run the bootstrap script:"
    echo "  cd ${REPO_ROOT}"
    echo "  ./scripts/bootstrap-homecore.sh"
    echo ""
    exit 1
fi

log_success ".env file exists"

# Check if orionctl exists and is executable
if [ ! -f "${REPO_ROOT}/scripts/orionctl" ]; then
    log_error "orionctl script not found"
    exit 1
fi

if [ ! -x "${REPO_ROOT}/scripts/orionctl" ]; then
    log_warn "orionctl is not executable, fixing..."
    chmod +x "${REPO_ROOT}/scripts/orionctl"
fi

log_success "orionctl script is ready"

# -----------------------------------------------------------------------------
# Select and prepare systemd unit file
# -----------------------------------------------------------------------------

echo ""
log_info "Preparing systemd unit file..."

UNIT_FILE="homecore.service"
SOURCE_UNIT="${REPO_ROOT}/systemd/${UNIT_FILE}"
TARGET_UNIT="/etc/systemd/system/${UNIT_FILE}"

if [ ! -f "$SOURCE_UNIT" ]; then
    log_error "Unit file not found: ${SOURCE_UNIT}"
    exit 1
fi

# Create a temporary file with substituted paths
TEMP_UNIT=$(mktemp)
sed "s|__REPO_DIR__|${REPO_ROOT}|g" "$SOURCE_UNIT" > "$TEMP_UNIT"

log_info "Created unit file with repository path: ${REPO_ROOT}"

# -----------------------------------------------------------------------------
# Install systemd unit file
# -----------------------------------------------------------------------------

echo ""
log_info "Installing systemd unit file..."

# Check if we need sudo
if [ -w "/etc/systemd/system" ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
    log_info "Installing with sudo (requires root privileges)..."
fi

# Install the unit file
if $SUDO_CMD cp "$TEMP_UNIT" "$TARGET_UNIT"; then
    log_success "Unit file installed to ${TARGET_UNIT}"
else
    log_error "Failed to install unit file"
    rm -f "$TEMP_UNIT"
    exit 1
fi

# Clean up temporary file
rm -f "$TEMP_UNIT"

# Set proper permissions
$SUDO_CMD chmod 644 "$TARGET_UNIT"

# -----------------------------------------------------------------------------
# Enable and start the service
# -----------------------------------------------------------------------------

echo ""
log_info "Enabling and starting systemd service..."

# Reload systemd daemon
if $SUDO_CMD systemctl daemon-reload; then
    log_success "systemd daemon reloaded"
else
    log_error "Failed to reload systemd daemon"
    exit 1
fi

# Enable the service
if $SUDO_CMD systemctl enable "$UNIT_FILE"; then
    log_success "Service enabled (will start on boot)"
else
    log_error "Failed to enable service"
    exit 1
fi

# Start the service
if $SUDO_CMD systemctl start "$UNIT_FILE"; then
    log_success "Service started"
else
    log_error "Failed to start service"
    echo ""
    echo "Check the service status:"
    echo "  sudo systemctl status ${UNIT_FILE}"
    echo "  sudo journalctl -u ${UNIT_FILE} -e --no-pager"
    exit 1
fi

# -----------------------------------------------------------------------------
# Display status and helpful information
# -----------------------------------------------------------------------------

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Installation Complete!                   ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

echo "HomeCore systemd service has been installed and started."
echo ""
echo "Service name: ${UNIT_FILE}"
echo "Unit file: ${TARGET_UNIT}"
echo "Repository: ${REPO_ROOT}"
echo ""

echo -e "${CYAN}Useful Commands:${NC}"
echo ""
echo "Check service status:"
echo "  sudo systemctl status ${UNIT_FILE} --no-pager"
echo ""
echo "View logs:"
echo "  sudo journalctl -u ${UNIT_FILE} -f"
echo "  sudo journalctl -u ${UNIT_FILE} -e --no-pager"
echo ""
echo "Restart service:"
echo "  sudo systemctl restart ${UNIT_FILE}"
echo ""
echo "Stop service:"
echo "  sudo systemctl stop ${UNIT_FILE}"
echo ""
echo "Disable service (prevent auto-start on boot):"
echo "  sudo systemctl disable ${UNIT_FILE}"
echo ""

# Show current status
echo -e "${CYAN}Current Status:${NC}"
echo ""
$SUDO_CMD systemctl status "$UNIT_FILE" --no-pager || true
echo ""

log_success "HomeCore will now start automatically on system boot!"
