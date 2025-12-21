#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Secret Generation Script
# =============================================================================
# This script generates secure random secrets for use in HomeCore services.
# Secrets are stored in ${DATA_ROOT}/secrets/ or ./secrets/ (gitignored).
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

# Default secrets directory
DATA_ROOT="${DATA_ROOT:-/srv/orion/homecore}"
SECRETS_DIR="${DATA_ROOT}/secrets"

# Fallback to repo secrets if DATA_ROOT is not accessible
if [ ! -w "$(dirname "$DATA_ROOT")" ] 2>/dev/null; then
    SECRETS_DIR="${REPO_ROOT}/secrets"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Secret Generation for HomeCore          ${NC}"
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

# Generate a secure random secret
generate_secret() {
    local length="${1:-32}"
    if command -v openssl &> /dev/null; then
        openssl rand -base64 48 | tr -d '\n/+=' | head -c "$length"
    else
        # Fallback using /dev/urandom
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    fi
}

# Generate a secure password (alphanumeric + special chars)
generate_password() {
    local length="${1:-32}"
    if command -v openssl &> /dev/null; then
        openssl rand -base64 48 | head -c "$length"
    else
        tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
    fi
}

# -----------------------------------------------------------------------------
# Create Secrets Directory
# -----------------------------------------------------------------------------

log_info "Creating secrets directory: ${SECRETS_DIR}"

if [ ! -d "$SECRETS_DIR" ]; then
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    log_success "Created secrets directory"
else
    log_info "Secrets directory already exists"
fi

# -----------------------------------------------------------------------------
# Generate Secrets
# -----------------------------------------------------------------------------

log_info "Generating secrets..."

# Mealie PostgreSQL password
POSTGRES_PASSWORD_FILE="${SECRETS_DIR}/mealie_postgres_password"
if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
    generate_password 32 > "$POSTGRES_PASSWORD_FILE"
    chmod 600 "$POSTGRES_PASSWORD_FILE"
    log_success "Generated Mealie PostgreSQL password"
else
    log_info "Mealie PostgreSQL password already exists"
fi

# Mealie secret key
MEALIE_SECRET_FILE="${SECRETS_DIR}/mealie_secret_key"
if [ ! -f "$MEALIE_SECRET_FILE" ]; then
    generate_secret 32 > "$MEALIE_SECRET_FILE"
    chmod 600 "$MEALIE_SECRET_FILE"
    log_success "Generated Mealie secret key"
else
    log_info "Mealie secret key already exists"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Secrets Generated Successfully!          ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Secrets are stored in: ${SECRETS_DIR}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Update your .env file with the generated secrets:"
echo "   sudo nano ${REPO_ROOT}/.env"
echo ""
echo "2. Set the following values:"
echo "   POSTGRES_PASSWORD=\$(cat ${POSTGRES_PASSWORD_FILE})"
echo "   MEALIE_SECRET_KEY=\$(cat ${MEALIE_SECRET_FILE})"
echo ""
echo "3. Or use the following commands to auto-update .env:"
echo "   sed -i \"s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\$(cat ${POSTGRES_PASSWORD_FILE})|\" ${REPO_ROOT}/.env"
echo "   sed -i \"s|^MEALIE_SECRET_KEY=.*|MEALIE_SECRET_KEY=\$(cat ${MEALIE_SECRET_FILE})|\" ${REPO_ROOT}/.env"
echo ""
echo -e "${RED}IMPORTANT:${NC} Keep these secrets secure and do not commit them to version control!"
echo ""
