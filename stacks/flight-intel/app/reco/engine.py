"""Recommendation engine for buy/wait decisions."""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import numpy as np
from sqlalchemy import and_, func

from app.config import settings
from app.db import PriceSnapshot, Recommendation, SessionLocal
from app.metrics import recommendations_generated

logger = logging.getLogger(__name__)


class RecommendationEngine:
    """Rules-based recommendation engine."""

    def __init__(self):
        """Initialize recommendation engine."""
        self.history_window_days = settings.reco_history_window_days
        self.buy_margin = settings.reco_buy_margin
        self.median_discount = settings.reco_median_discount
        self.trend_threshold = settings.reco_trend_threshold

    def get_price_history(
        self,
        origin: str,
        destination: str,
        depart_date: str,
        return_date: Optional[str],
        stay_days: Optional[int] = None,
    ) -> List[Tuple[datetime, float]]:
        """Get historical prices for a route."""
        db = SessionLocal()
        try:
            cutoff = datetime.now() - timedelta(days=self.history_window_days)

            query = db.query(
                PriceSnapshot.collected_at, func.min(PriceSnapshot.price_total).label("price")
            ).filter(
                and_(
                    PriceSnapshot.origin == origin,
                    PriceSnapshot.destination == destination,
                    PriceSnapshot.depart_date == depart_date,
                    PriceSnapshot.collected_at >= cutoff,
                )
            )

            if return_date:
                query = query.filter(PriceSnapshot.return_date == return_date)
            if stay_days:
                query = query.filter(PriceSnapshot.stay_days == stay_days)

            query = query.group_by(
                func.date(PriceSnapshot.collected_at), PriceSnapshot.collected_at
            ).order_by(PriceSnapshot.collected_at)

            results = query.all()
            return [(r.collected_at, r.price) for r in results]

        finally:
            db.close()

    def calculate_trend(self, history: List[Tuple[datetime, float]]) -> float:
        """Calculate price trend using simple linear regression."""
        if len(history) < 2:
            return 0.0

        # Convert to arrays
        dates = np.array([(d - history[0][0]).days for d, _ in history])
        prices = np.array([p for _, p in history])

        # Simple linear regression
        if len(dates) == 0 or np.std(dates) == 0:
            return 0.0

        slope = np.polyfit(dates, prices, 1)[0]
        return slope

    def generate_recommendation(
        self,
        origin: str,
        destination: str,
        depart_date: str,
        return_date: Optional[str],
        current_price: float,
        stay_days: Optional[int] = None,
    ) -> Dict:
        """Generate buy/wait recommendation."""
        # Get price history
        history = self.get_price_history(origin, destination, depart_date, return_date, stay_days)

        if not history:
            # No historical data, default to WAIT with low confidence
            return {
                "action": "WAIT",
                "confidence": 0.3,
                "current_price": current_price,
                "threshold_price": None,
                "rationale": {
                    "reason": "No historical data available",
                    "recommendation": "Wait and monitor prices",
                },
            }

        prices = [p for _, p in history]
        rolling_min = min(prices)
        rolling_median = float(np.median(prices))
        rolling_std = float(np.std(prices))
        trend_slope = self.calculate_trend(history)

        # Calculate thresholds
        buy_threshold_min = rolling_min * (1 + self.buy_margin)
        buy_threshold_median = rolling_median * (1 - self.median_discount)

        # Decision logic
        action = "WAIT"
        confidence = 0.5
        rationale = {}

        # BUY conditions
        if current_price <= buy_threshold_min:
            action = "BUY"
            confidence = 0.9
            rationale = {
                "reason": f"Current price (€{current_price:.2f}) is within {self.buy_margin*100}% of historical minimum (€{rolling_min:.2f})",
                "rolling_min": round(rolling_min, 2),
                "rolling_median": round(rolling_median, 2),
                "threshold": round(buy_threshold_min, 2),
            }
        elif current_price <= buy_threshold_median:
            action = "BUY"
            confidence = 0.75
            rationale = {
                "reason": f"Current price (€{current_price:.2f}) is {self.median_discount*100}% below median (€{rolling_median:.2f})",
                "rolling_min": round(rolling_min, 2),
                "rolling_median": round(rolling_median, 2),
                "threshold": round(buy_threshold_median, 2),
            }
        # WAIT conditions
        elif trend_slope < self.trend_threshold and current_price > rolling_median:
            action = "WAIT"
            confidence = 0.7
            rationale = {
                "reason": f"Price trend is downward (slope: {trend_slope:.2f}), current price (€{current_price:.2f}) above median (€{rolling_median:.2f})",
                "trend": "downward",
                "rolling_median": round(rolling_median, 2),
                "recommendation": "Wait for prices to drop further",
            }
        else:
            action = "HOLD"
            confidence = 0.5
            rationale = {
                "reason": f"Current price (€{current_price:.2f}) is near median (€{rolling_median:.2f}), no strong signal",
                "rolling_min": round(rolling_min, 2),
                "rolling_median": round(rolling_median, 2),
                "volatility": round(rolling_std, 2),
                "recommendation": "Monitor for better opportunities",
            }

        # Calculate days to departure
        try:
            depart = datetime.strptime(depart_date, "%Y-%m-%d")
            days_to_depart = (depart - datetime.now()).days
            rationale["days_to_departure"] = days_to_depart

            # Adjust confidence based on time pressure
            if days_to_depart < 14 and action == "WAIT":
                rationale[
                    "time_warning"
                ] = "Less than 2 weeks until departure, prices may increase"
                confidence *= 0.8
        except Exception:
            pass

        return {
            "action": action,
            "confidence": round(confidence, 2),
            "current_price": current_price,
            "threshold_price": round(buy_threshold_min, 2) if action == "BUY" else None,
            "rationale": rationale,
        }

    def save_recommendation(
        self,
        origin: str,
        destination: str,
        depart_date: str,
        return_date: Optional[str],
        stay_days: Optional[int],
        recommendation: Dict,
    ) -> None:
        """Save recommendation to database."""
        db = SessionLocal()
        try:
            rec = Recommendation(
                origin=origin,
                destination=destination,
                depart_date=depart_date,
                return_date=return_date,
                stay_days=stay_days,
                action=recommendation["action"],
                confidence=recommendation["confidence"],
                threshold_price=recommendation.get("threshold_price"),
                current_price=recommendation["current_price"],
                rationale=recommendation["rationale"],
            )
            db.add(rec)
            db.commit()

            recommendations_generated.labels(action=recommendation["action"]).inc()

            logger.info(
                f"Saved recommendation: {origin}->{destination} {depart_date}: "
                f"{recommendation['action']} (confidence: {recommendation['confidence']})"
            )

        except Exception as e:
            logger.error(f"Error saving recommendation: {e}")
            db.rollback()
        finally:
            db.close()


def get_recommendation(
    origin: str,
    destination: str,
    depart_date: str,
    return_date: Optional[str] = None,
    current_price: Optional[float] = None,
    stay_days: Optional[int] = None,
) -> Dict:
    """Get recommendation for a route (convenience function)."""
    engine = RecommendationEngine()

    # If current price not provided, get latest from DB
    if current_price is None:
        db = SessionLocal()
        try:
            latest = (
                db.query(func.min(PriceSnapshot.price_total))
                .filter(
                    and_(
                        PriceSnapshot.origin == origin,
                        PriceSnapshot.destination == destination,
                        PriceSnapshot.depart_date == depart_date,
                    )
                )
                .scalar()
            )
            if latest:
                current_price = latest
            else:
                return {
                    "error": "No price data available for this route",
                    "action": "WAIT",
                    "confidence": 0.0,
                }
        finally:
            db.close()

    recommendation = engine.generate_recommendation(
        origin, destination, depart_date, return_date, current_price, stay_days
    )

    # Save to database
    engine.save_recommendation(
        origin, destination, depart_date, return_date, stay_days, recommendation
    )

    return recommendation
