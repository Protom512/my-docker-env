#!/usr/bin/env bash
#
# ASE Docker Image Integration Test
# Tests the SAP ASE 16 Docker image functionality
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ase}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="ase-test-$$"
ASE_PORT="${ASE_PORT:-5000}"
ASE_DS_NAME="${ASE_DS_NAME:-MYSYBASE}"
ASE_SA_PASSWORD="${ASE_SA_PASSWORD:-TestPassword123}"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."

    if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
        log_info "Stopping container ${CONTAINER_NAME}..."
        docker stop "${CONTAINER_NAME}" || true
    fi

    if docker ps -aq -f name="${CONTAINER_NAME}" | grep -q .; then
        log_info "Removing container ${CONTAINER_NAME}..."
        docker rm "${CONTAINER_NAME}" || true
    fi

    exit ${exit_code}
}

trap cleanup EXIT INT TERM

# Test functions
test_image_exists() {
    log_info "Checking if image ${IMAGE_NAME}:${IMAGE_TAG} exists..."

    if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null 2>&1; then
        log_info "Image ${IMAGE_NAME}:${IMAGE_TAG} found locally"
        return 0
    fi

    log_warn "Image not found locally, attempting to build..."
    if ! docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${PROJECT_ROOT}/ase"; then
        log_error "Failed to build image"
        return 1
    fi

    log_info "Image built successfully"
    return 0
}

test_container_starts() {
    log_info "Starting container ${CONTAINER_NAME}..."

    if ! docker run -d \
        --name "${CONTAINER_NAME}" \
        -p "${ASE_PORT}:5000" \
        -e ASE_SA_PASSWORD="${ASE_SA_PASSWORD}" \
        "${IMAGE_NAME}:${IMAGE_TAG}"; then
        log_error "Failed to start container"
        return 1
    fi

    log_info "Container started successfully"
    return 0
}

test_ase_is_ready() {
    log_info "Waiting for ASE server to be ready (timeout: ${TEST_TIMEOUT}s)..."

    local elapsed=0
    local interval=5

    while [ ${elapsed} -lt ${TEST_TIMEOUT} ]; do
        if docker exec "${CONTAINER_NAME}" pgrep -x dataserver >/dev/null 2>&1; then
            log_info "ASE server process is running"

            # Try to connect using isql
            if docker exec "${CONTAINER_NAME}" isql \
                -S "${ASE_DS_NAME}" \
                -Usa \
                -P "${ASE_SA_PASSWORD}" \
                -b -w 10 <<-EOF 2>/dev/null
SELECT @@VERSION
GO
EXIT
EOF
            then
                log_info "Successfully connected to ASE server"
                return 0
            fi
        fi

        log_info "Waiting for ASE to be ready... (${elapsed}s/${TEST_TIMEOUT}s)"
        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log_error "ASE server did not become ready within ${TEST_TIMEOUT}s"
    return 1
}

test_basic_query() {
    log_info "Testing basic SQL query execution..."

    if ! docker exec "${CONTAINER_NAME}" isql \
        -S "${ASE_DS_NAME}" \
        -Usa \
        -P "${ASE_SA_PASSWORD}" \
        -b -w 10 <<-EOF >/dev/null 2>&1
SELECT @@SERVERNAME
GO
SELECT @@VERSION
GO
EXIT
EOF
    then
        log_error "Failed to execute basic query"
        return 1
    fi

    log_info "Basic query execution successful"
    return 0
}

test_database_operations() {
    log_info "Testing database creation and operations..."

    local test_db="testdb_$$"

    # Create database
    log_info "Creating test database: ${test_db}"
    if ! docker exec "${CONTAINER_NAME}" isql \
        -S "${ASE_DS_NAME}" \
        -Usa \
        -P "${ASE_SA_PASSWORD}" \
        -b -w 10 <<-EOF >/dev/null 2>&1
CREATE DATABASE ${test_db}
GO
USE ${test_db}
GO
CREATE TABLE test_table (id INT, name VARCHAR(50))
GO
INSERT INTO test_table VALUES (1, 'test')
GO
SELECT * FROM test_table
GO
DROP DATABASE ${test_db}
GO
EXIT
EOF
    then
        log_error "Failed to perform database operations"
        return 1
    fi

    log_info "Database operations successful"
    return 0
}

test_system_procedures() {
    log_info "Testing system stored procedures..."

    if ! docker exec "${CONTAINER_NAME}" isql \
        -S "${ASE_DS_NAME}" \
        -Usa \
        -P "${ASE_SA_PASSWORD}" \
        -b -w 10 <<-EOF >/dev/null 2>&1
sp_helpdb
GO
sp_who
GO
EXIT
EOF
    then
        log_error "Failed to execute system procedures"
        return 1
    fi

    log_info "System procedures execution successful"
    return 0
}

test_container_logs() {
    log_info "Checking container logs for errors..."

    local logs
    logs=$(docker logs "${CONTAINER_NAME}" 2>&1)

    # Check for critical errors (but ignore expected warnings)
    if echo "${logs}" | grep -i "error" | grep -iv "using default" | grep -iv "warning" | head -5; then
        log_warn "Potential errors found in logs (check above)"
    fi

    log_info "Log check completed"
    return 0
}

# Main test execution
main() {
    log_info "Starting ASE Docker Image Integration Test"
    log_info "========================================"

    local failed=0

    test_image_exists || failed=$((failed + 1))
    test_container_starts || failed=$((failed + 1))

    if [ ${failed} -eq 0 ]; then
        test_ase_is_ready || failed=$((failed + 1))
        test_basic_query || failed=$((failed + 1))
        test_database_operations || failed=$((failed + 1))
        test_system_procedures || failed=$((failed + 1))
        test_container_logs || failed=$((failed + 1))
    fi

    log_info "========================================"
    if [ ${failed} -eq 0 ]; then
        log_info "All tests passed!"
        return 0
    else
        log_error "${failed} test(s) failed"
        return 1
    fi
}

# Run main function
main "$@"
