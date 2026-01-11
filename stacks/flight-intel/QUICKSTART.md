# Flight Intelligence - Quick Start Guide

Get up and running with Flight Intelligence in 5 minutes!

## Prerequisites

- Ubuntu 22.04+ (or any Linux with Docker)
- Docker 24.0+ installed
- Docker Compose v2+ installed
- 2GB free RAM
- 5GB free disk space

## Step 1: Navigate to Flight Intel

```bash
cd Orion-Sentinel-HomeCore/stacks/flight-intel
```

## Step 2: Bootstrap

Run the bootstrap script to create environment file with secure secrets:

```bash
./scripts/bootstrap.sh
```

This will:
- Create `.env` with generated secure passwords
- Create data directories
- Create Docker volumes
- Generate default search configuration

## Step 3: Configure (Optional)

Edit `.env` to customize settings:

```bash
nano .env
```

**Key settings to review**:
- `HOST_IP=127.0.0.1` - Change to your machine's IP for LAN access
- `DEFAULT_PROVIDER=mock` - Keep as mock for testing (works without API keys)
- `AMADEUS_API_KEY` / `AMADEUS_API_SECRET` - Add if you have Amadeus credentials

**For testing**, the defaults work perfectly with MockProvider!

## Step 4: Start Services

```bash
# Core services only
docker compose --profile flight-intel up -d

# Or with all features (recommended for first try)
docker compose --profile flight-intel --profile observability up -d
```

Wait for services to start (about 30 seconds):

```bash
# Watch services come up
docker compose --profile flight-intel ps

# Watch logs
docker compose --profile flight-intel logs -f
```

## Step 5: Seed Mock Data

```bash
./scripts/seed_mock_data.sh
```

This creates:
- 8 flight routes (AMS, EIN, RTM, BRU → HER, CHQ)
- 1 active search configuration
- Initial price snapshots (via collector)

## Step 6: Access the System

Open in your browser:

- **Web UI**: http://localhost:8501
- **API Docs**: http://localhost:8000/docs
- **Grafana**: http://localhost:3000 (if observability profile enabled)
  - Username: `admin`
  - Password: `admin`

## Step 7: Explore the UI

### Best Offers Tab
1. Select origin airports (e.g., AMS, EIN)
2. Select destinations (HER, CHQ)
3. Choose date range and stay duration
4. Click "Refresh Offers"
5. View price heatmap and table

### Price History Tab
1. Select a specific route
2. Choose departure and return dates
3. Click "Get Price History"
4. View price trend chart

### Recommendations Tab
1. Select route and dates
2. Click "Get Recommendation"
3. View BUY/WAIT/HOLD recommendation with analysis

### AI Assistant Tab (if LLM enabled)
1. Ask questions like:
   - "Find me the cheapest week in June from Amsterdam to Crete"
   - "Should I buy now or wait?"

## Verification Checklist

✅ **API Health Check**:
```bash
curl http://localhost:8000/health
# Expected: {"status": "healthy", ...}
```

✅ **Database Check**:
```bash
docker exec flight-postgres pg_isready -U flightintel
# Expected: flightintel:5432 - accepting connections
```

✅ **Recent Data Check**:
```bash
curl "http://localhost:8000/offers/best?limit=5"
# Expected: JSON with flight offers
```

✅ **UI Access**:
- Open http://localhost:8501
- Should see Flight Intelligence dashboard

## Common First-Time Issues

### UI shows "Connection error"

**Solution**: API might still be starting. Wait 30 seconds and refresh.

```bash
# Check API logs
docker compose logs flight-api

# Verify API is healthy
curl http://localhost:8000/health
```

### No flight data shown

**Solution**: Trigger collector manually:

```bash
API_KEY=$(grep API_KEY .env | cut -d= -f2)
curl -X POST "http://localhost:8000/collect/trigger" \
  -H "X-API-Key: $API_KEY"
```

### Port already in use

**Solution**: Change ports in `.env`:

```bash
# Example: Change UI port
echo "UI_PORT=8502" >> .env
docker compose --profile flight-intel up -d
```

## Next Steps

### 1. Set Up Collection Schedule

The collector runs daily at 3:30 AM by default. To change:

```bash
# Edit .env
COLLECTOR_SCHEDULE=0 6 * * *  # Daily at 6:00 AM

# Restart collector
docker compose restart flight-collector
```

### 2. Add Real Flight Data (Amadeus)

1. Sign up at https://developers.amadeus.com
2. Create an application
3. Add credentials to `.env`:
   ```bash
   DEFAULT_PROVIDER=amadeus
   AMADEUS_API_KEY=your_key
   AMADEUS_API_SECRET=your_secret
   ```
4. Restart services:
   ```bash
   docker compose --profile flight-intel restart
   ```

### 3. Enable LLM Assistant

```bash
# Add to .env
AGENT_ENABLED=true

# Start with LLM profile
docker compose --profile flight-intel --profile llm up -d

# Pull Llama model (inside container)
docker exec flight-ollama ollama pull llama2
```

### 4. Set Up Systemd (Auto-start on Boot)

```bash
# Copy service file
sudo cp systemd/flight-intel.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable flight-intel
sudo systemctl start flight-intel

# Check status
sudo systemctl status flight-intel
```

### 5. Set Up Automated Backups

```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * /path/to/stacks/flight-intel/scripts/backup.sh >> /var/log/flight-intel-backup.log 2>&1
```

### 6. Configure Alerts (Optional)

```bash
# Start with alerts profile
docker compose --profile flight-intel --profile alerts up -d

# Subscribe to notifications (ntfy)
# On your phone: Install ntfy app and subscribe to topic
NTFY_URL=http://your-server:8080
NTFY_TOPIC=flight-intel-alerts

# Update .env
ALERTS_ENABLED=true
NTFY_URL=http://localhost:8080
NTFY_TOPIC=flight-intel-alerts
```

## Useful Commands

```bash
# View all services
docker compose --profile flight-intel ps

# View logs
docker compose --profile flight-intel logs -f

# Restart specific service
docker compose restart flight-api

# Stop all services
docker compose --profile flight-intel down

# View metrics
curl http://localhost:8000/metrics

# Backup database
./scripts/backup.sh

# Access database
docker exec -it flight-postgres psql -U flightintel flightintel
```

## Learning Resources

- **README.md** - Full documentation
- **docs/RUNBOOK.md** - Operations guide
- **docs/DATA_MODEL.md** - Database schema
- **docs/PROVIDERS.md** - Flight provider details
- **API Docs** - http://localhost:8000/docs (interactive)

## Getting Help

1. Check logs: `docker compose logs`
2. Review `docs/RUNBOOK.md` troubleshooting section
3. Check GitHub issues
4. Create new issue with logs

## Success!

You now have a working flight price intelligence system! 🎉

The system will:
- ✅ Collect flight prices daily
- ✅ Store price history
- ✅ Generate recommendations
- ✅ Provide web UI and API
- ✅ Monitor via Prometheus/Grafana

Happy flight hunting! ✈️
