"""Prometheus metrics for observability."""

from prometheus_client import Counter, Gauge, Histogram, generate_latest
from prometheus_client.core import CollectorRegistry

# Create a custom registry
registry = CollectorRegistry()

# Collector metrics
snapshots_collected = Counter(
    "flight_snapshots_collected_total",
    "Total number of price snapshots collected",
    ["provider", "origin", "destination"],
    registry=registry,
)

collection_runs = Counter(
    "flight_collection_runs_total",
    "Total number of collection runs",
    ["status"],
    registry=registry,
)

collection_duration = Histogram(
    "flight_collection_duration_seconds",
    "Duration of collection runs in seconds",
    registry=registry,
)

provider_errors = Counter(
    "flight_provider_errors_total",
    "Total number of provider errors",
    ["provider"],
    registry=registry,
)

# API metrics
api_requests = Counter(
    "flight_api_requests_total",
    "Total number of API requests",
    ["method", "endpoint", "status"],
    registry=registry,
)

api_request_duration = Histogram(
    "flight_api_request_duration_seconds",
    "Duration of API requests in seconds",
    ["method", "endpoint"],
    registry=registry,
)

# Recommendation metrics
recommendations_generated = Counter(
    "flight_recommendations_generated_total",
    "Total number of recommendations generated",
    ["action"],
    registry=registry,
)

# Database metrics
db_snapshots_total = Gauge(
    "flight_db_snapshots_total",
    "Total number of snapshots in database",
    registry=registry,
)

db_recommendations_total = Gauge(
    "flight_db_recommendations_total",
    "Total number of recommendations in database",
    registry=registry,
)


def get_metrics() -> bytes:
    """Get metrics in Prometheus format."""
    return generate_latest(registry)
