#!/bin/bash
# =============================================================================
# Bootstrap Script for Flight Intelligence
# =============================================================================
# Creates necessary directories, initializes environment, and prepares the system
#
# Usage: ./scripts/bootstrap.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Flight Intelligence Bootstrap ==="
echo "Project directory: $PROJECT_DIR"

# Create environment file if it doesn't exist
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "Creating .env file from .env.example..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    
    # Generate secure random passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)
    API_KEY=$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)
    JWT_SECRET=$(openssl rand -base64 32 | tr -d '=/+' | head -c 48)
    
    # Update .env with generated secrets
    sed -i "s/change_me_secure_password/$POSTGRES_PASSWORD/g" "$PROJECT_DIR/.env"
    sed -i "s/change_me_secure_api_key_for_trigger_endpoints/$API_KEY/g" "$PROJECT_DIR/.env"
    sed -i "s/change_me_random_jwt_secret_at_least_32_chars/$JWT_SECRET/g" "$PROJECT_DIR/.env"
    
    echo "✅ Environment file created with secure secrets"
    echo "⚠️  Please edit .env to configure your settings"
else
    echo "✅ Environment file already exists"
fi

# Create data directories
echo "Creating data directories..."
mkdir -p "$PROJECT_DIR/data/postgres"
mkdir -p "$PROJECT_DIR/data/backups"
mkdir -p "$PROJECT_DIR/logs"

echo "✅ Data directories created"

# Create Docker volumes
echo "Creating Docker volumes..."
docker volume create flight-postgres-data || true
docker volume create flight-prometheus-data || true
docker volume create flight-grafana-data || true

echo "✅ Docker volumes created"

# Create default search config
echo "Creating default search configuration..."
cat > "$PROJECT_DIR/data/default_search_config.sql" <<EOF
-- Default search configuration for Crete flights
INSERT INTO search_configs (name, origins, destinations, start_date, end_date, min_stay_days, max_stay_days, cabin, max_stops, currency, active)
VALUES (
    'NL-BE to Crete',
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

echo "✅ Default search configuration created"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "1. Edit .env to configure your settings (Amadeus API keys, etc.)"
echo "2. Start the services: docker compose --profile flight-intel up -d"
echo "3. View logs: docker compose --profile flight-intel logs -f"
echo "4. Access UI: http://localhost:8501"
echo "5. Access API docs: http://localhost:8000/docs"
echo ""
