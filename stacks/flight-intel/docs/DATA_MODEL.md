# Flight Intelligence Data Model

## Overview

The Flight Intelligence system uses PostgreSQL for data storage with five main tables:

1. **routes** - Flight route configurations
2. **search_configs** - Search parameters for automated collection
3. **price_snapshots** - Historical price data points
4. **daily_best** - Aggregated best prices per day
5. **recommendations** - Buy/wait recommendations

## Schema Diagrams

### Entity Relationships

```
search_configs (1) -----> (*) routes
                             |
                             v
                       price_snapshots (*)
                             |
                             v
                       daily_best (*)
                             |
                             v
                       recommendations (*)
```

## Table Definitions

### routes

Stores configured flight routes to monitor.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| origin_airport | STRING(3) | IATA origin airport code (e.g., AMS) |
| dest_airport | STRING(3) | IATA destination airport code (e.g., HER) |
| active | BOOLEAN | Whether route is actively monitored |
| created_at | TIMESTAMP | Record creation timestamp |

**Indexes**:
- `idx_route_active`: (origin_airport, dest_airport, active)

**Constraints**:
- `uq_route`: Unique (origin_airport, dest_airport)

**Example**:
```sql
INSERT INTO routes (origin_airport, dest_airport, active)
VALUES ('AMS', 'HER', true);
```

### search_configs

Defines search parameters for automated collection.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| name | STRING(255) | Unique configuration name |
| origins | ARRAY[STRING] | List of origin airport codes |
| destinations | ARRAY[STRING] | List of destination airport codes |
| start_date | STRING(10) | Search window start (YYYY-MM-DD) |
| end_date | STRING(10) | Search window end (YYYY-MM-DD) |
| min_stay_days | INTEGER | Minimum trip duration |
| max_stay_days | INTEGER | Maximum trip duration |
| cabin | STRING(20) | Cabin class (ECONOMY, BUSINESS, etc.) |
| max_stops | INTEGER | Maximum number of stops |
| currency | STRING(3) | Price currency code |
| active | BOOLEAN | Whether configuration is active |
| created_at | TIMESTAMP | Record creation timestamp |

**Constraints**:
- `name` is unique

**Example**:
```sql
INSERT INTO search_configs
  (name, origins, destinations, start_date, end_date,
   min_stay_days, max_stay_days, cabin, max_stops, currency, active)
VALUES
  ('Crete Summer 2024',
   ARRAY['AMS', 'EIN', 'RTM', 'BRU'],
   ARRAY['HER', 'CHQ'],
   '2024-06-01', '2024-08-31',
   7, 21, 'ECONOMY', 2, 'EUR', true);
```

### price_snapshots

Historical flight price data collected from providers.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| collected_at | TIMESTAMP | When snapshot was collected |
| provider | STRING(50) | Data provider (mock, amadeus) |
| origin | STRING(3) | Origin airport code |
| destination | STRING(3) | Destination airport code |
| depart_date | STRING(10) | Departure date (YYYY-MM-DD) |
| return_date | STRING(10) | Return date (NULL for one-way) |
| stay_days | INTEGER | Trip duration in days |
| price_total | FLOAT | Total price |
| currency | STRING(3) | Price currency |
| airline | STRING(50) | Operating airline (if known) |
| stops | INTEGER | Number of stops |
| deep_link | TEXT | Booking URL (if available) |
| raw_json | JSONB | Raw provider response |
| hash | STRING(64) | SHA-256 hash for deduplication |

**Indexes**:
- `idx_snapshot_collected`: (collected_at, provider)
- `idx_snapshot_route_date`: (origin, destination, depart_date, return_date)
- `idx_snapshot_price`: (origin, destination, price_total)

**Constraints**:
- `hash` is unique (prevents duplicate snapshots)

**Example**:
```sql
INSERT INTO price_snapshots
  (provider, origin, destination, depart_date, return_date,
   stay_days, price_total, currency, airline, stops, hash)
VALUES
  ('mock', 'AMS', 'HER', '2024-06-15', '2024-06-22',
   7, 299.99, 'EUR', 'KLM', 0, 'abc123...');
```

### daily_best

Aggregated best prices per day for quick lookups.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| date_bucket | STRING(10) | Date bucket (YYYY-MM-DD) |
| origin | STRING(3) | Origin airport code |
| destination | STRING(3) | Destination airport code |
| depart_date | STRING(10) | Departure date |
| return_date | STRING(10) | Return date (NULL for one-way) |
| stay_days | INTEGER | Trip duration |
| best_price | FLOAT | Best (minimum) price for this combination |
| provider | STRING(50) | Provider with best price |
| updated_at | TIMESTAMP | Last update timestamp |

**Indexes**:
- `idx_daily_best_lookup`: (origin, destination, depart_date, return_date, date_bucket)

**Constraints**:
- `uq_daily_best`: Unique (date_bucket, origin, destination, depart_date, return_date)

**Materialization**: Updated by collector after each run.

**Example**:
```sql
INSERT INTO daily_best
  (date_bucket, origin, destination, depart_date, return_date,
   stay_days, best_price, provider)
VALUES
  ('2024-01-11', 'AMS', 'HER', '2024-06-15', '2024-06-22',
   7, 279.99, 'mock')
ON CONFLICT (date_bucket, origin, destination, depart_date, return_date)
DO UPDATE SET
  best_price = EXCLUDED.best_price,
  updated_at = NOW();
```

### recommendations

Buy/wait/hold recommendations generated by the recommendation engine.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| created_at | TIMESTAMP | When recommendation was generated |
| origin | STRING(3) | Origin airport code |
| destination | STRING(3) | Destination airport code |
| depart_date | STRING(10) | Departure date |
| return_date | STRING(10) | Return date (NULL for one-way) |
| stay_days | INTEGER | Trip duration |
| action | STRING(10) | Recommendation: BUY, WAIT, or HOLD |
| confidence | FLOAT | Confidence score (0.0 to 1.0) |
| threshold_price | FLOAT | Price threshold for BUY action |
| current_price | FLOAT | Current best price |
| rationale | JSONB | Detailed reasoning (JSON) |

**Indexes**:
- `idx_reco_lookup`: (origin, destination, depart_date, return_date)
- `idx_reco_created_at`: (created_at)

**Example**:
```sql
INSERT INTO recommendations
  (origin, destination, depart_date, return_date,
   stay_days, action, confidence, threshold_price,
   current_price, rationale)
VALUES
  ('AMS', 'HER', '2024-06-15', '2024-06-22',
   7, 'BUY', 0.85, 280.00, 275.00,
   '{"reason": "Price is below historical minimum", "rolling_min": 280.00}');
```

## Query Examples

### Get Best Offers for a Route

```sql
SELECT
  depart_date,
  return_date,
  MIN(price_total) as best_price,
  COUNT(*) as offer_count
FROM price_snapshots
WHERE origin = 'AMS'
  AND destination = 'HER'
  AND depart_date >= CURRENT_DATE
GROUP BY depart_date, return_date
ORDER BY best_price ASC
LIMIT 10;
```

### Price History for Specific Trip

```sql
SELECT
  DATE(collected_at) as date,
  MIN(price_total) as min_price,
  AVG(price_total) as avg_price,
  COUNT(*) as samples
FROM price_snapshots
WHERE origin = 'AMS'
  AND destination = 'HER'
  AND depart_date = '2024-06-15'
  AND return_date = '2024-06-22'
GROUP BY DATE(collected_at)
ORDER BY date DESC;
```

### Recent Recommendations

```sql
SELECT
  origin,
  destination,
  depart_date,
  return_date,
  action,
  confidence,
  current_price,
  rationale->>'reason' as reason
FROM recommendations
WHERE created_at >= NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 20;
```

### Collection Statistics

```sql
SELECT
  DATE(collected_at) as date,
  provider,
  COUNT(*) as snapshots,
  COUNT(DISTINCT origin || '-' || destination) as routes,
  AVG(price_total) as avg_price
FROM price_snapshots
WHERE collected_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(collected_at), provider
ORDER BY date DESC;
```

## Data Retention

### Recommended Policies

- **price_snapshots**: Keep 90 days (configurable)
- **daily_best**: Keep 180 days
- **recommendations**: Keep 30 days
- **search_configs**: Keep all (or archive inactive)
- **routes**: Keep all

### Cleanup Queries

```sql
-- Delete old snapshots (90 days)
DELETE FROM price_snapshots
WHERE collected_at < NOW() - INTERVAL '90 days';

-- Delete old recommendations (30 days)
DELETE FROM recommendations
WHERE created_at < NOW() - INTERVAL '30 days';

-- Archive inactive search configs
UPDATE search_configs
SET active = false
WHERE end_date < CURRENT_DATE;
```

## Backup Considerations

- **Full backup**: Include all tables
- **Frequency**: Daily (via cron)
- **Retention**: 30 days of backups
- **Format**: Compressed SQL dump (gzip)

See `scripts/backup.sh` for automated backup implementation.

## Performance Optimization

### Index Maintenance

```sql
-- Analyze tables (update statistics)
ANALYZE price_snapshots;
ANALYZE daily_best;
ANALYZE recommendations;

-- Rebuild indexes (if needed)
REINDEX TABLE price_snapshots;
```

### Query Performance

- Use `daily_best` for recent best prices (pre-aggregated)
- Add indexes on frequently filtered columns
- Use `EXPLAIN ANALYZE` to diagnose slow queries
- Consider partitioning `price_snapshots` by date for large datasets

## Migration Management

Migrations are managed with Alembic:

```bash
# Create new migration
alembic revision -m "description"

# Apply migrations
alembic upgrade head

# Rollback migration
alembic downgrade -1

# View current version
alembic current

# View history
alembic history
```

See `alembic/versions/` for migration files.
