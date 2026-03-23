# ASE Docker Image

Docker image for SAP Adaptive Server Enterprise (ASE) 16.

## Overview

This project provides a Docker image for SAP ASE 16 (formerly Sybase ASE), based on Red Hat Universal Base Image (UBI) 9.

## Features

- **Multi-stage build**: Optimized image size using multi-stage Docker build
- **Configurable**: Environment variables for easy customization
- **Production-ready**: Proper error handling and health checks
- **Tested**: Comprehensive integration tests included

## Quick Start

### Build the Image

```bash
docker build -t ase:latest ./ase
```

Or using Make:

```bash
make build
```

### Run the Container

```bash
docker run -d \
  --name ase \
  -p 5000:5000 \
  -e ASE_SA_PASSWORD=YourPassword123 \
  ase:latest
```

Or using Make:

```bash
make test-quick
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ASE_DS_NAME` | Data source name for interfaces file | `MYSYBASE` |
| `ASE_SA_PASSWORD` | System Administrator password | Randomly generated |
| `ASE_PORT` | ASE server port | `5000` |
| `ASE_DB` | Default database | `master` |
| `ASE_HOST` | Default hostname | `localhost` |
| `ASE_DATA_PATH` | Data directory path | `$SYBASE/data` |
| `WAIT_SEC` | Maximum wait time for ASE startup (seconds) | `60` |

### Ports

- `5000` - ASE server default port

## Testing

### Run Integration Tests

```bash
make test
```

Or directly:

```bash
bash tests/ase-test.sh
```

The tests verify:
- Image builds successfully
- Container starts without errors
- ASE server becomes ready
- Basic SQL queries work
- Database operations function correctly
- System stored procedures execute

## Development

### Prerequisites

- Docker
- Bash shell
- (Optional) Make utility

### Dev Container

This project includes a dev container configuration for VS Code.

To use the dev container:
1. Open the project in VS Code
2. Install the "Dev Containers" extension
3. Press F1 and select "Dev Containers: Reopen in Container"

### Linting

Run shellcheck on shell scripts:

```bash
make lint
```

### Formatting

Format shell scripts:

```bash
make format
```

## Project Structure

```
.
├── .devcontainer/
│   └── devcontainer.json    # VS Code dev container configuration
├── .github/
│   └── workflows/
│       ├── ase.yaml         # ASE build workflow
│       └── docker-build-push.yml  # Reusable build workflow
├── ase/
│   ├── Dockerfile           # ASE Docker image
│   ├── entrypoint.sh        # Container entry point script
│   └── sap-response.txt     # SAP installer response file
├── tests/
│   └── ase-test.sh          # Integration tests
├── Makefile                 # Convenient commands
└── README.md                # This file
```

## Connecting to ASE

### Using isql from within the container

```bash
docker exec -it ase isql -S localhost -Usa -P YourPassword123
```

### Using isql from host (requires SAP client)

Install the SAP client and configure the interfaces file, then:

```bash
isql -S your_server_name -Usa -P YourPassword123
```

## Troubleshooting

### Container exits immediately

Check the logs:
```bash
docker logs ase
```

Common issues:
- Insufficient memory (ASE requires at least 2GB)
- Port 5000 already in use
- Incorrect password

### ASE not responding

Wait for ASE to fully start (can take up to 60 seconds):
```bash
docker logs -f ase
```

## License

This Docker image includes SAP ASE software. Please ensure you have appropriate licenses from SAP for using ASE in production.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## CI/CD

This project uses GitHub Actions for automated builds:

- **ase.yaml**: Scheduled monthly builds and manual triggers
- **docker-build-push.yml**: Reusable workflow for building and pushing to GHCR

## Support

For issues related to:
- **This Docker image**: Open an issue in this repository
- **SAP ASE**: Contact SAP support or refer to SAP documentation
