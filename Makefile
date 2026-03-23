# Makefile for ASE Docker Image Project
# Provides convenient commands for building, testing, and managing ASE containers

.PHONY: all build test clean help shell logs stop

# Default target
all: build

# Variables
IMAGE_NAME := ase
IMAGE_TAG := latest
CONTAINER_NAME := ase-dev
ASE_PORT := 5000
ASE_SA_PASSWORD ?= TestPassword123

# Build the ASE Docker image
build:
	@echo "Building ASE Docker image..."
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) ./ase

# Run tests
test: build
	@echo "Running ASE integration tests..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) ASE_SA_PASSWORD=$(ASE_SA_PASSWORD) \
		bash tests/ase-test.sh

# Quick test - build and run container
test-quick: build
	@echo "Starting ASE container for quick test..."
	docker run -d --name $(CONTAINER_NAME) \
		-p $(ASE_PORT):5000 \
		-e ASE_SA_PASSWORD=$(ASE_SA_PASSWORD) \
		$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Container started. Use 'make logs' to view logs."
	@echo "Use 'make stop' to stop the container."

# Start a shell in the container
shell:
	@echo "Starting shell in container..."
	docker exec -it $(CONTAINER_NAME) bash

# View container logs
logs:
	docker logs -f $(CONTAINER_NAME)

# Stop and remove the container
stop:
	@echo "Stopping container..."
	-docker stop $(CONTAINER_NAME)
	-docker rm $(CONTAINER_NAME)

# Clean up build artifacts and containers
clean: stop
	@echo "Cleaning up..."
	-docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "Cleanup complete."

# Run shellcheck on shell scripts
lint:
	@echo "Running shellcheck..."
	shellcheck ase/entrypoint.sh tests/ase-test.sh

# Format shell scripts
format:
	@echo "Formatting shell scripts..."
	shfmt -w ase/entrypoint.sh tests/ase-test.sh

# Show help
help:
	@echo "ASE Docker Image - Available commands:"
	@echo ""
	@echo "  make build      - Build the ASE Docker image"
	@echo "  make test       - Run integration tests"
	@echo "  make test-quick - Quick test (build and start container)"
	@echo "  make shell      - Start shell in running container"
	@echo "  make logs       - View container logs"
	@echo "  make stop       - Stop and remove container"
	@echo "  make clean      - Clean up images and containers"
	@echo "  make lint       - Run shellcheck on scripts"
	@echo "  make format     - Format shell scripts"
	@echo "  make help       - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  IMAGE_NAME      - Docker image name (default: ase)"
	@echo "  IMAGE_TAG       - Docker image tag (default: latest)"
	@echo "  CONTAINER_NAME  - Container name (default: ase-dev)"
	@echo "  ASE_PORT        - ASE port (default: 5000)"
	@echo "  ASE_SA_PASSWORD - SA password (default: TestPassword123)"
	@echo ""
	@echo "Example:"
	@echo "  make ASE_SA_PASSWORD=MyPassword123 test"
