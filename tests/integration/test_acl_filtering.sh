#!/usr/bin/env bats
# Integration tests for User Story 2: Traffic Filtering
# Tests ACL-based domain blocking and filtering

# Test configuration
IMAGE_NAME="${IMAGE_NAME:-cephaloproxy:test}"
CONTAINER_NAME="test-squid-acl"
PROXY_PORT=3128
HEALTH_PORT=8080

# Cleanup function
teardown() {
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# =============================================================================
# T030: Test blocked domain denial
# =============================================================================

@test "[US2-T030] Blocked domains return 403 Forbidden" {
    # Start container with ACL config
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Test blocked domain (facebook.com)
    run curl -x "http://localhost:$PROXY_PORT" \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        http://facebook.com

    [ "$status" -eq 0 ]
    [[ "$output" =~ "403" || "$output" =~ "407" ]]

    teardown
}

@test "[US2-T030] Logs show TCP_DENIED for blocked domains" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Attempt to access blocked domain
    curl -x "http://localhost:$PROXY_PORT" \
        -s \
        http://facebook.com > /dev/null 2>&1 || true

    sleep 2

    # Check Squid's access.log for denial (more reliable than docker logs)
    run docker exec "$CONTAINER_NAME" cat /var/log/squid/access.log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DENIED" || "$output" =~ "403" ]]

    teardown
}

# =============================================================================
# T031: Test allowed domain success
# =============================================================================

@test "[US2-T031] Allowed domains return 200 OK" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Test allowed domain (example.com)
    run curl -x "http://localhost:$PROXY_PORT" \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        http://example.com

    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}

@test "[US2-T031] Multiple allowed domains work correctly" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Test multiple allowed domains
    for domain in "example.com" "example.org" "www.google.com"; do
        run curl -x "http://localhost:$PROXY_PORT" \
            -s \
            -o /dev/null \
            -w "%{http_code}" \
            "http://$domain"

        [ "$status" -eq 0 ]
        [ "$output" = "200" ]
    done

    teardown
}

# =============================================================================
# Additional ACL filtering tests
# =============================================================================

@test "[US2] Container starts with ACL configuration" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Verify container is running
    run docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Up" ]]

    # Verify health check passes
    run curl -s -o /dev/null -w "%{http_code}" "http://localhost:$HEALTH_PORT/health"
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]

    teardown
}

@test "[US2] Subdomain blocking works correctly" {
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/filtering-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-configs/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro" \
        "$IMAGE_NAME"

    sleep 10

    # Test that subdomains of blocked domains are also blocked
    run curl -x "http://localhost:$PROXY_PORT" \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        http://www.facebook.com

    [ "$status" -eq 0 ]
    [[ "$output" =~ "403" || "$output" =~ "407" ]]

    teardown
}
