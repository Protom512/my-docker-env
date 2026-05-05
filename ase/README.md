# SAP ASE Docker Image

Docker image for SAP Adaptive Server Enterprise (ASE) 16, based on Red Hat Universal Base Image (UBI) 9.

## Overview

This Docker image provides SAP ASE 16 (formerly Sybase ASE) with multi-stage build optimization, configurable environment variables, and production-ready error handling.

## Features

- **Multi-stage build**: Optimized image size using multi-stage Docker build
- **Configurable**: Environment variables for easy customization including language, charset, and sort order
- **Production-ready**: Proper error handling
- **Tested**: Comprehensive integration tests included

## Quick Start

### Build the Image

Using Docker directly:
```bash
docker build -t ase:latest ./ase
```

Or using Make:
```bash
make build
```

To build with custom system language (build-time argument):
```bash
docker build -t ase:latest --build-arg LANG=en_US.utf8 ./ase
```

> **Note**: The `make build` target does not currently pass build-args. To build with a custom system language, you must use the `docker build` command directly as shown above. The Makefile could be extended to support build-args in the future.

### Run the Container

Using Docker directly:
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

With custom ASE language, charset, and sort order:
```bash
docker run -d \
  --name ase \
  -p 5000:5000 \
  -e ASE_SA_PASSWORD=YourPassword123 \
  -e ASE_LANGUAGE=us_english \
  -e ASE_CHARSET=utf8 \
  -e ASE_SORT=USE_DEFAULT \
  ase:latest
```

## Configuration

### Build-time Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `LANG` | System locale for the container | `ja_JP.utf8` |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ASE_DS_NAME` | Data source name for interfaces file | `MYSYBASE` |
| `ASE_SA_PASSWORD` | System Administrator password | Randomly generated |
| `ASE_PORT` | ASE server port | `5000` |
| `ASE_DB` | Default database | `master` |
| `ASE_HOST` | Default hostname | `localhost` |
| `ASE_DATA_PATH` | Data directory path | `$SYBASE/data` |
| `ASE_LANGUAGE` | ASE default language | `us_english` |
| `ASE_CHARSET` | ASE default character set | `utf8` |
| `ASE_SORT_ORDER` | ASE sort order | `binary` |
| `ASE_MAX_MEMORY_MB` | Memory cap handed to srvbuildres (MB) | `2048` |
| `WAIT_SEC` | Cold-start / connect timeout (seconds) | `120` |
| `SHUTDOWN_WAIT_SEC` | Graceful shutdown timeout (seconds) | `60` |
| `SQLLOCRES_WAIT_SEC` | sqllocres post-restart wait budget (seconds) | `180` |
| `SQL_DIR` | User init scripts directory | `/docker-entrypoint-initdb.d` |

### Initialization & restart behavior

The entrypoint distinguishes between **first run** and **subsequent runs** by
the presence of a sentinel file at `${ASE_DATA_PATH}/.ase-initialized`.

**First run** (sentinel absent):

1. Wipes any leftover device files / RUN file / cfg from a previous failed
   attempt.
2. Runs `srvbuildres` to build master, sysprocs, sysdb and tempdb devices.
3. Runs `sqllocres` to install the requested locale and charset.
4. Cleanly stops the server.
5. Edits `${ASE_DS_NAME}.cfg` to disable async I/O (must be done while the
   server is stopped — ASE rewrites the cfg from in-memory config on
   shutdown).
6. Restarts the server with the patched cfg.
7. Runs user-supplied `*.sh` / `*.sql` scripts from `${SQL_DIR}` (alphabetical
   order).
8. Stops the server cleanly.
9. Touches the sentinel file. From here on the container takes the fast path.

If any step fails, the entrypoint cleans up partial device files and exits
non-zero. The next container start re-attempts initialization from a clean
state.

**Subsequent runs** (sentinel present): only steps 6 and 9 of the above run —
`startserver` is invoked once and the entrypoint waits on the dataserver
process while keeping the error log streamed to stdout.

**Graceful shutdown**: SIGTERM and SIGINT trigger an ASE `shutdown` (then
`shutdown with nowait` then SIGKILL as escalating fallbacks). `tini` is the
container PID 1, so signals from `docker stop` reach the entrypoint reliably.

### Language, Charset, and Sort Order

The following environment variables control ASE language settings:

- **ASE_LANGUAGE**: Default language (e.g., `japanese`, `us_english`)
- **ASE_CHARSET**: Default character set (e.g., `utf8`, `sjis`, `eucjis`)
- **ASE_SORT**: Sort order (e.g., `USE_DEFAULT`, `binary`, `dictionary`)

**Example**: Building an ASE image with English locale and UTF-8 charset:
```bash
docker build -t ase-en:latest --build-arg LANG=en_US.utf8 ./ase
docker run -d \
  -p 5000:5000 \
  -e ASE_SA_PASSWORD=YourPassword123 \
  -e ASE_LANGUAGE=us_english \
  -e ASE_CHARSET=utf8 \
  -e ASE_SORT=binary \
  ase-en:latest
```

### Ports

- `5000` - ASE server default port

## Testing

### Run Integration Tests

Using Make:
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

### Quick Test

Build and run a container for quick testing:
```bash
make test-quick
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

## Support

For issues related to:
- **This Docker image**: Open an issue in the repository
- **SAP ASE**: Contact SAP support or refer to SAP documentation
