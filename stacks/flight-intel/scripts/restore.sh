#!/bin/bash
# =============================================================================
# Restore Script for Flight Intelligence Database
# =============================================================================
# Restores the PostgreSQL database from a backup
#
# Usage: ./scripts/restore.sh <backup_file>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "Error: .env file not found"
    exit 1
fi

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file>"
    echo ""
    echo "Available backups:"
    ls -lh "$PROJECT_DIR/data/backups/"flight_intel_backup_*.sql.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE=$1

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "=== Flight Intelligence Restore ==="
echo "Backup file: $BACKUP_FILE"
echo ""
echo "⚠️  WARNING: This will DROP and recreate the database!"
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Restore cancelled"
    exit 0
fi

# Stop services to prevent connections
echo "Stopping services..."
docker compose --profile flight-intel stop flight-api flight-ui flight-collector

# Drop and recreate database
echo "Dropping and recreating database..."
docker exec flight-postgres psql -U "${POSTGRES_USER:-flightintel}" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB:-flightintel};"
docker exec flight-postgres psql -U "${POSTGRES_USER:-flightintel}" -c "CREATE DATABASE ${POSTGRES_DB:-flightintel};"

# Restore from backup
echo "Restoring from backup..."
gunzip < "$BACKUP_FILE" | docker exec -i flight-postgres psql -U "${POSTGRES_USER:-flightintel}" "${POSTGRES_DB:-flightintel}"

if [ $? -eq 0 ]; then
    echo "✅ Restore successful"
else
    echo "❌ Restore failed"
    exit 1
fi

# Restart services
echo "Restarting services..."
docker compose --profile flight-intel start flight-api flight-ui flight-collector

echo "=== Restore Complete ==="
