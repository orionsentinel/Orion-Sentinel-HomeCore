"""Unit tests for recommendation engine."""

import pytest
from datetime import datetime, timedelta

from app.reco import RecommendationEngine


def test_trend_calculation():
    """Test price trend calculation."""
    engine = RecommendationEngine()
    
    # Downward trend
    history_down = [
        (datetime.now() - timedelta(days=10), 300.0),
        (datetime.now() - timedelta(days=7), 280.0),
        (datetime.now() - timedelta(days=5), 270.0),
        (datetime.now() - timedelta(days=2), 260.0),
    ]
    
    trend = engine.calculate_trend(history_down)
    assert trend < 0  # Should be negative (downward)
    
    # Upward trend
    history_up = [
        (datetime.now() - timedelta(days=10), 250.0),
        (datetime.now() - timedelta(days=7), 270.0),
        (datetime.now() - timedelta(days=5), 280.0),
        (datetime.now() - timedelta(days=2), 300.0),
    ]
    
    trend = engine.calculate_trend(history_up)
    assert trend > 0  # Should be positive (upward)


def test_recommendation_no_history():
    """Test recommendation when no historical data available."""
    engine = RecommendationEngine()
    
    # Mock get_price_history to return empty list
    original_method = engine.get_price_history
    engine.get_price_history = lambda *args, **kwargs: []
    
    recommendation = engine.generate_recommendation(
        origin="AMS",
        destination="HER",
        depart_date="2024-06-15",
        return_date="2024-06-22",
        current_price=299.99,
    )
    
    # Restore original method
    engine.get_price_history = original_method
    
    # Should default to WAIT with low confidence
    assert recommendation["action"] == "WAIT"
    assert recommendation["confidence"] < 0.5
    assert "No historical data" in recommendation["rationale"]["reason"]


def test_recommendation_structure():
    """Test that recommendation has expected structure."""
    engine = RecommendationEngine()
    
    # Create mock history
    history = [
        (datetime.now() - timedelta(days=30), 350.0),
        (datetime.now() - timedelta(days=20), 320.0),
        (datetime.now() - timedelta(days=10), 300.0),
        (datetime.now() - timedelta(days=5), 280.0),
    ]
    
    # Mock get_price_history
    engine.get_price_history = lambda *args, **kwargs: history
    
    recommendation = engine.generate_recommendation(
        origin="AMS",
        destination="HER",
        depart_date="2024-06-15",
        return_date="2024-06-22",
        current_price=270.0,
    )
    
    # Check structure
    assert "action" in recommendation
    assert "confidence" in recommendation
    assert "current_price" in recommendation
    assert "rationale" in recommendation
    assert recommendation["action"] in ["BUY", "WAIT", "HOLD"]
    assert 0 <= recommendation["confidence"] <= 1.0
