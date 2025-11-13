#!/usr/bin/env bats
# Integration tests for health check endpoints
# Separate test file for comprehensive health check testing

# Test configuration
IMAGE_NAME="${IMAGE_NAME:-cephaloproxy:test}"
CONTAINER_NAME="test-squid-health"
PROXY_PORT=3128
HEALTH_PORT=8080

# Cleanup function
teardown() {
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# =============================================================================
# T015: Comprehensive /health endpoint tests
# =============================================================================

@test "[US1-T015] /health returns OK with correct content type" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    # Check content type header
    run curl -s -I "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Content-Type: text/plain" ]]

    teardown
}

@test "[US1-T015] /health returns correct status code" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}

@test "[US1-T015] /health response body contains OK" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    run curl -s "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OK" ]]

    teardown
}

# =============================================================================
# T016: Comprehensive /ready endpoint tests
# =============================================================================

@test "[US1-T016] /ready returns READY with correct content type" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    run curl -s -I "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Content-Type: text/plain" ]]

    teardown
}

@test "[US1-T016] /ready returns correct status code" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}

@test "[US1-T016] /ready response body contains READY" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    run curl -s "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "READY" ]]

    teardown
}

# =============================================================================
# Additional health check tests
# =============================================================================

@test "Health check server rejects unknown endpoints" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    # Test unknown endpoint
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/unknown"
    [ "$status" -eq 0 ]
    [ "$output" = "404" ]

    teardown
}

@test "Health check server handles concurrent requests" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    sleep 10

    # Send 10 concurrent requests
    for i in {1..10}; do
        curl -s "http://localhost:$HEALTH_PORT/health" > /dev/null &
    done
    wait

    # Verify server still responds
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}
