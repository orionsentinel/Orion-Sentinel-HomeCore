# Flight Intelligence Observability

## Overview

Flight Intelligence includes comprehensive observability features for monitoring system health, performance, and data collection progress.

## Monitoring Stack

### Components

1. **Prometheus** - Metrics collection and storage
2. **Grafana** - Metrics visualization and dashboards
3. **Application Metrics** - Custom metrics from API and collector
4. **Structured Logging** - JSON-formatted logs with context

### Architecture

```
┌─────────────┐     scrape      ┌─────────────┐
│   Flight    │ ───────────────> │ Prometheus  │
│     API     │   /metrics       │    :9090    │
└─────────────┘                  └──────┬──────┘
                                        │
┌─────────────┐                         │ query
│  Collector  │                         │
│   (logs)    │                         v
└─────────────┘                  ┌─────────────┐
                                 │   Grafana   │
┌─────────────┐                  │    :3000    │
│    Logs     │                  └─────────────┘
│   (JSON)    │
└─────────────┘
```

## Getting Started

### Enable Observability

```bash
# Start with observability profile
docker compose --profile flight-intel --profile observability up -d
```

### Access Interfaces

- **Prometheus**: http://localhost:9091
- **Grafana**: http://localhost:3000
  - Username: `admin`
  - Password: `admin` (change on first login)
- **Metrics Endpoint**: http://localhost:8000/metrics

## Prometheus

### Configuration

Prometheus is configured to scrape:
- Flight API every 30 seconds
- Self-monitoring every 15 seconds

**Config**: `prometheus.yml`

```yaml
scrape_configs:
  - job_name: 'flight-api'
    static_configs:
      - targets: ['flight-api:8000']
    metrics_path: '/metrics'
    scrape_interval: 30s
```

### Useful Queries

#### Collection Rate
```promql
# Snapshots collected per minute
rate(flight_snapshots_collected_total[5m])

# By provider
rate(flight_snapshots_collected_total{provider="mock"}[5m])
```

#### API Performance
```promql
# Request rate
rate(flight_api_requests_total[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(flight_api_request_duration_seconds_bucket[5m]))

# Error rate
rate(flight_api_requests_total{status=~"5.."}[5m])
```

#### Recommendations
```promql
# Total recommendations by action
flight_recommendations_generated_total

# BUY vs WAIT ratio
flight_recommendations_generated_total{action="BUY"} / 
flight_recommendations_generated_total{action="WAIT"}
```

### Accessing Prometheus UI

1. Navigate to http://localhost:9091
2. Go to "Graph" tab
3. Enter PromQL query
4. Click "Execute"
5. View graph or table

**Example**: View collection runs
```promql
flight_collection_runs_total
```

## Grafana

### Initial Setup

1. **Login**:
   - URL: http://localhost:3000
   - Username: `admin`
   - Password: `admin`
   - Change password when prompted

2. **Verify Data Source**:
   - Go to Configuration → Data Sources
   - Should see "Prometheus" as default
   - Click "Test" to verify connection

3. **Load Dashboard**:
   - Go to Dashboards → Browse
   - Should see "Flight Intelligence Dashboard"
   - Click to open

### Pre-Built Dashboard

The included dashboard shows:

#### Panel 1: Snapshots Collection Rate
- Line chart showing rate of snapshot collection
- Grouped by provider, origin, destination
- 5-minute rate calculation

#### Panel 2: Collection Runs
- Gauge showing total collection runs
- Color-coded by status (success/error)

#### Panel 3: Recommendations by Action
- Pie chart of BUY/WAIT/HOLD distribution
- Shows recommendation patterns

#### Panel 4: API Request Duration (p95)
- Time series of 95th percentile latency
- Grouped by method and endpoint
- Helps identify slow endpoints

#### Panel 5: API Request Rate
- Request throughput by endpoint
- Status code breakdown
- Identifies high-traffic endpoints

### Custom Dashboards

Create your own dashboard:

1. Click "+" → "Dashboard"
2. Add Panel
3. Select Prometheus data source
4. Enter query
5. Choose visualization
6. Save dashboard

**Example Panel** - Price Trend:
```promql
# Average price over time
avg(flight_daily_best_price) by (origin, destination)
```

## Application Metrics

### Available Metrics

#### Collection Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `flight_snapshots_collected_total` | Counter | Total snapshots collected (labels: provider, origin, destination) |
| `flight_collection_runs_total` | Counter | Total collection runs (labels: status) |
| `flight_collection_duration_seconds` | Histogram | Collection run duration |
| `flight_provider_errors_total` | Counter | Provider errors (labels: provider) |

#### API Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `flight_api_requests_total` | Counter | Total API requests (labels: method, endpoint, status) |
| `flight_api_request_duration_seconds` | Histogram | Request duration |

#### Recommendation Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `flight_recommendations_generated_total` | Counter | Total recommendations (labels: action) |

#### Database Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `flight_db_snapshots_total` | Gauge | Total snapshots in database |
| `flight_db_recommendations_total` | Gauge | Total recommendations in database |

### Viewing Raw Metrics

```bash
# All metrics
curl http://localhost:8000/metrics

# Filter specific metric
curl http://localhost:8000/metrics | grep flight_snapshots_collected

# With labels
curl http://localhost:8000/metrics | grep 'provider="mock"'
```

### Adding Custom Metrics

To add new metrics, edit `app/metrics/__init__.py`:

```python
from prometheus_client import Counter

# Define metric
custom_metric = Counter(
    "flight_custom_total",
    "Description of custom metric",
    ["label1", "label2"],
    registry=registry,
)

# Use in code
custom_metric.labels(label1="value1", label2="value2").inc()
```

## Structured Logging

### Log Format

All logs are JSON-structured for easy parsing:

```json
{
  "timestamp": "2024-01-11T10:00:00Z",
  "level": "INFO",
  "module": "app.collector",
  "message": "Collection completed",
  "routes_searched": 24,
  "offers_collected": 150,
  "duration_seconds": 45.2
}
```

### Log Levels

- `DEBUG` - Detailed diagnostic information
- `INFO` - General informational messages
- `WARNING` - Warning messages for non-critical issues
- `ERROR` - Error messages for failures
- `CRITICAL` - Critical failures requiring immediate attention

### Viewing Logs

```bash
# All services
docker compose --profile flight-intel logs -f

# Specific service
docker compose logs -f flight-api
docker compose logs -f flight-collector

# Filter by level
docker compose logs flight-api | grep ERROR

# Last 100 lines
docker compose logs --tail=100 flight-api

# Since timestamp
docker compose logs --since="2024-01-11T10:00:00" flight-api
```

### Log Aggregation (Optional)

For advanced log management, integrate with:

**Loki** (Grafana's log aggregation system):
```yaml
# Add to compose.yaml
loki:
  image: grafana/loki:latest
  ports:
    - "3100:3100"
  command: -config.file=/etc/loki/local-config.yaml
```

**Promtail** (Log shipper):
```yaml
promtail:
  image: grafana/promtail:latest
  volumes:
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - ./promtail-config.yml:/etc/promtail/config.yml
  command: -config.file=/etc/promtail/config.yml
```

## Alerting

### Prometheus Alerts

Create `alerts.yml`:

```yaml
groups:
  - name: flight_intel_alerts
    interval: 1m
    rules:
      # Alert on collection failures
      - alert: CollectionFailing
        expr: rate(flight_collection_runs_total{status="error"}[1h]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Flight collection is failing"
          description: "Collection has failed {{ $value }} times in the last hour"

      # Alert on no recent collections
      - alert: NoRecentCollection
        expr: (time() - flight_collection_runs_total) > 86400
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "No collection in 24 hours"
          description: "Last collection was over 24 hours ago"

      # Alert on high error rate
      - alert: HighAPIErrorRate
        expr: |
          rate(flight_api_requests_total{status=~"5.."}[5m]) /
          rate(flight_api_requests_total[5m]) > 0.05
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High API error rate"
          description: "API error rate is {{ $value | humanizePercentage }}"
```

### Grafana Alerts

1. Open dashboard panel
2. Click "Alert" tab
3. Create alert rule
4. Configure notification channel
5. Save

**Example**: Alert when collection stops
- Condition: `flight_collection_runs_total` no change for 24h
- Notification: Email/Slack/ntfy

## Health Checks

### Service Health Endpoints

```bash
# API health
curl http://localhost:8000/health

# Expected response:
{
  "status": "healthy",
  "timestamp": "2024-01-11T10:00:00",
  "service": "flight-intel-api"
}
```

### Database Health

```bash
docker exec flight-postgres pg_isready -U flightintel
# Output: flightintel:5432 - accepting connections
```

### Collector Health

```bash
# Check if process is running
docker exec flight-collector pgrep -f collector
# Output: PID number
```

### Comprehensive Health Check

```bash
#!/bin/bash
# health_check.sh

echo "=== Flight Intelligence Health Check ==="

# API
if curl -sf http://localhost:8000/health > /dev/null; then
    echo "✅ API: Healthy"
else
    echo "❌ API: Unhealthy"
fi

# Database
if docker exec flight-postgres pg_isready -U flightintel > /dev/null 2>&1; then
    echo "✅ Database: Healthy"
else
    echo "❌ Database: Unhealthy"
fi

# Recent data
RECENT=$(docker exec flight-postgres psql -U flightintel flightintel -t -c "
SELECT COUNT(*) FROM price_snapshots
WHERE collected_at > NOW() - INTERVAL '24 hours';")

if [ "$RECENT" -gt 0 ]; then
    echo "✅ Data: $RECENT snapshots in last 24h"
else
    echo "⚠️  Data: No recent snapshots"
fi

echo "=== Health Check Complete ==="
```

## Performance Monitoring

### Database Performance

```sql
-- Slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Index usage
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC
LIMIT 10;
```

### Application Performance

```bash
# Container resource usage
docker stats flight-api flight-ui flight-collector flight-postgres

# API response time
time curl http://localhost:8000/offers/best?limit=10
```

## Troubleshooting

### No Metrics Visible

1. **Check Prometheus is scraping**:
   ```bash
   curl http://localhost:9091/targets
   ```
   - Should show `flight-api` target as UP

2. **Check metrics endpoint**:
   ```bash
   curl http://localhost:8000/metrics
   ```
   - Should return Prometheus format metrics

3. **Check Grafana data source**:
   - Grafana → Configuration → Data Sources → Prometheus
   - Click "Test" - should succeed

### Grafana Dashboard Empty

1. **Check time range**: Ensure dashboard time range includes recent data
2. **Check queries**: Edit panel and verify PromQL queries
3. **Refresh**: Click refresh button (top right)

### High Memory Usage

```bash
# Check memory limits
docker inspect flight-postgres | grep -A 5 Memory

# Increase limits in .env
POSTGRES_MEM_LIMIT=2g

# Restart
docker compose up -d flight-postgres
```

## Best Practices

1. **Set Up Alerts**: Configure alerts for critical metrics
2. **Regular Review**: Check dashboards weekly
3. **Capacity Planning**: Monitor trends for resource needs
4. **Retention**: Configure Prometheus retention (default: 15 days)
5. **Backup**: Export Grafana dashboards regularly

## Resources

- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **PromQL Guide**: https://prometheus.io/docs/prometheus/latest/querying/basics/

---

For operational procedures, see `docs/RUNBOOK.md`.
