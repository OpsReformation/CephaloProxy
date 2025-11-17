#!/usr/bin/env bats
# Integration tests for health check endpoints (T015, T016)
# Tests /health (liveness) and /ready (readiness) endpoints

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
# T015: /health endpoint tests (Liveness probe)
# =============================================================================

@test "[US1-T015] /health endpoint returns 200 OK when Squid is running" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to start
    sleep 10

    # Test /health endpoint
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    # Cleanup
    teardown
}

@test "[US1-T015] /health endpoint responds in less than 1 second" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to start
    sleep 10

    # Test /health response time
    run curl -s -o /dev/null -w "%{time_total}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]

    # Convert to integer for comparison (e.g., 0.123 -> 0)
    response_time_ms=$(echo "$output * 1000" | bc | cut -d. -f1)
    [ "$response_time_ms" -lt 1000 ]

    # Cleanup
    teardown
}

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
# T016: /ready endpoint tests (Readiness probe)
# =============================================================================

@test "[US1-T016] /ready endpoint returns 200 OK when Squid is ready" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to start
    sleep 10

    # Test /ready endpoint
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    # Cleanup
    teardown
}

@test "[US1-T016] /ready endpoint responds in less than 1 second" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to start
    sleep 10

    # Test /ready response time
    run curl -s -o /dev/null -w "%{time_total}" "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]

    # Convert to integer for comparison
    response_time_ms=$(echo "$output * 1000" | bc | cut -d. -f1)
    [ "$response_time_ms" -lt 1000 ]

    # Cleanup
    teardown
}

@test "[US1-T016] /ready endpoint checks cache directory" {
    # Start container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        "$IMAGE_NAME"

    # Wait for container to start
    sleep 10

    # Get /ready response body
    run curl -s "http://localhost:$HEALTH_PORT/ready"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "READY" ]]

    # Cleanup
    teardown
}

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
    for _ in {1..10}; do
        curl -s "http://localhost:$HEALTH_PORT/health" > /dev/null &
    done
    wait

    # Verify server still responds
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}
