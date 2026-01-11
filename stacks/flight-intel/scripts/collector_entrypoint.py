#!/usr/bin/env python3
"""Collector entrypoint with scheduling."""

import logging
import sys
import time
from datetime import datetime

from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger

# Add app to path
sys.path.insert(0, "/app")

from app.collector import run_collector_once
from app.config import settings

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logger = logging.getLogger(__name__)


def run_scheduled_collection():
    """Run collection with exception handling."""
    logger.info("=== Starting scheduled collection ===")
    try:
        result = run_collector_once()
        logger.info(f"Collection completed: {result}")
    except Exception as e:
        logger.error(f"Collection failed: {e}", exc_info=True)


def main():
    """Main collector entrypoint."""
    if not settings.collector_enabled:
        logger.warning("Collector is disabled (COLLECTOR_ENABLED=false). Sleeping indefinitely...")
        # Sleep forever to keep container running
        while True:
            time.sleep(3600)
        return

    logger.info("Flight Intelligence Collector starting...")
    logger.info(f"Schedule: {settings.collector_schedule}")

    # Create scheduler
    scheduler = BlockingScheduler()

    # Parse cron schedule
    try:
        # Schedule format: "minute hour day month day_of_week"
        # Default: "0 3 * * *" (daily at 3:00 AM)
        trigger = CronTrigger.from_crontab(settings.collector_schedule)
        scheduler.add_job(
            run_scheduled_collection,
            trigger=trigger,
            id="flight_collector",
            name="Flight Price Collection",
            replace_existing=True,
        )
        logger.info(f"Collector scheduled: {trigger}")

        # Run once immediately on startup
        logger.info("Running initial collection on startup...")
        run_scheduled_collection()

        # Start scheduler
        logger.info("Collector scheduler started. Press Ctrl+C to exit.")
        scheduler.start()

    except Exception as e:
        logger.error(f"Failed to start collector: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
