#!/bin/bash
# =============================================================================
# Backup Script for Flight Intelligence Database
# =============================================================================
# Creates a backup of the PostgreSQL database
#
# Usage: ./scripts/backup.sh

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

# Configuration
BACKUP_DIR="$PROJECT_DIR/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/flight_intel_backup_$TIMESTAMP.sql.gz"
RETENTION_DAYS=30

echo "=== Flight Intelligence Backup ==="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Perform backup
echo "Creating backup: $BACKUP_FILE"
docker exec flight-postgres pg_dump -U "${POSTGRES_USER:-flightintel}" "${POSTGRES_DB:-flightintel}" | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Backup successful: $BACKUP_FILE"
    
    # Calculate backup size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "Backup size: $BACKUP_SIZE"
else
    echo "❌ Backup failed"
    exit 1
fi

# Clean up old backups (keep last 30 days)
echo "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "flight_intel_backup_*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete

REMAINING_BACKUPS=$(find "$BACKUP_DIR" -name "flight_intel_backup_*.sql.gz" -type f | wc -l)
echo "Remaining backups: $REMAINING_BACKUPS"

echo "=== Backup Complete ==="
