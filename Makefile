# =============================================================================
# Orion-Sentinel-HomeCore Makefile
# =============================================================================
# Convenience targets for common operations
# =============================================================================

.PHONY: help bootstrap up down ps logs restart update doctor clean

SHELL := /bin/bash

# Default target
help:
	@echo "Orion-Sentinel-HomeCore Management"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  bootstrap   Run the bootstrap script to prepare the environment"
	@echo "  up          Start all services (or use STACK=name)"
	@echo "  down        Stop all services (or use STACK=name)"
	@echo "  ps          Show running services"
	@echo "  logs        Show logs (use SERVICE=name for specific service)"
	@echo "  restart     Restart services"
	@echo "  update      Pull latest images and restart"
	@echo "  doctor      Run health checks"
	@echo "  clean       Remove stopped containers and unused images"
	@echo ""
	@echo "Examples:"
	@echo "  make up                      # Start core services"
	@echo "  make up STACK=homeauto       # Start home automation stack"
	@echo "  make logs SERVICE=homeassistant"
	@echo ""

# Bootstrap the environment
bootstrap:
	@./scripts/bootstrap-homecore.sh

# Start services
up:
ifdef STACK
	@./scripts/orionctl up $(STACK)
else ifdef PROFILE
	@./scripts/orionctl up --profile $(PROFILE)
else
	@./scripts/orionctl up
endif

# Stop services
down:
ifdef STACK
	@./scripts/orionctl down $(STACK)
else
	@./scripts/orionctl down
endif

# Show service status
ps:
	@./scripts/orionctl ps

# Show logs
logs:
ifdef SERVICE
	@./scripts/orionctl logs $(SERVICE)
else
	@docker compose logs -f
endif

# Restart services
restart:
ifdef STACK
	@./scripts/orionctl restart $(STACK)
else
	@./scripts/orionctl restart
endif

# Update images
update:
	@./scripts/orionctl update

# Run doctor
doctor:
	@./scripts/orionctl doctor

# Clean up Docker resources
clean:
	@echo "Removing stopped containers..."
	@docker container prune -f
	@echo "Removing unused images..."
	@docker image prune -f
	@echo "Done!"
