"""FastAPI application for flight intelligence."""

import logging
from datetime import datetime
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from app.agent import agent
from app.collector import run_collector_once
from app.config import settings
from app.db import DailyBest, PriceSnapshot, Recommendation, Route, SessionLocal, get_db
from app.metrics import api_requests, get_metrics
from app.reco import get_recommendation
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Flight Intelligence API",
    description="Flight price intelligence and recommendation system",
    version="0.1.0",
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_api_key(x_api_key: Optional[str] = Header(None)) -> None:
    """Verify API key for protected endpoints."""
    if x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")


@app.get("/health")
def health_check():
    """Health check endpoint."""
    try:
        # Check database connection
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()

        api_requests.labels(method="GET", endpoint="/health", status="200").inc()

        return {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "service": "flight-intel-api",
        }
    except Exception as e:
        api_requests.labels(method="GET", endpoint="/health", status="500").inc()
        raise HTTPException(status_code=500, detail=f"Unhealthy: {str(e)}")


@app.get("/routes")
def list_routes(db: Session = Depends(get_db)):
    """List all configured routes."""
    routes = db.query(Route).filter(Route.active == True).all()

    api_requests.labels(method="GET", endpoint="/routes", status="200").inc()

    return {
        "routes": [
            {
                "id": r.id,
                "origin": r.origin_airport,
                "destination": r.dest_airport,
                "active": r.active,
            }
            for r in routes
        ]
    }


@app.get("/offers/best")
def get_best_offers(
    origins: Optional[str] = Query(None, description="Comma-separated origin airports"),
    destinations: Optional[str] = Query(None, description="Comma-separated destination airports"),
    depart_date_start: Optional[str] = Query(None, description="Start of departure date range (YYYY-MM-DD)"),
    depart_date_end: Optional[str] = Query(None, description="End of departure date range (YYYY-MM-DD)"),
    min_stay: Optional[int] = Query(None, description="Minimum stay days"),
    max_stay: Optional[int] = Query(None, description="Maximum stay days"),
    limit: int = Query(50, description="Maximum number of results"),
    db: Session = Depends(get_db),
):
    """Get best flight offers with filters."""
    query = db.query(PriceSnapshot).order_by(PriceSnapshot.price_total.asc())

    if origins:
        origin_list = [o.strip() for o in origins.split(",")]
        query = query.filter(PriceSnapshot.origin.in_(origin_list))

    if destinations:
        dest_list = [d.strip() for d in destinations.split(",")]
        query = query.filter(PriceSnapshot.destination.in_(dest_list))

    if depart_date_start:
        query = query.filter(PriceSnapshot.depart_date >= depart_date_start)

    if depart_date_end:
        query = query.filter(PriceSnapshot.depart_date <= depart_date_end)

    if min_stay:
        query = query.filter(PriceSnapshot.stay_days >= min_stay)

    if max_stay:
        query = query.filter(PriceSnapshot.stay_days <= max_stay)

    offers = query.limit(limit).all()

    api_requests.labels(method="GET", endpoint="/offers/best", status="200").inc()

    return {
        "count": len(offers),
        "offers": [
            {
                "id": o.id,
                "origin": o.origin,
                "destination": o.destination,
                "depart_date": o.depart_date,
                "return_date": o.return_date,
                "stay_days": o.stay_days,
                "price": o.price_total,
                "currency": o.currency,
                "airline": o.airline,
                "stops": o.stops,
                "provider": o.provider,
                "collected_at": o.collected_at.isoformat() if o.collected_at else None,
            }
            for o in offers
        ],
    }


@app.get("/history")
def get_price_history(
    origin: str = Query(..., description="Origin airport code"),
    destination: str = Query(..., description="Destination airport code"),
    depart_date: str = Query(..., description="Departure date (YYYY-MM-DD)"),
    return_date: Optional[str] = Query(None, description="Return date (YYYY-MM-DD)"),
    stay_days: Optional[int] = Query(None, description="Stay duration in days"),
    db: Session = Depends(get_db),
):
    """Get price history for a specific route and dates."""
    query = db.query(
        func.date(PriceSnapshot.collected_at).label("date"),
        func.min(PriceSnapshot.price_total).label("min_price"),
        func.avg(PriceSnapshot.price_total).label("avg_price"),
        func.count(PriceSnapshot.id).label("sample_count"),
    ).filter(
        and_(
            PriceSnapshot.origin == origin,
            PriceSnapshot.destination == destination,
            PriceSnapshot.depart_date == depart_date,
        )
    )

    if return_date:
        query = query.filter(PriceSnapshot.return_date == return_date)

    if stay_days:
        query = query.filter(PriceSnapshot.stay_days == stay_days)

    results = query.group_by(func.date(PriceSnapshot.collected_at)).order_by(
        func.date(PriceSnapshot.collected_at)
    ).all()

    api_requests.labels(method="GET", endpoint="/history", status="200").inc()

    return {
        "origin": origin,
        "destination": destination,
        "depart_date": depart_date,
        "return_date": return_date,
        "stay_days": stay_days,
        "history": [
            {
                "date": r.date.isoformat(),
                "min_price": round(r.min_price, 2),
                "avg_price": round(r.avg_price, 2),
                "sample_count": r.sample_count,
            }
            for r in results
        ],
    }


@app.get("/recommendation")
def get_recommendation_endpoint(
    origin: str = Query(..., description="Origin airport code"),
    destination: str = Query(..., description="Destination airport code"),
    depart_date: str = Query(..., description="Departure date (YYYY-MM-DD)"),
    return_date: Optional[str] = Query(None, description="Return date (YYYY-MM-DD)"),
    stay_days: Optional[int] = Query(None, description="Stay duration in days"),
    current_price: Optional[float] = Query(None, description="Current price to evaluate"),
    db: Session = Depends(get_db),
):
    """Get buy/wait recommendation for a route."""
    try:
        recommendation = get_recommendation(
            origin=origin,
            destination=destination,
            depart_date=depart_date,
            return_date=return_date,
            current_price=current_price,
            stay_days=stay_days,
        )

        api_requests.labels(method="GET", endpoint="/recommendation", status="200").inc()

        return recommendation

    except Exception as e:
        logger.error(f"Error generating recommendation: {e}")
        api_requests.labels(method="GET", endpoint="/recommendation", status="500").inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/collect/trigger")
def trigger_collection(api_key_verified: None = Depends(verify_api_key)):
    """Trigger a manual collection run (protected endpoint)."""
    try:
        result = run_collector_once()
        api_requests.labels(method="POST", endpoint="/collect/trigger", status="200").inc()
        return result
    except Exception as e:
        logger.error(f"Collection trigger failed: {e}")
        api_requests.labels(method="POST", endpoint="/collect/trigger", status="500").inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics", response_class=PlainTextResponse)
def metrics():
    """Prometheus metrics endpoint."""
    return get_metrics().decode("utf-8")


class AgentQuery(BaseModel):
    """Agent query request."""

    question: str


@app.post("/agent/query")
def agent_query(query: AgentQuery):
    """Query the LLM-powered flight assistant."""
    try:
        result = agent.query(query.question)
        api_requests.labels(method="POST", endpoint="/agent/query", status="200").inc()
        return result
    except Exception as e:
        logger.error(f"Agent query failed: {e}")
        api_requests.labels(method="POST", endpoint="/agent/query", status="500").inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
def root():
    """Root endpoint."""
    return {
        "service": "Flight Intelligence API",
        "version": "0.1.0",
        "docs": "/docs",
        "health": "/health",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=settings.api_host, port=settings.api_port)
