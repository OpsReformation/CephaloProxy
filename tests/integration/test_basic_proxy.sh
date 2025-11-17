#!/usr/bin/env bats
# Integration tests for User Story 1: Basic Proxy Deployment
# Tests default container startup and HTTP proxy functionality

# Test configuration
IMAGE_NAME="${IMAGE_NAME:-cephaloproxy:test}"
CONTAINER_NAME="test-squid-basic"
PROXY_PORT=3128
HEALTH_PORT=8080

# Cleanup function
teardown() {
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# =============================================================================
# T013: Test default container startup
# =============================================================================

@test "[US1-T013] Container starts with default config and no volumes" {
    # Start container without any volume mounts
    run docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    [ "$status" -eq 0 ]

    # Wait for container to start
    sleep 10

    # Verify container is running
    run docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Up" ]]

    # Cleanup
    teardown
}

@test "[US1-T013] Container starts in less than 10 seconds" {
    # Start container
    start_time=$(date +%s)

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for health check to pass
    max_wait=10
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf "http://localhost:$HEALTH_PORT/health" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    end_time=$(date +%s)
    startup_time=$((end_time - start_time))

    # Verify startup time < 10 seconds
    [ $startup_time -lt 10 ]

    # Cleanup
    teardown
}

# =============================================================================
# T014: Test HTTP proxy functionality
# =============================================================================

@test "[US1-T014] Proxy forwards HTTP requests successfully" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to be ready
    sleep 10

    # Test HTTP proxy request
    run curl -x "http://localhost:$PROXY_PORT" \
        -I \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        http://example.com

    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    # Cleanup
    teardown
}

@test "[US1-T014] Proxy logs show successful request" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to be ready
    sleep 10

    # Make a proxy request
    curl -x "http://localhost:$PROXY_PORT" \
        -s \
        http://example.com > /dev/null 2>&1 || true

    # Wait for logs to be written
    sleep 2

    # Check logs for successful request
    run docker logs "$CONTAINER_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" =~ example.com ]]

    # Cleanup
    teardown
}

# =============================================================================
# NOTE: Health check tests (T015, T016) are in test_health_checks.sh
# =============================================================================
