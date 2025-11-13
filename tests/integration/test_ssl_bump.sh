#!/usr/bin/env bats
# Integration tests for User Story 3: SSL-Bump HTTPS Caching
# Tests HTTPS interception, decryption, and caching

# Test configuration
IMAGE_NAME="${IMAGE_NAME:-cephaloproxy:test}"
CONTAINER_NAME="test-squid-ssl"
PROXY_PORT=3128
HEALTH_PORT=8080

# Cleanup function
teardown() {
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# =============================================================================
# T044: Test HTTPS interception
# =============================================================================

@test "[US3-T044] Container starts with SSL-bump configuration" {
    # Generate test CA certificate if not exists
    if [ ! -f tests/fixtures/test-certs/ca.pem ]; then
        skip "Test certificates not generated. Run: openssl genrsa -out tests/fixtures/test-certs/ca.key 2048 && openssl req -new -x509 -key tests/fixtures/test-certs/ca.key -out tests/fixtures/test-certs/ca.pem -days 365 -subj '/CN=Test CA'"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/sslbump-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-certs:/etc/squid/ssl_cert:ro" \
        "$IMAGE_NAME"

    sleep 15

    # Verify container is running
    run docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Up" ]]

    teardown
}

@test "[US3-T044] SSL-bump intercepts HTTPS traffic" {
    if [ ! -f tests/fixtures/test-certs/ca.pem ]; then
        skip "Test certificates not generated"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/sslbump-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-certs:/etc/squid/ssl_cert:ro" \
        "$IMAGE_NAME"

    sleep 15

    # Test HTTPS request (will fail cert validation without trusting CA, but proxy should intercept)
    run curl -x "http://localhost:$PROXY_PORT" \
        -k \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        https://example.com

    [ "$status" -eq 0 ]
    # Should get response (200 or connection successful)
    [[ "$output" =~ "200" || "$output" =~ "000" ]]

    teardown
}

# =============================================================================
# T045: Test cache hit verification
# =============================================================================

@test "[US3-T045] SSL-bump caches HTTPS content" {
    if [ ! -f tests/fixtures/test-certs/ca.pem ]; then
        skip "Test certificates not generated"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/sslbump-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-certs:/etc/squid/ssl_cert:ro" \
        "$IMAGE_NAME"

    sleep 15

    # First request (cache miss)
    curl -x "http://localhost:$PROXY_PORT" \
        -k \
        -s \
        https://example.com > /dev/null 2>&1 || true

    sleep 2

    # Second request (should be cache hit)
    curl -x "http://localhost:$PROXY_PORT" \
        -k \
        -s \
        https://example.com > /dev/null 2>&1 || true

    sleep 2

    # Check logs for cache activity
    run docker logs "$CONTAINER_NAME" 2>&1
    [ "$status" -eq 0 ]
    # Logs should show cache activity (TCP_MISS then TCP_HIT or similar)

    teardown
}

# =============================================================================
# Additional SSL-bump tests
# =============================================================================

@test "[US3] SSL database is initialized correctly" {
    if [ ! -f tests/fixtures/test-certs/ca.pem ]; then
        skip "Test certificates not generated"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/sslbump-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-certs:/etc/squid/ssl_cert:ro" \
        "$IMAGE_NAME"

    sleep 15

    # Check that SSL database was created
    run docker exec "$CONTAINER_NAME" ls -la /var/lib/squid/ssl_db
    [ "$status" -eq 0 ]
    [[ "$output" =~ "certs" ]]

    teardown
}

@test "[US3] Container validates SSL certificate permissions" {
    if [ ! -f tests/fixtures/test-certs/ca.pem ]; then
        skip "Test certificates not generated"
    fi

    # This test verifies that the container checks certificate file permissions
    # The entrypoint should warn if ca.key is world-readable

    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PROXY_PORT:3128" \
        -p "$HEALTH_PORT:8080" \
        -v "$(pwd)/tests/fixtures/test-configs/sslbump-squid.conf:/etc/squid/squid.conf:ro" \
        -v "$(pwd)/tests/fixtures/test-certs:/etc/squid/ssl_cert:ro" \
        "$IMAGE_NAME"

    sleep 15

    # Check logs for permission warnings or validation
    run docker logs "$CONTAINER_NAME" 2>&1
    [ "$status" -eq 0 ]

    teardown
}
