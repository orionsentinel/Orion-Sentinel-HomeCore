"""Unit tests for provider implementations."""

import pytest

from app.providers import FlightOffer, MockProvider


def test_mock_provider_available():
    """Test that mock provider is always available."""
    provider = MockProvider()
    assert provider.is_available() is True


def test_mock_provider_search():
    """Test mock provider search functionality."""
    provider = MockProvider()
    
    offers = provider.search_flights(
        origin="AMS",
        destination="HER",
        depart_date="2024-06-15",
        return_date="2024-06-22",
        cabin="ECONOMY",
        max_stops=2,
        currency="EUR",
    )
    
    # Should return multiple offers
    assert len(offers) >= 3
    assert len(offers) <= 5
    
    # Check offer structure
    offer = offers[0]
    assert isinstance(offer, FlightOffer)
    assert offer.origin == "AMS"
    assert offer.destination == "HER"
    assert offer.depart_date == "2024-06-15"
    assert offer.return_date == "2024-06-22"
    assert offer.stay_days == 7
    assert offer.price_total > 0
    assert offer.currency == "EUR"
    assert offer.provider == "mock"
    assert offer.airline is not None
    assert offer.stops is not None
    assert offer.hash is not None


def test_flight_offer_hash_generation():
    """Test that flight offer generates consistent hash."""
    offer1 = FlightOffer(
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
    
    offer2 = FlightOffer(
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
    
    # Same offers should have same hash
    assert offer1.hash == offer2.hash


def test_flight_offer_to_dict():
    """Test flight offer serialization to dict."""
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
    
    data = offer.to_dict()
    
    assert data["origin"] == "AMS"
    assert data["destination"] == "HER"
    assert data["price_total"] == 299.99
    assert data["stay_days"] == 7
    assert data["hash"] is not None
