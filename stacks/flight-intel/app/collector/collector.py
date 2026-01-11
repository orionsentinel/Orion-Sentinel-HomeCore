"""Flight data collector service."""

import logging
import time
from datetime import datetime, timedelta
from typing import List, Tuple

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert

from app.config import settings
from app.db import DailyBest, PriceSnapshot, SearchConfig, SessionLocal
from app.metrics import (
    collection_duration,
    collection_runs,
    provider_errors,
    snapshots_collected,
)
from app.providers import FlightOffer, get_provider

logger = logging.getLogger(__name__)


class Collector:
    """Flight price collector."""

    def __init__(self):
        """Initialize collector."""
        self.provider = get_provider()
        self.batch_size = settings.collector_batch_size
        self.timeout = settings.collector_timeout_seconds

    def generate_date_pairs(
        self, start_date: str, end_date: str, min_stay: int, max_stay: int
    ) -> List[Tuple[str, str]]:
        """Generate (depart_date, return_date) pairs."""
        pairs = []
        start = datetime.strptime(start_date, "%Y-%m-%d")
        end = datetime.strptime(end_date, "%Y-%m-%d")

        current = start
        while current <= end:
            # For each depart date, generate return dates based on stay
            for stay_days in range(min_stay, max_stay + 1):
                return_date = current + timedelta(days=stay_days)
                if return_date <= end + timedelta(days=max_stay):
                    pairs.append(
                        (
                            current.strftime("%Y-%m-%d"),
                            return_date.strftime("%Y-%m-%d"),
                        )
                    )

            # Move to next depart date (e.g., every 3 days to reduce API calls)
            current += timedelta(days=3)

        return pairs

    def store_offers(self, offers: List[FlightOffer]) -> int:
        """Store offers in database, return number of new rows inserted."""
        if not offers:
            return 0

        db = SessionLocal()
        try:
            new_count = 0
            for offer in offers:
                # Use INSERT ... ON CONFLICT DO NOTHING for idempotency
                stmt = insert(PriceSnapshot).values(**offer.to_dict())
                stmt = stmt.on_conflict_do_nothing(index_elements=["hash"])

                result = db.execute(stmt)
                db.commit()

                if result.rowcount > 0:
                    new_count += 1
                    # Update metrics
                    snapshots_collected.labels(
                        provider=offer.provider,
                        origin=offer.origin,
                        destination=offer.destination,
                    ).inc()

            logger.info(f"Stored {new_count} new snapshots out of {len(offers)} offers")
            return new_count

        except Exception as e:
            logger.error(f"Error storing offers: {e}")
            db.rollback()
            return 0
        finally:
            db.close()

    def update_daily_best(self) -> None:
        """Update daily best prices from snapshots."""
        db = SessionLocal()
        try:
            # Get today's date bucket
            today = datetime.now().strftime("%Y-%m-%d")

            # Find best prices for each route/date combination from recent snapshots
            # This is a simplified version; production might use a more sophisticated query
            recent_cutoff = datetime.now() - timedelta(days=1)

            subquery = (
                db.query(
                    PriceSnapshot.origin,
                    PriceSnapshot.destination,
                    PriceSnapshot.depart_date,
                    PriceSnapshot.return_date,
                    PriceSnapshot.stay_days,
                    func.min(PriceSnapshot.price_total).label("best_price"),
                    PriceSnapshot.provider,
                )
                .filter(PriceSnapshot.collected_at >= recent_cutoff)
                .group_by(
                    PriceSnapshot.origin,
                    PriceSnapshot.destination,
                    PriceSnapshot.depart_date,
                    PriceSnapshot.return_date,
                    PriceSnapshot.stay_days,
                    PriceSnapshot.provider,
                )
                .all()
            )

            for row in subquery:
                stmt = insert(DailyBest).values(
                    date_bucket=today,
                    origin=row.origin,
                    destination=row.destination,
                    depart_date=row.depart_date,
                    return_date=row.return_date,
                    stay_days=row.stay_days,
                    best_price=row.best_price,
                    provider=row.provider,
                )
                stmt = stmt.on_conflict_do_update(
                    constraint="uq_daily_best",
                    set_={"best_price": row.best_price, "updated_at": datetime.utcnow()},
                )
                db.execute(stmt)

            db.commit()
            logger.info("Updated daily best prices")

        except Exception as e:
            logger.error(f"Error updating daily best: {e}")
            db.rollback()
        finally:
            db.close()

    def run_collection(self) -> dict:
        """Run a single collection cycle."""
        start_time = time.time()
        logger.info("Starting collection run")

        try:
            # Get active search configs
            db = SessionLocal()
            configs = db.query(SearchConfig).filter(SearchConfig.active == True).all()
            db.close()

            if not configs:
                logger.warning("No active search configs found")
                collection_runs.labels(status="no_configs").inc()
                return {
                    "status": "no_configs",
                    "message": "No active search configurations",
                }

            total_routes = 0
            total_offers = 0
            total_new_snapshots = 0

            for config in configs:
                logger.info(f"Processing search config: {config.name}")

                # Generate date pairs
                date_pairs = self.generate_date_pairs(
                    config.start_date,
                    config.end_date,
                    config.min_stay_days,
                    config.max_stay_days,
                )

                # Search each origin-destination-date combination
                for origin in config.origins:
                    for destination in config.destinations:
                        for depart_date, return_date in date_pairs:
                            total_routes += 1

                            try:
                                offers = self.provider.search_flights(
                                    origin=origin,
                                    destination=destination,
                                    depart_date=depart_date,
                                    return_date=return_date,
                                    cabin=config.cabin,
                                    max_stops=config.max_stops,
                                    currency=config.currency,
                                )

                                total_offers += len(offers)
                                new_count = self.store_offers(offers)
                                total_new_snapshots += new_count

                                # Rate limiting: small delay between requests
                                time.sleep(0.5)

                            except Exception as e:
                                logger.error(
                                    f"Error searching {origin}->{destination} "
                                    f"{depart_date}/{return_date}: {e}"
                                )
                                provider_errors.labels(provider=self.provider.__class__.__name__).inc()

            # Update daily best after collection
            self.update_daily_best()

            duration = time.time() - start_time
            collection_duration.observe(duration)
            collection_runs.labels(status="success").inc()

            result = {
                "status": "success",
                "routes_searched": total_routes,
                "offers_collected": total_offers,
                "new_snapshots": total_new_snapshots,
                "duration_seconds": round(duration, 2),
            }

            logger.info(
                f"Collection completed: {total_routes} routes, "
                f"{total_offers} offers, {total_new_snapshots} new snapshots, "
                f"{duration:.2f}s"
            )

            return result

        except Exception as e:
            logger.error(f"Collection run failed: {e}")
            collection_runs.labels(status="error").inc()
            return {
                "status": "error",
                "message": str(e),
            }


def run_collector_once() -> dict:
    """Run collector once (for manual trigger or testing)."""
    collector = Collector()
    return collector.run_collection()
