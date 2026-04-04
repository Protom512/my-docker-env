# Docker Environment

This repository contains Docker configurations for various development environments.

## Overview

This project provides Dockerized environments for development and testing purposes. Currently includes:

- **SAP ASE**: Docker image for SAP Adaptive Server Enterprise 16

## Project Structure

```text
.
├── .devcontainer/          # VS Code dev container configurations
│   └── devcontainer.json   # VS Code dev container settings
├── .github/                # GitHub Actions workflows
│   └── workflows/          # CI/CD pipelines
│       ├── ase.yaml        # ASE build workflow
│       └── docker-build-push.yml  # Reusable build workflow
├── ase/                    # SAP ASE Docker image
│   ├── Dockerfile          # ASE Docker image
│   ├── entrypoint.sh       # Container entry point script
│   ├── sap-response.txt    # SAP installer response file
│   └── README.md           # ASE documentation and build instructions
├── tests/                  # Integration tests
│   └── ase-test.sh         # ASE integration tests
├── Makefile                # Convenient commands
└── README.md               # This file
```

## Getting Started

Each environment has its own README with detailed build and usage instructions:

- **SAP ASE**: See [ase/README.md](ase/README.md) for build instructions, configuration options, and troubleshooting

## Development

### Prerequisites

- Docker
- Bash shell
- (Optional) Make utility

### Dev Container

This project includes dev container configurations for VS Code.

To use a dev container:
1. Open the project in VS Code
2. Install the "Dev Containers" extension
3. Press F1 and select "Dev Containers: Reopen in Container"

### Common Commands

```bash
# Build all images
make build

# Run all tests
make test

# Run shellcheck on scripts
make lint

# Format shell scripts
make format

# Clean up images and containers
make clean
```

For detailed command reference, see the Makefile help:
```bash
make help
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## CI/CD

This project uses GitHub Actions for automated builds:

- **ase.yaml**: Scheduled monthly builds and manual triggers for ASE
- **docker-build-push.yml**: Reusable workflow for building and pushing to GHCR

## Support

For environment-specific issues, refer to the individual README files:

- **SAP ASE**: See [ase/README.md](ase/README.md) for ASE-specific documentation and troubleshooting
- **General issues**: Open an issue in this repository
