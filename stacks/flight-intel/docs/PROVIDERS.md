# Flight Provider Documentation

## Overview

Flight Intelligence supports multiple flight data providers through a unified interface. The system automatically falls back to MockProvider if real providers are unavailable or misconfigured.

## Provider Interface

All providers implement the `FlightProvider` abstract base class:

```python
class FlightProvider(ABC):
    @abstractmethod
    def search_flights(
        self,
        origin: str,
        destination: str,
        depart_date: str,
        return_date: Optional[str] = None,
        cabin: str = "ECONOMY",
        max_stops: int = 2,
        currency: str = "EUR",
    ) -> List[FlightOffer]:
        """Search for flight offers."""
        pass

    @abstractmethod
    def is_available(self) -> bool:
        """Check if provider is available and configured."""
        pass
```

## MockProvider

### Description

The MockProvider generates synthetic flight data for development and testing. It always returns valid, deterministic results without requiring external API credentials.

### Features

- ✅ Always available (no configuration required)
- ✅ Deterministic prices (same input = same output)
- ✅ Realistic price variations based on:
  - Destination
  - Days until departure
  - Route popularity
- ✅ Includes realistic airlines, stops, and booking links
- ✅ Zero cost (no API usage)

### Configuration

```bash
# .env
DEFAULT_PROVIDER=mock
```

No additional configuration required.

### Price Generation Logic

MockProvider generates prices using this formula:

```python
base_price = 150.0 (round-trip) or 80.0 (one-way)

# Adjust for destination
if destination in ["HER", "CHQ"]:
    base_price += 50.0

# Adjust for booking time
if days_ahead < 30:
    base_price *= 1.3  # Last-minute premium
elif days_ahead > 90:
    base_price *= 0.85  # Early booking discount

# Add random variation
final_price = base_price * random(0.85, 1.25) + random(-20, 30)
```

### Example Output

```json
{
  "origin": "AMS",
  "destination": "HER",
  "depart_date": "2024-06-15",
  "return_date": "2024-06-22",
  "stay_days": 7,
  "price_total": 289.50,
  "currency": "EUR",
  "provider": "mock",
  "airline": "KLM",
  "stops": 0,
  "deep_link": "https://example.com/book/AMS-HER-2024-06-15"
}
```

## AmadeusProvider

### Description

Integration with [Amadeus for Developers](https://developers.amadeus.com) API for real-time flight search data.

### Features

- ✅ Real-time flight prices from actual airlines
- ✅ OAuth2 authentication with token caching
- ✅ Automatic token refresh
- ✅ Rate-limit friendly
- ✅ Automatic fallback to MockProvider if unavailable

### Setup

1. **Sign Up for Amadeus**:
   - Visit https://developers.amadeus.com
   - Create a free account
   - Create a new application

2. **Get API Credentials**:
   - API Key (Client ID)
   - API Secret (Client Secret)
   - Choose Test or Production environment

3. **Configure Environment**:
   ```bash
   # .env
   DEFAULT_PROVIDER=amadeus
   AMADEUS_API_KEY=your_api_key_here
   AMADEUS_API_SECRET=your_api_secret_here
   AMADEUS_BASE_URL=https://test.api.amadeus.com  # or https://api.amadeus.com for production
   ```

4. **Restart Services**:
   ```bash
   docker compose --profile flight-intel restart
   ```

### Authentication

AmadeusProvider uses OAuth2 Client Credentials flow:

1. Requests access token using API key/secret
2. Caches token in memory
3. Automatically refreshes before expiration (5 min buffer)
4. Token valid for 30 minutes by default

**Token Request**:
```http
POST /v1/security/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=YOUR_API_KEY
&client_secret=YOUR_API_SECRET
```

### API Endpoints Used

#### Flight Offers Search

```
GET /v2/shopping/flight-offers
```

**Parameters**:
- `originLocationCode`: IATA airport code (e.g., AMS)
- `destinationLocationCode`: IATA airport code (e.g., HER)
- `departureDate`: YYYY-MM-DD
- `returnDate`: YYYY-MM-DD (optional)
- `adults`: Number of passengers (default: 1)
- `travelClass`: ECONOMY, PREMIUM_ECONOMY, BUSINESS, FIRST
- `currencyCode`: EUR, USD, etc.
- `max`: Maximum results (default: 10)

**Example Request**:
```bash
curl "https://test.api.amadeus.com/v2/shopping/flight-offers?originLocationCode=AMS&destinationLocationCode=HER&departureDate=2024-06-15&returnDate=2024-06-22&adults=1&travelClass=ECONOMY&currencyCode=EUR&max=10" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Rate Limits

#### Test Environment
- **Requests per second**: 10
- **Requests per month**: 2,000 free quota

#### Production Environment
- **Requests per second**: Varies by plan
- **Monthly quota**: Based on subscription

**Our Implementation**:
- 0.5 second delay between requests
- Batch processing of routes
- Caching in `daily_best` table

### Error Handling

The provider handles these errors gracefully:

1. **Authentication Failures**:
   - Invalid credentials → Falls back to MockProvider
   - Token expired → Auto-refreshes and retries

2. **API Errors**:
   - Rate limit exceeded → Logs error, skips route
   - Network timeout → Logs error, continues collection
   - Invalid parameters → Logs error, skips route

3. **Data Issues**:
   - Empty results → Returns empty list
   - Malformed response → Logs warning, continues

### Response Mapping

Amadeus API response is mapped to our normalized `FlightOffer`:

```python
# Amadeus response structure
{
  "data": [
    {
      "id": "1",
      "price": {
        "total": "299.99",
        "currency": "EUR"
      },
      "itineraries": [
        {
          "segments": [
            {
              "carrierCode": "KL",
              "departure": {...},
              "arrival": {...}
            }
          ]
        }
      ]
    }
  ]
}

# Mapped to FlightOffer
FlightOffer(
    origin="AMS",
    destination="HER",
    depart_date="2024-06-15",
    return_date="2024-06-22",
    price_total=299.99,
    currency="EUR",
    provider="amadeus",
    airline="KL",
    stops=0,  # calculated from segments
    deep_link=None,  # not provided by this API
    raw_data={...}  # full response stored
)
```

### Best Practices

1. **Use Test Environment** for development:
   ```bash
   AMADEUS_BASE_URL=https://test.api.amadeus.com
   ```

2. **Monitor API Usage**:
   - Check Amadeus dashboard for quota
   - View metrics: `curl http://localhost:8000/metrics | grep provider_errors`

3. **Optimize Searches**:
   - Limit date ranges in `search_configs`
   - Use smaller `COLLECTOR_BATCH_SIZE` to respect rate limits
   - Schedule collection during off-peak hours

4. **Production Checklist**:
   - [ ] Switch to production API URL
   - [ ] Upgrade Amadeus plan if needed for quota
   - [ ] Monitor error rates in Grafana
   - [ ] Set appropriate collection schedule

### Troubleshooting

#### "Failed to get access token"

**Cause**: Invalid API credentials

**Solution**:
```bash
# Verify credentials in .env
grep AMADEUS_ .env

# Test authentication manually
curl -X POST "https://test.api.amadeus.com/v1/security/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=YOUR_KEY&client_secret=YOUR_SECRET"
```

#### "Provider automatically falling back to mock"

**Cause**: `AMADEUS_API_KEY` or `AMADEUS_API_SECRET` not set

**Solution**:
```bash
# Check .env
grep AMADEUS_API_KEY .env
grep AMADEUS_API_SECRET .env

# If empty, add credentials and restart
docker compose --profile flight-intel restart
```

#### "Rate limit exceeded"

**Cause**: Too many requests in short time

**Solution**:
```bash
# Reduce collection frequency
COLLECTOR_SCHEDULE="0 6 * * *"  # Once per day at 6 AM

# Reduce batch size
COLLECTOR_BATCH_SIZE=5

# Restart collector
docker compose restart flight-collector
```

## Adding New Providers

To add a new flight data provider:

### 1. Implement Provider Class

```python
# app/providers/new_provider.py

from app.providers.flight_providers import FlightProvider, FlightOffer

class NewProvider(FlightProvider):
    def __init__(self):
        self.api_key = settings.new_provider_api_key
        # Initialize provider-specific settings

    def search_flights(self, origin, destination, depart_date, ...):
        # Implement search logic
        # Make API calls
        # Map to FlightOffer objects
        return offers

    def is_available(self):
        # Check if credentials are configured
        return bool(self.api_key)
```

### 2. Register Provider

```python
# app/providers/flight_providers.py

def get_provider(provider_name: Optional[str] = None) -> FlightProvider:
    if provider_name is None:
        provider_name = settings.default_provider

    if provider_name == "amadeus":
        # ... existing code
    elif provider_name == "new_provider":
        from app.providers.new_provider import NewProvider
        provider = NewProvider()
        if provider.is_available():
            return provider
        logger.warning("NewProvider not configured, falling back to mock")

    return MockProvider()
```

### 3. Add Configuration

```python
# app/config.py
class Settings(BaseSettings):
    # ... existing settings

    # New provider
    new_provider_api_key: str = ""
    new_provider_base_url: str = "https://api.newprovider.com"
```

```bash
# .env.example
# New Provider Configuration
NEW_PROVIDER_API_KEY=
NEW_PROVIDER_BASE_URL=https://api.newprovider.com
```

### 4. Add Tests

```python
# tests/unit/test_new_provider.py

def test_new_provider_available():
    provider = NewProvider()
    assert provider.is_available() in [True, False]

def test_new_provider_search():
    provider = NewProvider()
    if provider.is_available():
        offers = provider.search_flights(...)
        assert isinstance(offers, list)
```

### 5. Update Documentation

- Add provider details to this file
- Update README.md with usage instructions
- Add troubleshooting section

## Provider Selection

The system selects a provider using this logic:

```
1. Check DEFAULT_PROVIDER setting
2. If provider has credentials and is_available() → Use it
3. Otherwise → Fall back to MockProvider
4. Log the selection decision
```

Example log output:
```
INFO: Using Amadeus provider
```

or

```
WARNING: Amadeus credentials not configured, falling back to MockProvider
INFO: Using MockProvider
```

## Monitoring Provider Performance

### Metrics

View provider-specific metrics:

```bash
curl http://localhost:8000/metrics | grep flight_snapshots_collected_total
```

Output:
```
flight_snapshots_collected_total{provider="mock",origin="AMS",destination="HER"} 150
flight_snapshots_collected_total{provider="amadeus",origin="AMS",destination="HER"} 75
```

### Error Tracking

```bash
curl http://localhost:8000/metrics | grep flight_provider_errors_total
```

### Grafana Dashboard

Access Grafana (http://localhost:3000) to view:
- Snapshot collection rates by provider
- Provider error rates
- Collection success/failure ratio

## Cost Considerations

### MockProvider
- **Cost**: $0
- **Quota**: Unlimited
- **Rate Limits**: None
- **Best For**: Development, testing, demos

### Amadeus Test
- **Cost**: Free tier available
- **Quota**: 2,000 requests/month
- **Rate Limits**: 10 requests/second
- **Best For**: Development, small-scale production

### Amadeus Production
- **Cost**: Varies by plan (check Amadeus pricing)
- **Quota**: Based on subscription
- **Rate Limits**: Based on plan
- **Best For**: Production with real-time data needs

### Optimization Tips

1. **Use daily_best table** for cached results
2. **Limit search_configs** to needed routes only
3. **Adjust collection frequency** based on price volatility
4. **Monitor quota usage** in provider dashboard

---

For issues or questions about providers, see `docs/TROUBLESHOOTING.md`.
