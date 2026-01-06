# Quick Start: Distroless Migration Development

**Feature**: 003-distroless-completion
**Date**: 2026-01-01
**Purpose**: Developer guide for building, testing, and debugging Python entrypoint

## Prerequisites

- Docker 20.10+ or Podman 4.0+
- Bats (Bash Automated Testing System) for integration tests
- Python 3.11+ (for local unit testing)
- kubectl (optional, for Kubernetes debugging)

## Quick Start

### 1. Build Distroless Image

```bash
# Build Debian 12 distroless image (current approach)
cd /Users/nathan/Documents/Code/OpsReformation/CephaloProxy
docker build -f container/Dockerfile.distroless -t cephaloproxy:distroless .

# Build multi-platform (amd64 + arm64)
./container/build-multiplatform.sh
```

**Build Time**: ~5-10 minutes (Debian package installation + Squid compilation)

**Expected Output**:
```
[+] Building 300.5s (25/25) FINISHED
=> [squid-builder 1/5] FROM debian:12-slim
=> [squid-builder 2/5] RUN apt-get update && apt-get install -y squid-openssl
=> [directory-builder 1/2] RUN mkdir -p /runtime/var/spool/squid ...
=> [stage-2 1/8] COPY --from=squid-builder /usr/sbin/squid /usr/sbin/squid
=> exporting to image
=> => naming to docker.io/library/cephaloproxy:distroless
```

### 2. Run Container Locally

```bash
# Run with default configuration
docker run --rm -p 3128:3128 -p 8080:8080 cephaloproxy:distroless

# Run with custom squid.conf
docker run --rm \
  -v $(pwd)/custom-squid.conf:/etc/squid/squid.conf:ro \
  -p 3128:3128 \
  cephaloproxy:distroless

# Run with SSL-bump (requires TLS secret)
docker run --rm \
  -v $(pwd)/tls-secret:/etc/squid/ssl_cert:ro \
  -p 3128:3128 \
  cephaloproxy:distroless
```

**Expected Logs**:
```
2026-01-01 12:00:00 [INFO] CephaloProxy entrypoint starting (UID: 1000, GID: 0)
2026-01-01 12:00:00 [INFO] Validating Squid configuration...
2026-01-01 12:00:01 [INFO] Configuration validation passed
2026-01-01 12:00:01 [INFO] Starting health check server on port 8080
2026-01-01 12:00:03 [INFO] Health check server started (PID: 45)
2026-01-01 12:00:03 [INFO] Starting Squid proxy...
2026-01-01 12:00:05 [INFO] Squid started with PID 123
2026-01-01 12:00:05 [INFO] Container ready, entering monitoring loop
```

### 3. Test Proxy Functionality

```bash
# Test HTTP proxy
curl -x http://localhost:3128 http://example.com

# Test health endpoint
curl http://localhost:8080/health
# Expected: OK

# Test ready endpoint
curl http://localhost:8080/ready
# Expected: OK
```

### 4. Test Graceful Shutdown

```bash
# In one terminal: run container
docker run --name test-proxy cephaloproxy:distroless

# In another terminal: stop container
time docker stop test-proxy

# Expected: Completes in ~30-35 seconds
# Logs show: "Received signal SIGTERM, initiating graceful shutdown..."
#            "Shutdown complete"
```

### 5. Verify Shell Absence

```bash
# Start container
docker run --name test-proxy -d cephaloproxy:distroless

# Attempt shell access (should fail)
docker exec -it test-proxy /bin/sh
# Expected: OCI runtime exec failed: exec failed: unable to start container process: exec: "/bin/sh": stat /bin/sh: no such file or directory

docker exec -it test-proxy /bin/bash
# Expected: Similar error

docker exec -it test-proxy sh
# Expected: Similar error

# Cleanup
docker rm -f test-proxy
```

## Development Workflow

### Local Unit Testing

```bash
# Run Python unit tests (before container build)
cd /Users/nathan/Documents/Code/OpsReformation/CephaloProxy
python3 -m pytest tests/unit/test-entrypoint.py -v

# Run with coverage
python3 -m pytest tests/unit/ --cov=container/ --cov-report=html
```

**Example Unit Test**:

```python
# tests/unit/test-entrypoint.py
import unittest
from pathlib import Path
from container.entrypoint import check_process_running, parse_proc_status

class TestProcParsing(unittest.TestCase):

    def test_check_process_running_self(self):
        """Test that current Python process is detected as running."""
        import os
        self_pid = os.getpid()
        self.assertTrue(check_process_running(self_pid))

    def test_check_process_running_nonexistent(self):
        """Test that non-existent PID returns False."""
        self.assertFalse(check_process_running(999999))

    def test_parse_proc_status_self(self):
        """Test parsing /proc/self/status."""
        import os
        self_pid = os.getpid()
        info = parse_proc_status(self_pid)
        self.assertIsNotNone(info)
        self.assertEqual(info['pid'], self_pid)
        self.assertIn(info['state'], ['R', 'S'])  # Running or Sleeping
```

### Integration Testing

```bash
# Run Bats integration tests
cd /Users/nathan/Documents/Code/OpsReformation/CephaloProxy
bats tests/integration/test-container-startup.bats
bats tests/integration/test-shell-absence.bats
bats tests/integration/test-graceful-shutdown.bats

# Run all integration tests
bats tests/integration/*.bats
```

**Example Bats Test**:

```bash
# tests/integration/test-shell-absence.bats
#!/usr/bin/env bats

@test "Container does not include /bin/sh" {
  run docker run --rm cephaloproxy:distroless ls /bin/sh
  [ "$status" -ne 0 ]
}

@test "Container does not include /bin/bash" {
  run docker run --rm cephaloproxy:distroless ls /bin/bash
  [ "$status" -ne 0 ]
}

@test "docker exec /bin/sh fails" {
  docker run --name test-shell -d cephaloproxy:distroless
  run docker exec test-shell /bin/sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such file or directory"* ]]
  docker rm -f test-shell
}
```

### Debugging Without Shell

Since the distroless container has no shell, use these debugging techniques:

#### Method 1: Ephemeral Debug Container (Kubernetes)

```bash
# Kubernetes: Attach debug container with shell
kubectl debug -it <pod-name> --image=busybox:latest --target=<container-name>

# Inside debug container
ps aux  # View processes
cat /proc/<squid-pid>/status  # Check Squid status
ls -la /var/run/squid/  # Inspect runtime files
```

#### Method 2: Docker Debug (Docker 23.0+)

```bash
# Docker: Attach debug shell to running container
docker debug <container-id>

# Inside debug shell
ps aux
cat /proc/$(pgrep squid)/status
```

#### Method 3: Distroless Debug Variant (Development Only)

```dockerfile
# Temporarily switch to debug variant in Dockerfile.distroless
# FROM gcr.io/distroless/python3-debian12
FROM gcr.io/distroless/python3-debian12:debug

# Rebuild and test
docker build -f container/Dockerfile.distroless -t cephaloproxy:debug .
docker run --rm -it cephaloproxy:debug /busybox/sh
```

**Warning**: Debug variant includes busybox shell. NOT for production use.

#### Method 4: Log Inspection

```bash
# Stream container logs
docker logs -f <container-id>

# Export logs for analysis
docker logs <container-id> > entrypoint.log 2>&1

# Filter specific log levels
docker logs <container-id> 2>&1 | grep '\[ERROR\]'
```

#### Method 5: /proc Filesystem Inspection (from host)

```bash
# Find container PID
docker inspect <container-id> | jq '.[0].State.Pid'

# Inspect from host /proc
sudo cat /proc/<container-pid>/status
sudo ls -la /proc/<container-pid>/fd  # Open file descriptors
sudo cat /proc/<container-pid>/cmdline  # Command line
```

## Testing Scenarios

### Scenario 1: Config Validation Failure

```bash
# Create invalid squid.conf
echo "invalid directive" > /tmp/bad-squid.conf

# Run container with bad config
docker run --rm -v /tmp/bad-squid.conf:/etc/squid/squid.conf:ro \
  cephaloproxy:distroless

# Expected output:
# [ERROR] Squid configuration validation failed:
#   squid: ERROR: Unknown directive 'invalid'
# Exit code: 1
```

### Scenario 2: Directory Permission Error

```bash
# Run as arbitrary UID without writable /var/run/squid
docker run --rm --user 99999:0 \
  --read-only \
  cephaloproxy:distroless

# Expected output:
# [ERROR] Directory /var/run/squid is not writable (UID: 99999, GID: 0)
# Exit code: 1
```

### Scenario 3: SSL-Bump Without Certificates

```bash
# Create squid.conf with ssl-bump enabled
cat > /tmp/ssl-squid.conf <<EOF
http_port 3128 ssl-bump cert=/var/lib/squid/squid-ca.pem
ssl_bump server-first all
acl all src 0.0.0.0/0
http_access allow all
EOF

# Run without mounting TLS secret
docker run --rm -v /tmp/ssl-squid.conf:/etc/squid/squid.conf:ro \
  cephaloproxy:distroless

# Expected output:
# [ERROR] SSL-bump enabled but TLS certificate not found: /etc/squid/ssl_cert/tls.crt
# Exit code: 1
```

### Scenario 4: Process Monitoring (Squid Crash)

```bash
# Start container
docker run --name test-crash -d cephaloproxy:distroless

# Wait for startup
sleep 10

# Kill Squid process directly
SQUID_PID=$(docker exec test-crash pgrep squid)  # Note: pgrep not available in distroless
# Alternative: Use docker debug or inspect logs for PID

# Container should exit within 2 seconds
docker wait test-crash  # Should return exit code 1

# Check logs
docker logs test-crash
# Expected: [ERROR] Squid process died with exit code ...

# Cleanup
docker rm test-crash
```

### Scenario 5: OpenShift Arbitrary UID

```bash
# Run with arbitrary UID (simulates OpenShift)
docker run --rm --user 1234567:0 cephaloproxy:distroless

# Expected: Container starts successfully
# Logs show: "CephaloProxy entrypoint starting (UID: 1234567, GID: 0)"
```

## Performance Benchmarking

### Startup Time Measurement

```bash
# Measure container startup time
time docker run --rm cephaloproxy:distroless /usr/bin/python3 -c "import sys; sys.exit(0)"

# Measure until "Container ready" log appears
docker run --name bench-startup -d cephaloproxy:distroless
START_TIME=$(date +%s)
while ! docker logs bench-startup 2>&1 | grep -q "Container ready"; do
  sleep 0.1
done
END_TIME=$(date +%s)
echo "Startup time: $((END_TIME - START_TIME)) seconds"
docker rm -f bench-startup
```

**Baseline**: Compare with bash entrypoint version. Python version MUST be ≤ 110% of baseline.

### Memory Usage Measurement

```bash
# Run container
docker run --name mem-test -d cephaloproxy:distroless

# Wait for full startup
sleep 15

# Measure memory (entrypoint process only, not Squid)
docker exec mem-test cat /proc/1/status | grep VmRSS
# Expected: VmRSS < 50 MB

docker rm -f mem-test
```

### Shutdown Time Measurement

```bash
# Run container
docker run --name shutdown-test -d cephaloproxy:distroless

# Wait for startup
sleep 10

# Measure shutdown time
time docker stop shutdown-test
# Expected: ~30-35 seconds (30s graceful + 5s Docker timeout buffer)

docker rm shutdown-test
```

## Vulnerability Scanning

### Trivy Scan

```bash
# Scan image for vulnerabilities
trivy image --severity HIGH,CRITICAL cephaloproxy:distroless

# Expected: Reduced CVE count compared to Debian 12 debug variant
# Generate report
trivy image --format json --output trivy-report.json cephaloproxy:distroless
```

### Compare Vulnerability Counts

```bash
# Scan Debian 12 debug variant
trivy image gcr.io/distroless/python3-debian12:debug > baseline-cves.txt

# Scan custom distroless image
trivy image cephaloproxy:distroless > distroless-cves.txt

# Compare counts
grep "Total:" baseline-cves.txt
grep "Total:" distroless-cves.txt
```

## Continuous Integration

### CI Pipeline Steps

```yaml
# .github/workflows/distroless-migration.yml
name: Distroless Migration CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Unit Tests
        run: |
          python3 -m pytest tests/unit/ --cov=container/

      - name: Build Docker Image
        run: |
          docker build -f container/Dockerfile.distroless \
            -t cephaloproxy:distroless .

      - name: Integration Tests
        run: |
          bats tests/integration/*.bats

      - name: Security Scan
        run: |
          trivy image --severity HIGH,CRITICAL \
            --exit-code 1 cephaloproxy:distroless

      - name: Startup Performance Test
        run: |
          ./scripts/benchmark-startup.sh

      - name: Shell Absence Verification
        run: |
          ! docker run --rm cephaloproxy:distroless ls /bin/sh
          ! docker run --rm cephaloproxy:distroless ls /bin/bash
```

## Troubleshooting

### Problem: Container Exits Immediately with Code 1

**Diagnosis**:
```bash
docker logs <container-id>
```

**Common Causes**:
- Invalid squid.conf → Check `[ERROR] Squid configuration validation failed`
- Non-writable directories → Check `[ERROR] Directory ... is not writable`
- Missing SSL certs → Check `[ERROR] SSL-bump enabled but TLS certificate not found`

**Solution**: Fix configuration, mount required volumes, ensure correct permissions.

### Problem: Container Hangs During Startup

**Diagnosis**:
```bash
# Check logs for last message
docker logs <container-id>

# Inspect processes
docker debug <container-id>  # If available
ps aux
```

**Common Causes**:
- Squid PID file not created (permission issue or config error)
- Health check server port conflict

**Solution**: Check Squid logs in /var/log/squid/, verify port availability.

### Problem: Graceful Shutdown Takes > 30 Seconds

**Diagnosis**:
```bash
# Enable verbose logging
docker run --name debug-shutdown \
  -e LOG_LEVEL=DEBUG \
  cephaloproxy:distroless

# In another terminal
docker stop debug-shutdown

# Check shutdown logs
docker logs debug-shutdown
```

**Common Causes**:
- Squid not responding to SIGTERM (check Squid config)
- Async tasks not cancelling properly

**Solution**: Review asyncio task cancellation logic, verify Squid shutdown handlers.

### Problem: Cannot Debug Without Shell

**Solution**: Use one of these methods:
1. Kubernetes: `kubectl debug -it <pod> --image=busybox`
2. Docker: `docker debug <container-id>` (Docker 23.0+)
3. Development: Temporarily use debug variant (`python3-debian12:debug`)
4. Host: Inspect `/proc/<container-pid>` from host system

## Next Steps

After completing quickstart:

1. Review [data-model.md](data-model.md) for state machine details
2. Review [contracts/entrypoint-contract.md](contracts/entrypoint-contract.md) for behavioral contracts
3. Run `/speckit.tasks` to generate implementation tasks
4. Implement entrypoint.py following TDD workflow
5. Run full test suite before merging

## Reference

- **Dockerfile**: [container/Dockerfile.distroless](../../../container/Dockerfile.distroless)
- **Current Bash Entrypoint**: [container/entrypoint.sh](../../../container/entrypoint.sh)
- **Python Entrypoint** (to be created): [container/entrypoint.py](../../../container/entrypoint.py)
- **Integration Tests**: [tests/integration/](../../../tests/integration/)
- **Distroless Documentation**: https://github.com/GoogleContainerTools/distroless
