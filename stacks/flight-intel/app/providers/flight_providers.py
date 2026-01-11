"""Provider interface and implementations."""

import hashlib
import json
import logging
import random
import time
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import requests

from app.config import settings

logger = logging.getLogger(__name__)


class FlightOffer:
    """Normalized flight offer."""

    def __init__(
        self,
        origin: str,
        destination: str,
        depart_date: str,
        return_date: Optional[str],
        price_total: float,
        currency: str,
        provider: str,
        airline: Optional[str] = None,
        stops: Optional[int] = None,
        deep_link: Optional[str] = None,
        raw_data: Optional[Dict[str, Any]] = None,
    ):
        """Initialize flight offer."""
        self.origin = origin
        self.destination = destination
        self.depart_date = depart_date
        self.return_date = return_date
        self.price_total = price_total
        self.currency = currency
        self.provider = provider
        self.airline = airline
        self.stops = stops
        self.deep_link = deep_link
        self.raw_data = raw_data or {}

        # Calculate stay days if return flight
        if return_date:
            depart = datetime.strptime(depart_date, "%Y-%m-%d")
            ret = datetime.strptime(return_date, "%Y-%m-%d")
            self.stay_days = (ret - depart).days
        else:
            self.stay_days = None

        # Generate hash for deduplication
        self.hash = self._generate_hash()

    def _generate_hash(self) -> str:
        """Generate unique hash for this offer."""
        data = f"{self.origin}{self.destination}{self.depart_date}{self.return_date}{self.price_total}{self.airline}{self.stops}"
        return hashlib.sha256(data.encode()).hexdigest()

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "origin": self.origin,
            "destination": self.destination,
            "depart_date": self.depart_date,
            "return_date": self.return_date,
            "stay_days": self.stay_days,
            "price_total": self.price_total,
            "currency": self.currency,
            "provider": self.provider,
            "airline": self.airline,
            "stops": self.stops,
            "deep_link": self.deep_link,
            "raw_json": self.raw_data,
            "hash": self.hash,
        }


class FlightProvider(ABC):
    """Abstract flight provider interface."""

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


class MockProvider(FlightProvider):
    """Mock provider for development and testing."""

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
        """Generate synthetic flight offers."""
        logger.info(
            f"MockProvider: Searching {origin}->{destination}, "
            f"depart={depart_date}, return={return_date}"
        )

        offers = []

        # Generate 3-5 synthetic offers with deterministic but varied prices
        num_offers = random.randint(3, 5)
        seed = hash(f"{origin}{destination}{depart_date}{return_date}")
        random.seed(seed)

        base_price = 150.0 if return_date else 80.0

        # Price varies by destination and dates
        if destination in ["HER", "CHQ"]:
            base_price += 50.0

        # Add variation based on depart date
        try:
            depart = datetime.strptime(depart_date, "%Y-%m-%d")
            days_ahead = (depart - datetime.now()).days
            if days_ahead < 30:
                base_price *= 1.3  # More expensive if soon
            elif days_ahead > 90:
                base_price *= 0.85  # Cheaper if far ahead
        except Exception:
            pass

        airlines = ["KLM", "Ryanair", "Transavia", "EasyJet", "Aegean"]

        for i in range(num_offers):
            price_variation = random.uniform(0.85, 1.25)
            price = base_price * price_variation + random.uniform(-20, 30)
            stops = random.choice([0, 0, 0, 1, 1, 2])  # More direct flights

            offer = FlightOffer(
                origin=origin,
                destination=destination,
                depart_date=depart_date,
                return_date=return_date,
                price_total=round(price, 2),
                currency=currency,
                provider="mock",
                airline=random.choice(airlines),
                stops=stops,
                deep_link=f"https://example.com/book/{origin}-{destination}-{depart_date}",
                raw_data={"mock": True, "offer_id": f"MOCK{i + 1}"},
            )
            offers.append(offer)

        # Reset random seed
        random.seed()

        logger.info(f"MockProvider: Generated {len(offers)} offers")
        return offers

    def is_available(self) -> bool:
        """Mock provider is always available."""
        return True


class AmadeusProvider(FlightProvider):
    """Amadeus API provider."""

    def __init__(self):
        """Initialize Amadeus provider."""
        self.api_key = settings.amadeus_api_key
        self.api_secret = settings.amadeus_api_secret
        self.base_url = settings.amadeus_base_url
        self._token: Optional[str] = None
        self._token_expires_at: Optional[datetime] = None

    def _get_access_token(self) -> str:
        """Get or refresh access token."""
        # Check if we have a valid cached token
        if self._token and self._token_expires_at:
            if datetime.now() < self._token_expires_at - timedelta(minutes=5):
                return self._token

        # Request new token
        url = f"{self.base_url}/v1/security/oauth2/token"
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {
            "grant_type": "client_credentials",
            "client_id": self.api_key,
            "client_secret": self.api_secret,
        }

        try:
            response = requests.post(url, headers=headers, data=data, timeout=10)
            response.raise_for_status()
            token_data = response.json()

            self._token = token_data["access_token"]
            expires_in = token_data.get("expires_in", 1800)
            self._token_expires_at = datetime.now() + timedelta(seconds=expires_in)

            logger.info("Amadeus: Successfully obtained access token")
            return self._token

        except Exception as e:
            logger.error(f"Amadeus: Failed to get access token: {e}")
            raise

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
        """Search flights via Amadeus API."""
        try:
            token = self._get_access_token()
        except Exception as e:
            logger.error(f"Amadeus: Cannot search, token error: {e}")
            return []

        url = f"{self.base_url}/v2/shopping/flight-offers"
        headers = {"Authorization": f"Bearer {token}"}

        params = {
            "originLocationCode": origin,
            "destinationLocationCode": destination,
            "departureDate": depart_date,
            "adults": 1,
            "currencyCode": currency,
            "max": 10,
            "travelClass": cabin,
        }

        if return_date:
            params["returnDate"] = return_date

        try:
            response = requests.get(url, headers=headers, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()

            offers = []
            for item in data.get("data", []):
                # Parse Amadeus response
                price_data = item.get("price", {})
                price_total = float(price_data.get("total", 0))

                itineraries = item.get("itineraries", [])
                # Get airline from first segment
                airline = None
                total_stops = 0
                if itineraries:
                    segments = itineraries[0].get("segments", [])
                    if segments:
                        airline = segments[0].get("carrierCode")
                        total_stops = len(segments) - 1

                offer = FlightOffer(
                    origin=origin,
                    destination=destination,
                    depart_date=depart_date,
                    return_date=return_date,
                    price_total=price_total,
                    currency=price_data.get("currency", currency),
                    provider="amadeus",
                    airline=airline,
                    stops=total_stops,
                    deep_link=None,  # Amadeus doesn't provide direct booking link in this API
                    raw_data=item,
                )
                offers.append(offer)

            logger.info(f"Amadeus: Found {len(offers)} offers for {origin}->{destination}")
            return offers

        except Exception as e:
            logger.error(f"Amadeus: Search failed: {e}")
            return []

    def is_available(self) -> bool:
        """Check if Amadeus is configured."""
        return bool(self.api_key and self.api_secret)


def get_provider(provider_name: Optional[str] = None) -> FlightProvider:
    """Get flight provider instance."""
    if provider_name is None:
        provider_name = settings.default_provider

    if provider_name == "amadeus":
        amadeus = AmadeusProvider()
        if amadeus.is_available():
            logger.info("Using Amadeus provider")
            return amadeus
        else:
            logger.warning(
                "Amadeus credentials not configured, falling back to MockProvider"
            )
            return MockProvider()

    # Default to mock
    logger.info("Using MockProvider")
    return MockProvider()
