"""Database models and session management."""

from datetime import datetime
from typing import Optional

from sqlalchemy import (
    JSON,
    TIMESTAMP,
    Boolean,
    Column,
    Float,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    create_engine,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    """Base class for all models."""

    pass


class Route(Base):
    """Flight route configuration."""

    __tablename__ = "routes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    origin_airport = Column(String(3), nullable=False, index=True)
    dest_airport = Column(String(3), nullable=False, index=True)
    active = Column(Boolean, default=True, nullable=False)
    created_at = Column(TIMESTAMP, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        Index("idx_route_active", "origin_airport", "dest_airport", "active"),
        UniqueConstraint("origin_airport", "dest_airport", name="uq_route"),
    )


class SearchConfig(Base):
    """Search configuration for automated collection."""

    __tablename__ = "search_configs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False, unique=True)
    origins = Column(ARRAY(String), nullable=False)
    destinations = Column(ARRAY(String), nullable=False)
    start_date = Column(String(10), nullable=False)  # YYYY-MM-DD
    end_date = Column(String(10), nullable=False)  # YYYY-MM-DD
    min_stay_days = Column(Integer, nullable=False)
    max_stay_days = Column(Integer, nullable=False)
    cabin = Column(String(20), default="ECONOMY")
    max_stops = Column(Integer, default=2)
    currency = Column(String(3), default="EUR")
    active = Column(Boolean, default=True, nullable=False)
    created_at = Column(TIMESTAMP, default=datetime.utcnow, nullable=False)


class PriceSnapshot(Base):
    """Price snapshot from provider."""

    __tablename__ = "price_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    collected_at = Column(TIMESTAMP, default=datetime.utcnow, nullable=False, index=True)
    provider = Column(String(50), nullable=False, index=True)
    origin = Column(String(3), nullable=False, index=True)
    destination = Column(String(3), nullable=False, index=True)
    depart_date = Column(String(10), nullable=False, index=True)  # YYYY-MM-DD
    return_date = Column(String(10), nullable=True, index=True)  # YYYY-MM-DD or NULL for one-way
    stay_days = Column(Integer, nullable=True)
    price_total = Column(Float, nullable=False)
    currency = Column(String(3), nullable=False)
    airline = Column(String(50), nullable=True)
    stops = Column(Integer, nullable=True)
    deep_link = Column(Text, nullable=True)
    raw_json = Column(JSON, nullable=True)
    hash = Column(String(64), unique=True, nullable=False, index=True)

    __table_args__ = (
        Index("idx_snapshot_route_date", "origin", "destination", "depart_date", "return_date"),
        Index("idx_snapshot_collected", "collected_at", "provider"),
        Index("idx_snapshot_price", "origin", "destination", "price_total"),
    )


class DailyBest(Base):
    """Daily best price aggregation."""

    __tablename__ = "daily_best"

    id = Column(Integer, primary_key=True, autoincrement=True)
    date_bucket = Column(String(10), nullable=False, index=True)  # YYYY-MM-DD
    origin = Column(String(3), nullable=False, index=True)
    destination = Column(String(3), nullable=False, index=True)
    depart_date = Column(String(10), nullable=False, index=True)
    return_date = Column(String(10), nullable=True)
    stay_days = Column(Integer, nullable=True)
    best_price = Column(Float, nullable=False)
    provider = Column(String(50), nullable=False)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    __table_args__ = (
        Index(
            "idx_daily_best_lookup",
            "origin",
            "destination",
            "depart_date",
            "return_date",
            "date_bucket",
        ),
        UniqueConstraint(
            "date_bucket",
            "origin",
            "destination",
            "depart_date",
            "return_date",
            name="uq_daily_best",
        ),
    )


class Recommendation(Base):
    """Buy/wait recommendations."""

    __tablename__ = "recommendations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    created_at = Column(TIMESTAMP, default=datetime.utcnow, nullable=False, index=True)
    origin = Column(String(3), nullable=False, index=True)
    destination = Column(String(3), nullable=False, index=True)
    depart_date = Column(String(10), nullable=False)
    return_date = Column(String(10), nullable=True)
    stay_days = Column(Integer, nullable=True)
    action = Column(String(10), nullable=False)  # BUY, WAIT, HOLD
    confidence = Column(Float, nullable=False)  # 0.0 to 1.0
    threshold_price = Column(Float, nullable=True)
    current_price = Column(Float, nullable=False)
    rationale = Column(JSON, nullable=True)

    __table_args__ = (Index("idx_reco_lookup", "origin", "destination", "depart_date", "return_date"),)


# Database engine and session
engine = create_engine(settings.database_url, pool_pre_ping=True, echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Session:
    """Get database session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Initialize database (create tables)."""
    Base.metadata.create_all(bind=engine)
