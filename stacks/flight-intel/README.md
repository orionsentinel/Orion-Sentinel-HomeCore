# Flight Intelligence Homelab

**Production-ready flight price intelligence system for monitoring flights from NL/BE to Crete**

A complete, Docker-based flight price tracking and recommendation system designed for homelab deployment. Continuously collects flight prices, stores historical data, provides web UI and API, generates buy/wait recommendations, and optionally includes an LLM-powered assistant.

## Features

- 🛫 **Multi-Provider Support**: Mock provider (always works) + Amadeus API adapter with automatic fallback
- 📊 **Web Dashboard**: Interactive Streamlit UI with price heatmaps, history charts, and recommendations
- 🔌 **REST API**: FastAPI-based API with OpenAPI documentation
- 📈 **Smart Recommendations**: Rules-based engine analyzing price history, trends, and volatility
- 🤖 **LLM Assistant**: Optional AI-powered flight assistant using local Ollama
- 📉 **Observability**: Prometheus metrics + Grafana dashboards
- 🔔 **Notifications**: Support for ntfy, Telegram, and email alerts
- 🔒 **Security First**: Non-root containers, secrets via env vars, localhost-only by default
- 💾 **Automated Backups**: Built-in backup/restore scripts with retention
- 🚀 **Production Ready**: Healthchecks, retries, structured logging, database migrations

## Quick Start

```bash
# 1. Clone and navigate
cd stacks/flight-intel

# 2. Bootstrap (creates .env with secure secrets)
./scripts/bootstrap.sh

# 3. Configure (optional: add Amadeus API credentials)
nano .env

# 4. Start core services
docker compose --profile flight-intel up -d

# 5. Seed with sample data
./scripts/seed_mock_data.sh
```

**Access Points**:
- 🌐 Web UI: http://localhost:8501
- 📚 API Docs: http://localhost:8000/docs
- 📊 Metrics: http://localhost:8000/metrics

## Service Profiles

Start different combinations of services using profiles:

```bash
# Core only (API + UI + Collector + Database)
docker compose --profile flight-intel up -d

# With LLM agent (adds Ollama)
docker compose --profile flight-intel --profile llm up -d

# With observability (adds Prometheus + Grafana)
docker compose --profile flight-intel --profile observability up -d

# With alerts (adds ntfy)
docker compose --profile flight-intel --profile alerts up -d

# Everything
docker compose --profile flight-intel --profile llm --profile observability --profile alerts up -d
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flight Intelligence                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐           │
│  │ Streamlit│  │ FastAPI  │  │ Collector  │           │
│  │    UI    │  │   API    │  │  (Cron)    │           │
│  │  :8501   │  │  :8000   │  │            │           │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘           │
│       │             │              │                    │
│       └─────────────┼──────────────┘                    │
│                     │                                    │
│            ┌────────┴────────┐                          │
│            │   PostgreSQL    │                          │
│            │     :5432       │                          │
│            └─────────────────┘                          │
│                                                          │
│  Optional:                                              │
│  ┌──────────┐  ┌────────────┐  ┌──────────┐           │
│  │ Ollama   │  │Prometheus  │  │  ntfy    │           │
│  │  (LLM)   │  │ + Grafana  │  │ (Alerts) │           │
│  └──────────┘  └────────────┘  └──────────┘           │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Configuration

### Environment Variables

Key configuration in `.env`:

```bash
# Provider selection (mock or amadeus)
DEFAULT_PROVIDER=mock

# Amadeus API (optional - falls back to mock if not set)
AMADEUS_API_KEY=your_api_key
AMADEUS_API_SECRET=your_api_secret

# Search parameters
DEFAULT_ORIGINS=AMS,EIN,RTM,BRU
DEFAULT_DESTINATIONS=HER,CHQ
MIN_STAY_DAYS=7
MAX_STAY_DAYS=21

# Collection schedule (cron format)
COLLECTOR_SCHEDULE=0 3 * * *  # Daily at 3:00 AM

# LLM Agent (optional)
AGENT_ENABLED=false
OLLAMA_MODEL=llama2

# Security
HOST_IP=127.0.0.1  # localhost-only (change for LAN access)
API_KEY=your_secure_api_key
```

See `.env.example` for full configuration options.

### Using Amadeus API

1. Sign up at https://developers.amadeus.com
2. Create an application to get API credentials
3. Add credentials to `.env`:
   ```bash
   DEFAULT_PROVIDER=amadeus
   AMADEUS_API_KEY=your_key
   AMADEUS_API_SECRET=your_secret
   ```
4. Restart services: `docker compose --profile flight-intel restart`

If credentials are invalid or not set, system automatically falls back to MockProvider.

## Usage

### Web UI

Navigate to http://localhost:8501

**Features**:
- **Best Offers Tab**: View price heatmap and table of cheapest flights
- **Price History Tab**: Chart historical prices for specific routes
- **Recommendations Tab**: Get buy/wait recommendation with rationale
- **AI Assistant Tab**: Ask questions in natural language (if LLM enabled)

### API

Access API documentation at http://localhost:8000/docs

**Key Endpoints**:
- `GET /health` - Health check
- `GET /offers/best` - Query best offers with filters
- `GET /history` - Get price history for a route
- `GET /recommendation` - Get buy/wait recommendation
- `POST /collect/trigger` - Manually trigger collection (requires API key)
- `POST /agent/query` - Query LLM assistant
- `GET /metrics` - Prometheus metrics

**Example**:
```bash
# Get best offers
curl "http://localhost:8000/offers/best?origins=AMS,EIN&destinations=HER&limit=10"

# Get recommendation
curl "http://localhost:8000/recommendation?origin=AMS&destination=HER&depart_date=2024-06-15&return_date=2024-06-22"

# Trigger collection (requires API key)
curl -X POST "http://localhost:8000/collect/trigger" \
  -H "X-API-Key: your_api_key"
```

## Operations

### Backup

```bash
# Manual backup
./scripts/backup.sh

# Backups are stored in: data/backups/
# Retention: 30 days (configurable in script)
```

### Restore

```bash
# List available backups
ls -lh data/backups/

# Restore from backup
./scripts/restore.sh data/backups/flight_intel_backup_20240111_120000.sql.gz
```

### Logs

```bash
# View all logs
docker compose --profile flight-intel logs -f

# Specific service
docker compose logs -f flight-api
docker compose logs -f flight-collector
```

### Health Checks

```bash
# Check service status
docker compose --profile flight-intel ps

# API health
curl http://localhost:8000/health

# Database connection test
docker exec flight-postgres pg_isready -U flightintel
```

### Updating

```bash
# Pull latest images
docker compose --profile flight-intel pull

# Rebuild and restart
docker compose --profile flight-intel up -d --build

# Run migrations (if schema changed)
docker exec flight-api alembic upgrade head
```

## Observability

### Prometheus + Grafana

Start with observability profile:
```bash
docker compose --profile flight-intel --profile observability up -d
```

Access:
- **Prometheus**: http://localhost:9091
- **Grafana**: http://localhost:3000 (admin/admin)

Pre-configured dashboard shows:
- Snapshot collection rates
- Collection run success/failure
- Recommendation distribution (BUY/WAIT/HOLD)
- API request latency (p95)
- API request rates by endpoint

### Metrics

View raw metrics: http://localhost:8000/metrics

Key metrics:
- `flight_snapshots_collected_total` - Snapshots collected by provider/route
- `flight_collection_runs_total` - Collection runs by status
- `flight_recommendations_generated_total` - Recommendations by action
- `flight_api_requests_total` - API requests by endpoint/status
- `flight_api_request_duration_seconds` - API request latency histogram

## Troubleshooting

### Collection not running

```bash
# Check collector logs
docker compose logs flight-collector

# Verify collector is enabled
grep COLLECTOR_ENABLED .env

# Manually trigger collection
curl -X POST "http://localhost:8000/collect/trigger" \
  -H "X-API-Key: $(grep API_KEY .env | cut -d= -f2)"
```

### No flight data

- System uses **MockProvider** by default (generates synthetic data)
- Check collector logs: `docker compose logs flight-collector`
- Verify search configs exist: Check database or seed with `./scripts/seed_mock_data.sh`

### Database connection errors

```bash
# Check database is running
docker compose ps flight-postgres

# Check database health
docker exec flight-postgres pg_isready -U flightintel

# Restart database
docker compose restart flight-postgres
```

### UI not loading

```bash
# Check UI logs
docker compose logs flight-ui

# Verify API is accessible from UI
docker exec flight-ui curl -f http://flight-api:8000/health
```

See `docs/TROUBLESHOOTING.md` for more solutions.

## Development

### Running Tests

```bash
# Install dev dependencies
uv pip install -e ".[dev]"

# Run all tests
pytest

# Run with coverage
pytest --cov=app --cov-report=html

# Run specific test file
pytest tests/unit/test_providers.py
```

### Code Quality

```bash
# Install pre-commit hooks
pre-commit install

# Run linting
ruff check app/
ruff format app/

# Run type checking
mypy app/
```

### Local Development

```bash
# Start just the database
docker compose up -d flight-postgres

# Set database URL
export DATABASE_URL=postgresql://flightintel:flightintel@localhost:5432/flightintel

# Run migrations
alembic upgrade head

# Start API locally
uvicorn app.api.main:app --reload

# Start UI locally (in another terminal)
streamlit run ui/app.py
```

## System Requirements

- **OS**: Ubuntu 22.04+ (or any Linux with Docker)
- **Docker**: 24.0+
- **Docker Compose**: v2.0+
- **RAM**: 2GB minimum (4GB recommended with all profiles)
- **Storage**: 10GB minimum (for database and backups)

## Security

- **Localhost-only by default**: Services bind to `127.0.0.1`
- **Non-root containers**: All services run as unprivileged users
- **Secrets via environment**: No hardcoded credentials
- **API key protection**: Sensitive endpoints require authentication
- **Database passwords**: Auto-generated on bootstrap

For LAN access, change `HOST_IP=127.0.0.1` to your machine's IP in `.env`.

See `docs/SECURITY.md` for detailed security practices.

## Documentation

- `docs/RUNBOOK.md` - Operational runbook
- `docs/DATA_MODEL.md` - Database schema documentation
- `docs/PROVIDERS.md` - Flight provider details
- `docs/SECURITY.md` - Security best practices
- `docs/OBSERVABILITY.md` - Monitoring and metrics guide

## License

MIT License - see LICENSE file for details.

## Support

For issues, feature requests, or questions:
- Check documentation in `docs/`
- Review existing issues
- Create a new issue with details

---

**Built for homelabs, optimized for reliability.** ✈️
