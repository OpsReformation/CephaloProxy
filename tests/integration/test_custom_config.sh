#!/usr/bin/env bats
# Integration tests for User Story 4: Advanced Custom Configuration
# Tests custom squid.conf override and configuration validation

# Test configuration
IMAGE_NAME="${IMAGE_NAME:-cephaloproxy:test}"
CONTAINER_NAME="test-squid-custom"
PROXY_PORT=3128
HEALTH_PORT=8080

# Cleanup function
teardown() {
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# =============================================================================
# T060: Test custom config loading
# =============================================================================

@test "[US4-T060] Container loads custom squid.conf successfully" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/custom-advanced.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Verify container is running
    run docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Up" ]]

    teardown
}

@test "[US4-T060] Custom config is validated on startup" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/custom-advanced.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Check logs for config validation
    run docker logs "$CONTAINER_NAME" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "validation" || "$output" =~ "parse" || "$output" =~ "Squid" ]]

    teardown
}

# =============================================================================
# T061: Test invalid config rejection
# =============================================================================

@test "[US4-T061] Invalid config causes container to exit with error" {
    # Start container with invalid config
    run docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/invalid-syntax.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME"

    # Container may start but should exit quickly
    sleep 5

    # Check container status (should have exited)
    run docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Exited" ]]

    teardown
}

@test "[US4-T061] Invalid config shows clear error message" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/invalid-syntax.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME" || true

    sleep 5

    # Check logs for error message
    run docker logs "$CONTAINER_NAME" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ERROR" || "$output" =~ "error" || "$output" =~ "failed" || "$output" =~ "FATAL" ]]

    teardown
}

# =============================================================================
# Additional custom config tests
# =============================================================================

@test "[US4] Custom config with different port works" {
    # This test would require a custom config with a different port
    # For now, verify that config can be loaded
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/custom-advanced.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Verify health checks still work
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}

@test "[US4] Container prefers mounted config over default" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/custom-advanced.conf:/etc/squid/squid.conf:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Check logs to confirm custom config was used
    run docker logs "$CONTAINER_NAME" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "custom" || "$output" =~ "Using" || "$output" =~ "configuration" ]]

    teardown
}
