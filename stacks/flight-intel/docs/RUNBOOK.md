# Flight Intelligence Operational Runbook

## Daily Operations

### Monitoring Health

**Check Service Status**:
```bash
docker compose --profile flight-intel ps
```

All services should show "Up" with healthy status.

**Check API Health**:
```bash
curl http://localhost:8000/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-11T10:00:00",
  "service": "flight-intel-api"
}
```

**Check Collection Status**:
```bash
docker compose logs --tail=50 flight-collector
```

Look for successful collection messages with offer counts.

### Common Maintenance Tasks

#### Trigger Manual Collection

```bash
API_KEY=$(grep API_KEY .env | cut -d= -f2)
curl -X POST "http://localhost:8000/collect/trigger" \
  -H "X-API-Key: $API_KEY"
```

#### View Recent Offers

```bash
curl "http://localhost:8000/offers/best?limit=10"
```

#### Create Manual Backup

```bash
./scripts/backup.sh
```

#### Check Disk Usage

```bash
# Docker volumes
docker system df -v

# Backup directory
du -sh data/backups/
```

## Troubleshooting Guide

### Collector Not Running

**Symptoms**: No new price data, collector container exiting

**Diagnosis**:
```bash
docker compose logs flight-collector
docker compose ps flight-collector
```

**Common Causes**:

1. **Collector disabled in config**:
   ```bash
   grep COLLECTOR_ENABLED .env
   # Should be: COLLECTOR_ENABLED=true
   ```

2. **Database connection failure**:
   ```bash
   docker exec flight-collector python -c "from app.db import SessionLocal; SessionLocal()"
   ```

3. **Invalid cron schedule**:
   ```bash
   grep COLLECTOR_SCHEDULE .env
   # Format: "minute hour day month day_of_week"
   # Default: "0 3 * * *"
   ```

**Solution**:
```bash
# Fix configuration and restart
docker compose restart flight-collector
```

### Database Issues

**Symptoms**: API 500 errors, connection timeouts

**Diagnosis**:
```bash
docker exec flight-postgres pg_isready -U flightintel
docker compose logs flight-postgres
```

**Solutions**:

1. **Database not running**:
   ```bash
   docker compose up -d flight-postgres
   ```

2. **Connection pool exhausted**:
   ```bash
   docker compose restart flight-api
   ```

3. **Disk full**:
   ```bash
   df -h
   # Clean old backups if needed
   find data/backups/ -type f -mtime +30 -delete
   ```

4. **Corrupted data**:
   ```bash
   docker exec flight-postgres psql -U flightintel -c "VACUUM FULL;"
   ```

### API Performance Issues

**Symptoms**: Slow responses, timeouts

**Diagnosis**:
```bash
# Check metrics
curl http://localhost:8000/metrics | grep api_request_duration

# Check resource usage
docker stats flight-api
```

**Solutions**:

1. **High database query time**:
   ```bash
   # Check for missing indexes
   docker exec flight-postgres psql -U flightintel flightintel -c "
   SELECT schemaname, tablename, indexname, idx_scan
   FROM pg_stat_user_indexes
   ORDER BY idx_scan ASC
   LIMIT 10;"
   ```

2. **Memory pressure**:
   ```bash
   # Increase memory limit in .env
   API_MEM_LIMIT=1g
   docker compose up -d flight-api
   ```

3. **Too many snapshots**:
   ```bash
   # Archive old data (older than 90 days)
   docker exec flight-postgres psql -U flightintel flightintel -c "
   DELETE FROM price_snapshots
   WHERE collected_at < NOW() - INTERVAL '90 days';"
   ```

### UI Not Loading

**Symptoms**: Blank page, connection refused

**Diagnosis**:
```bash
docker compose logs flight-ui
curl -f http://localhost:8501/_stcore/health
```

**Solutions**:

1. **API not accessible**:
   ```bash
   docker exec flight-ui curl -f http://flight-api:8000/health
   ```

2. **Port conflict**:
   ```bash
   # Change UI_PORT in .env
   UI_PORT=8502
   docker compose up -d flight-ui
   ```

3. **Memory issue**:
   ```bash
   # Increase memory limit
   UI_MEM_LIMIT=1g
   docker compose up -d flight-ui
   ```

## Updating the System

### Update Application Code

```bash
# 1. Pull latest code
git pull

# 2. Rebuild containers
cd stacks/flight-intel
docker compose --profile flight-intel build

# 3. Stop services
docker compose --profile flight-intel down

# 4. Run migrations
docker compose up -d flight-postgres
sleep 10
docker compose run --rm flight-api alembic upgrade head

# 5. Start all services
docker compose --profile flight-intel up -d
```

### Update Docker Images

```bash
# Pull latest base images
docker compose --profile flight-intel pull

# Rebuild and restart
docker compose --profile flight-intel up -d --build
```

### Schema Migrations

```bash
# Check current version
docker exec flight-api alembic current

# View migration history
docker exec flight-api alembic history

# Upgrade to latest
docker exec flight-api alembic upgrade head

# Rollback one version (if needed)
docker exec flight-api alembic downgrade -1
```

## Backup and Recovery

### Automated Backups

Set up cron job for automated backups:

```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * /path/to/stacks/flight-intel/scripts/backup.sh >> /var/log/flight-intel-backup.log 2>&1
```

### Manual Backup

```bash
./scripts/backup.sh
```

Backups are stored in `data/backups/` with format: `flight_intel_backup_YYYYMMDD_HHMMSS.sql.gz`

### Restore from Backup

```bash
# List available backups
ls -lh data/backups/

# Restore (WARNING: drops existing database)
./scripts/restore.sh data/backups/flight_intel_backup_20240111_120000.sql.gz
```

### Disaster Recovery

**Complete system restore**:

```bash
# 1. Stop all services
docker compose --profile flight-intel down

# 2. Restore database
./scripts/restore.sh <backup_file>

# 3. Verify data
docker exec flight-postgres psql -U flightintel flightintel -c "
SELECT COUNT(*) FROM price_snapshots;
SELECT COUNT(*) FROM search_configs;
"

# 4. Start services
docker compose --profile flight-intel up -d
```

## Security Operations

### Rotate API Key

```bash
# 1. Generate new key
NEW_KEY=$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)

# 2. Update .env
sed -i "s/API_KEY=.*/API_KEY=$NEW_KEY/" .env

# 3. Restart services
docker compose --profile flight-intel restart

# 4. Update any clients/scripts using the old key
```

### Rotate Database Password

```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)

# 2. Update password in database
docker exec flight-postgres psql -U flightintel -c "
ALTER USER flightintel WITH PASSWORD '$NEW_PASS';"

# 3. Update .env
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$NEW_PASS/" .env
sed -i "s/:.*@/:$NEW_PASS@/" .env  # Update DATABASE_URL

# 4. Restart all services
docker compose --profile flight-intel down
docker compose --profile flight-intel up -d
```

### Review Security

```bash
# Check for exposed ports
docker compose ps

# Verify localhost binding
grep HOST_IP .env
# Should be: HOST_IP=127.0.0.1 (unless LAN access needed)

# Check for secrets in logs
docker compose logs | grep -i password

# Review container users
docker compose exec flight-api whoami
# Should be: flightintel (not root)
```

## Performance Tuning

### Database Optimization

```bash
# Analyze tables
docker exec flight-postgres psql -U flightintel flightintel -c "
ANALYZE VERBOSE price_snapshots;
ANALYZE VERBOSE daily_best;
"

# Rebuild indexes
docker exec flight-postgres psql -U flightintel flightintel -c "
REINDEX TABLE price_snapshots;
"

# Check table sizes
docker exec flight-postgres psql -U flightintel flightintel -c "
SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

### Data Retention

Clean old data to improve performance:

```bash
# Remove snapshots older than 90 days
docker exec flight-postgres psql -U flightintel flightintel -c "
DELETE FROM price_snapshots
WHERE collected_at < NOW() - INTERVAL '90 days';
"

# Remove old recommendations (keep last 30 days)
docker exec flight-postgres psql -U flightintel flightintel -c "
DELETE FROM recommendations
WHERE created_at < NOW() - INTERVAL '30 days';
"

# Vacuum to reclaim space
docker exec flight-postgres psql -U flightintel flightintel -c "
VACUUM FULL ANALYZE;
"
```

## Monitoring and Alerts

### Set Up Prometheus Alerts

Create `alerts.yml`:
```yaml
groups:
  - name: flight-intel
    interval: 1m
    rules:
      - alert: CollectionFailing
        expr: rate(flight_collection_runs_total{status="error"}[1h]) > 0
        annotations:
          summary: "Flight collection is failing"

      - alert: NoRecentCollection
        expr: (time() - flight_collection_runs_total) > 86400
        annotations:
          summary: "No collection in 24 hours"
```

### Health Check Script

```bash
#!/bin/bash
# health_check.sh - Run comprehensive health checks

echo "=== Flight Intelligence Health Check ==="

# API
if curl -sf http://localhost:8000/health > /dev/null; then
    echo "✅ API is healthy"
else
    echo "❌ API is unhealthy"
fi

# Database
if docker exec flight-postgres pg_isready -U flightintel > /dev/null 2>&1; then
    echo "✅ Database is healthy"
else
    echo "❌ Database is unhealthy"
fi

# Recent data
RECENT_COUNT=$(docker exec flight-postgres psql -U flightintel flightintel -t -c "
SELECT COUNT(*) FROM price_snapshots
WHERE collected_at > NOW() - INTERVAL '24 hours';")

if [ "$RECENT_COUNT" -gt 0 ]; then
    echo "✅ Recent data: $RECENT_COUNT snapshots in last 24h"
else
    echo "⚠️  No data collected in last 24h"
fi

echo "=== Health Check Complete ==="
```

## Emergency Procedures

### Complete System Reset

**WARNING**: This will delete all data!

```bash
# 1. Stop all services
docker compose --profile flight-intel down -v

# 2. Remove all data
rm -rf data/postgres/*

# 3. Rebuild
./scripts/bootstrap.sh
docker compose --profile flight-intel up -d

# 4. Seed initial data
./scripts/seed_mock_data.sh
```

### Service Recovery Priority

If resources are limited, start services in this order:

1. **Database** (flight-postgres)
2. **API** (flight-api)
3. **Collector** (flight-collector)
4. **UI** (flight-ui)
5. **Optional services** (ollama, prometheus, etc.)

```bash
# Start core only
docker compose up -d flight-postgres
sleep 10
docker compose up -d flight-api
sleep 5
docker compose up -d flight-collector
docker compose up -d flight-ui
```

## Contact and Escalation

For critical issues:
1. Check logs: `docker compose logs`
2. Review this runbook
3. Check documentation in `docs/`
4. File issue with logs attached
