# =============================================================================
# Makefile for Flight Intelligence
# =============================================================================

.PHONY: help up down logs restart build test lint fmt migrate backup restore seed clean

# Default target
help:
	@echo "Flight Intelligence - Make Targets"
	@echo ""
	@echo "  make up             - Start all services"
	@echo "  make down           - Stop all services"
	@echo "  make logs           - View logs (all services)"
	@echo "  make restart        - Restart all services"
	@echo "  make build          - Rebuild Docker images"
	@echo ""
	@echo "  make test           - Run tests"
	@echo "  make lint           - Run linter (ruff)"
	@echo "  make fmt            - Format code (ruff)"
	@echo "  make typecheck      - Run type checking (mypy)"
	@echo ""
	@echo "  make migrate        - Run database migrations"
	@echo "  make migrate-create - Create new migration"
	@echo ""
	@echo "  make backup         - Create database backup"
	@echo "  make restore        - Restore from backup"
	@echo "  make seed           - Seed mock data"
	@echo ""
	@echo "  make clean          - Remove containers and volumes"
	@echo "  make clean-data     - Remove all data (WARNING: destructive)"
	@echo ""
	@echo "Profiles:"
	@echo "  make up-full        - Start with all profiles (llm + observability + alerts)"
	@echo "  make up-obs         - Start with observability"
	@echo "  make up-llm         - Start with LLM agent"

# Service management
up:
	docker compose --profile flight-intel up -d

up-full:
	docker compose --profile flight-intel --profile llm --profile observability --profile alerts up -d

up-obs:
	docker compose --profile flight-intel --profile observability up -d

up-llm:
	docker compose --profile flight-intel --profile llm up -d

down:
	docker compose --profile flight-intel down

logs:
	docker compose --profile flight-intel logs -f

restart:
	docker compose --profile flight-intel restart

build:
	docker compose --profile flight-intel build

# Development
test:
	pytest -v

test-cov:
	pytest --cov=app --cov-report=html --cov-report=term

lint:
	ruff check app/ tests/

fmt:
	ruff format app/ tests/
	ruff check --fix app/ tests/

typecheck:
	mypy app/

quality: lint typecheck test

# Database operations
migrate:
	docker compose run --rm flight-api alembic upgrade head

migrate-create:
	@read -p "Enter migration message: " msg; \
	docker compose run --rm flight-api alembic revision -m "$$msg"

migrate-history:
	docker compose run --rm flight-api alembic history

migrate-current:
	docker compose run --rm flight-api alembic current

# Backup and restore
backup:
	./scripts/backup.sh

restore:
	@echo "Usage: make restore BACKUP=<backup_file>"
	@echo "Example: make restore BACKUP=data/backups/flight_intel_backup_20240111_120000.sql.gz"

restore-file:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Error: BACKUP parameter required"; \
		echo "Usage: make restore-file BACKUP=<backup_file>"; \
		exit 1; \
	fi
	./scripts/restore.sh $(BACKUP)

seed:
	./scripts/seed_mock_data.sh

# Monitoring
metrics:
	curl http://localhost:8000/metrics

health:
	@echo "=== Health Check ==="
	@echo "API:"
	@curl -sf http://localhost:8000/health | jq . || echo "❌ API unhealthy"
	@echo "\nDatabase:"
	@docker exec flight-postgres pg_isready -U flightintel || echo "❌ Database unhealthy"
	@echo "\n=== Status ==="
	@docker compose ps

stats:
	docker stats --no-stream flight-api flight-ui flight-collector flight-postgres

# Cleanup
clean:
	docker compose --profile flight-intel down -v

clean-data:
	@echo "⚠️  WARNING: This will delete ALL data including backups!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		docker compose --profile flight-intel down -v; \
		rm -rf data/postgres/*; \
		echo "✅ All data cleaned"; \
	else \
		echo "Cancelled"; \
	fi

clean-backups:
	@echo "Removing backups older than 30 days..."
	find data/backups/ -name "flight_intel_backup_*.sql.gz" -type f -mtime +30 -delete
	@echo "✅ Old backups cleaned"

# Development setup
dev-setup:
	pip install -e ".[dev]"
	pre-commit install
	@echo "✅ Development environment ready"

dev-run-api:
	export DATABASE_URL=postgresql://flightintel:flightintel@localhost:5432/flightintel && \
	uvicorn app.api.main:app --reload --host 0.0.0.0 --port 8000

dev-run-ui:
	export API_BASE_URL=http://localhost:8000 && \
	streamlit run ui/app.py

# Docker utilities
shell-api:
	docker compose exec flight-api /bin/bash

shell-db:
	docker compose exec flight-postgres psql -U flightintel flightintel

shell-collector:
	docker compose exec flight-collector /bin/bash

# Logs by service
logs-api:
	docker compose logs -f flight-api

logs-ui:
	docker compose logs -f flight-ui

logs-collector:
	docker compose logs -f flight-collector

logs-db:
	docker compose logs -f flight-postgres
