"""Integration tests for flight intelligence."""

import os
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.db.models import Base, SearchConfig, PriceSnapshot, Recommendation
from app.collector import Collector


@pytest.fixture(scope="session")
def test_database_url():
    """Get test database URL from environment or use default."""
    return os.getenv(
        "TEST_DATABASE_URL",
        "postgresql://flightintel:flightintel@localhost:5432/flightintel_test"
    )


@pytest.fixture(scope="session")
def test_engine(test_database_url):
    """Create test database engine."""
    engine = create_engine(test_database_url)
    
    # Create tables
    Base.metadata.create_all(engine)
    
    yield engine
    
    # Cleanup
    Base.metadata.drop_all(engine)


@pytest.fixture
def test_session(test_engine):
    """Create test database session."""
    Session = sessionmaker(bind=test_engine)
    session = Session()
    
    yield session
    
    # Cleanup after each test
    session.rollback()
    session.close()


def test_database_migrations(test_engine):
    """Test that database migrations create all expected tables."""
    # Check that all tables exist
    with test_engine.connect() as conn:
        result = conn.execute(
            text(
                """
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                """
            )
        )
        tables = [row[0] for row in result]
    
    expected_tables = [
        "routes",
        "search_configs",
        "price_snapshots",
        "daily_best",
        "recommendations",
    ]
    
    for table in expected_tables:
        assert table in tables, f"Table {table} not found in database"


def test_insert_search_config(test_session):
    """Test inserting a search configuration."""
    config = SearchConfig(
        name="Test Config",
        origins=["AMS", "EIN"],
        destinations=["HER", "CHQ"],
        start_date="2024-06-01",
        end_date="2024-08-31",
        min_stay_days=7,
        max_stay_days=14,
        cabin="ECONOMY",
        max_stops=2,
        currency="EUR",
        active=True,
    )
    
    test_session.add(config)
    test_session.commit()
    
    # Verify insertion
    result = test_session.query(SearchConfig).filter_by(name="Test Config").first()
    assert result is not None
    assert result.origins == ["AMS", "EIN"]
    assert result.destinations == ["HER", "CHQ"]


def test_insert_price_snapshot(test_session):
    """Test inserting a price snapshot."""
    from app.providers import FlightOffer
    
    offer = FlightOffer(
        origin="AMS",
        destination="HER",
        depart_date="2024-06-15",
        return_date="2024-06-22",
        price_total=299.99,
        currency="EUR",
        provider="mock",
        airline="KLM",
        stops=0,
    )
    
    snapshot = PriceSnapshot(**offer.to_dict())
    test_session.add(snapshot)
    test_session.commit()
    
    # Verify insertion
    result = test_session.query(PriceSnapshot).filter_by(hash=offer.hash).first()
    assert result is not None
    assert result.origin == "AMS"
    assert result.destination == "HER"
    assert result.price_total == 299.99


def test_collector_with_mock_provider(test_session):
    """Test collector with mock provider."""
    # Create a test search config
    config = SearchConfig(
        name="Test Collection",
        origins=["AMS"],
        destinations=["HER"],
        start_date="2024-06-01",
        end_date="2024-06-30",
        min_stay_days=7,
        max_stay_days=7,
        cabin="ECONOMY",
        max_stops=2,
        currency="EUR",
        active=True,
    )
    
    test_session.add(config)
    test_session.commit()
    
    # Run collector
    collector = Collector()
    result = collector.run_collection()
    
    # Verify collection ran
    assert result["status"] in ["success", "no_configs"]
    if result["status"] == "success":
        assert result["routes_searched"] > 0
        assert result["offers_collected"] > 0
