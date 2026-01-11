#!/bin/bash
# =============================================================================
# Seed Mock Data Script
# =============================================================================
# Seeds the database with mock search configurations and sample data
#
# Usage: ./scripts/seed_mock_data.sh

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

echo "=== Seeding Mock Data ==="

# Create SQL script
cat > /tmp/seed_data.sql <<EOF
-- Insert default routes
INSERT INTO routes (origin_airport, dest_airport, active)
VALUES 
    ('AMS', 'HER', true),
    ('AMS', 'CHQ', true),
    ('EIN', 'HER', true),
    ('EIN', 'CHQ', true),
    ('RTM', 'HER', true),
    ('RTM', 'CHQ', true),
    ('BRU', 'HER', true),
    ('BRU', 'CHQ', true)
ON CONFLICT (origin_airport, dest_airport) DO NOTHING;

-- Insert default search configuration
INSERT INTO search_configs (name, origins, destinations, start_date, end_date, min_stay_days, max_stay_days, cabin, max_stops, currency, active)
VALUES (
    'NL-BE to Crete - Summer 2024',
    ARRAY['AMS', 'EIN', 'RTM', 'BRU'],
    ARRAY['HER', 'CHQ'],
    (CURRENT_DATE + INTERVAL '7 days')::text,
    (CURRENT_DATE + INTERVAL '180 days')::text,
    7,
    21,
    'ECONOMY',
    2,
    'EUR',
    true
)
ON CONFLICT (name) DO NOTHING;
EOF

# Execute SQL
docker exec -i flight-postgres psql -U "${POSTGRES_USER:-flightintel}" "${POSTGRES_DB:-flightintel}" < /tmp/seed_data.sql

echo "✅ Mock data seeded successfully"

# Trigger a collection to populate price data
echo "Triggering collector to generate sample price data..."
API_KEY="${API_KEY:-dev_api_key}"
curl -X POST "http://localhost:8000/collect/trigger" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" || echo "Note: API may not be ready yet"

echo ""
echo "=== Seeding Complete ==="
echo "The system is now populated with:"
echo "- 8 flight routes (4 origins × 2 destinations)"
echo "- 1 active search configuration"
echo "- Sample price data (if collector ran successfully)"
echo ""
