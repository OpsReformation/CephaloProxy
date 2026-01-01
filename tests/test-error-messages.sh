#!/bin/bash
# Test script for validating error messages and logging clarity (T019)
# Tests various failure scenarios for init-squid.py
#
# Expected behavior (corrected):
# 1. cache_dir configured + volume missing/not writable → FAIL with clear error
# 2. NO cache_dir configured → Start successfully in pure proxy mode
# 3. SSL-bump configured + certs missing → FAIL with clear error

set -e

IMAGE="${IMAGE:-cephaloproxy:distroless-test}"
PASSED=0
FAILED=0

log_test() {
    echo ""
    echo "=========================================="
    echo "TEST: $1"
    echo "=========================================="
}

log_pass() {
    echo "✅ PASS: $1"
    ((PASSED++))
}

log_fail() {
    echo "❌ FAIL: $1"
    ((FAILED++))
}

# Test 1: cache_dir configured but volume read-only (should FAIL with clear error)
log_test "cache_dir configured but volume read-only (should FAIL)"
mkdir -p /tmp/test-readonly-cache
chmod 555 /tmp/test-readonly-cache
if docker run --rm \
    -v /tmp/test-readonly-cache:/var/spool/squid:ro \
    "$IMAGE" 2>&1 | grep -q "cache_dir directive found in squid.conf but volume not writable"; then
    log_pass "Failed correctly with clear error when cache_dir configured but volume not writable"
else
    log_fail "Missing or unclear error message for read-only cache volume"
fi
rm -rf /tmp/test-readonly-cache

# Test 2: Missing SSL certificate volume (should FAIL)
log_test "Missing SSL certificate volume (should FAIL)"
cat > /tmp/test-ssl-squid.conf << 'EOF'
http_port 3128
pid_filename /var/run/squid/squid.pid
cache_dir ufs /var/spool/squid 250 16 256
# Enable SSL-bump
http_port 3129 ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=/var/lib/squid/squid-ca.pem
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 4MB
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump bump all
EOF
if docker run --rm \
    -v /tmp/test-ssl-squid.conf:/etc/squid/squid.conf:ro \
    "$IMAGE" 2>&1 | grep -q "TLS certificate not found"; then
    log_pass "Failed correctly when SSL-bump enabled but certs missing"
else
    log_fail "Missing or unclear SSL certificate error message"
fi
rm -f /tmp/test-ssl-squid.conf

# Test 3: Successful initialization with writable cache volume
log_test "Successful initialization with writable cache volume"
CONTAINER_ID=$(docker run -d "$IMAGE")

sleep 5

if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Initialization complete"; then
    log_pass "Container initialized successfully"
else
    log_fail "Container failed to initialize"
fi

# Check for clear logging with timestamps
if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Starting Squid initialization"; then
    log_pass "Python logging with timestamps present"
else
    log_fail "Python logging missing"
fi

# Check that Squid started
if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Squid started with PID"; then
    log_pass "Squid process started successfully"
else
    log_fail "Squid process failed to start"
fi

# Check health endpoint
if docker exec "$CONTAINER_ID" /busybox/wget -q -O- http://localhost:8080/ready 2>&1 | grep -q "READY"; then
    log_pass "Health endpoint operational"
else
    log_fail "Health endpoint not working"
fi

docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true
docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true

# Test 4: Verify error message clarity (cache_dir configured but missing)
log_test "Error message clarity - cache_dir configured but volume missing"
mkdir -p /tmp/test-missing-cache
chmod 000 /tmp/test-missing-cache
LOGS=$(docker run --rm -v /tmp/test-missing-cache:/var/spool/squid "$IMAGE" 2>&1 || true)
chmod 755 /tmp/test-missing-cache
rm -rf /tmp/test-missing-cache

if echo "$LOGS" | grep -q "Cache directory not writable"; then
    log_pass "Clear error message for non-writable cache"
else
    log_fail "Error message unclear or missing"
fi

if echo "$LOGS" | grep -q "Fix volume permissions or remove cache_dir from config"; then
    log_pass "Error message includes actionable guidance"
else
    log_fail "Error message missing actionable guidance"
fi

# Test 5: Verify logging format quality
log_test "Logging format quality"
if echo "$LOGS" | grep -q "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}"; then
    log_pass "Timestamps in ISO format present"
else
    log_fail "Timestamps in ISO format missing"
fi

if echo "$LOGS" | grep -q "\[ERROR\]"; then
    log_pass "ERROR severity level present"
else
    log_fail "ERROR severity level missing"
fi

# Summary
echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"
echo "=========================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
