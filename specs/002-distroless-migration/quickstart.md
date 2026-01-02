# Quickstart Guide: Distroless Container Migration

**Feature**: `002-distroless-migration`
**Created**: 2025-12-31
**Purpose**: Quick reference for building, testing, and extending the distroless CephaloProxy image

---

## 1. Building the Distroless Image

### Multi-Stage Build Command

```bash
# Build the distroless image
docker build -t cephaloproxy:distroless -f container/Dockerfile .

# Build with specific Squid version (optional)
docker build \
  --build-arg SQUID_VERSION=6.13 \
  -t cephaloproxy:distroless \
  -f container/Dockerfile .
```

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `SQUID_VERSION` | `6.*` | Squid version to compile (6.x series) |
| `DEBIAN_FRONTEND` | `noninteractive` | Avoid interactive prompts during build |

### Expected Build Time

- **Current Gentoo build**: 20-30 minutes (source compilation with emerge)
- **New Distroless build**: 6-9 minutes (70%+ faster)
  - Stage 1 (Squid Builder): ~4-6 minutes (Debian apt + compilation)
  - Stage 2 (Runtime): ~1-2 minutes (copy binaries, set permissions)

### Build Output Verification

```bash
# Verify SSL-bump support compiled
docker run --rm cephaloproxy:distroless squid -v | grep -i ssl

# Expected output should include:
# --enable-ssl-crtd
# --with-openssl
```

---

## 2. Testing the Migration

### Running Existing Integration Tests

The distroless image must pass all existing integration tests without modification (SC-004).

```bash
# Export the new image name
export IMAGE_NAME=cephaloproxy:distroless

# Run all integration tests
bats tests/integration/test-basic-proxy.bats \
     tests/integration/test-health-checks.bats \
     tests/integration/test-acl-filtering.bats

# Expected: 100% pass rate
```

### Vulnerability Scanning with Trivy

Compare security posture between Gentoo and distroless images:

```bash
# Scan distroless image
trivy image --severity HIGH,CRITICAL cephaloproxy:distroless

# Scan current Gentoo image for comparison
trivy image --severity HIGH,CRITICAL cephaloproxy:current

# Success Criteria (SC-003):
# - ≥60% reduction in CVE count vs Gentoo baseline
```

### Size Comparison

```bash
# Compare image sizes
docker images | grep cephaloproxy

# Success Criteria (SC-001):
# - Current Gentoo: ~500MB+
# - Target Distroless: ≤300MB (40%+ reduction)
```

### Startup Time Validation

```bash
# Measure container startup time
time docker run --rm \
  -e HEALTH_PORT=8080 \
  cephaloproxy:distroless &

# Wait for health check ready
while ! curl -sf http://localhost:8080/ready; do
  sleep 0.5
done

# Success Criteria (SC-005):
# - Startup time ≤110% of Gentoo baseline
```

### Manual Functional Testing

```bash
# Start the distroless container
docker run -d --name cephaloproxy-test \
  -p 3128:3128 \
  -p 8080:8080 \
  cephaloproxy:distroless

# Test HTTP proxy functionality
curl -x http://localhost:3128 http://example.com

# Test health endpoints
curl http://localhost:8080/health   # Should return 200 OK
curl http://localhost:8080/ready    # Should return 200 OK

# Test graceful shutdown
docker stop --time=30 cephaloproxy-test

# Verify logs show graceful shutdown
docker logs cephaloproxy-test
```

---

## 3. Extending with Custom CAs (Enterprise Use Case)

The distroless runtime image does NOT include `update-ca-certificates` or shell utilities. Users needing custom CA certificates must extend the image using a multi-stage build pattern.

### Method 1: Multi-Stage Extension (Recommended)

Create a custom Dockerfile that extends CephaloProxy:

```dockerfile
# Dockerfile.custom-ca
FROM debian:13-slim AS ca-builder

# Copy your custom CA certificate
COPY my-corporate-ca.crt /usr/local/share/ca-certificates/

# Update CA certificates bundle
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Extend the distroless CephaloProxy image
FROM cephaloproxy:latest

# Copy the updated CA bundle from builder
COPY --from=ca-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Metadata
LABEL custom-ca="true"
LABEL ca-update-date="2025-12-31"
```

Build your custom image:

```bash
docker build -t cephaloproxy:custom-ca -f Dockerfile.custom-ca .
```

### Method 2: Mount CA at Runtime (Alternative)

If your custom CA is in PEM format, you can mount it directly:

```bash
docker run -d \
  -v /path/to/custom-ca.crt:/etc/ssl/certs/custom-ca.crt:ro \
  -e SSL_CERT_FILE=/etc/ssl/certs/custom-ca.crt \
  cephaloproxy:distroless
```

**Note**: This method only works if your application respects `SSL_CERT_FILE`. For system-wide trust, use Method 1.

### Method 3: Bundle Multiple CAs

```dockerfile
# Dockerfile.multi-ca
FROM debian:13-slim AS ca-builder

# Copy all custom CAs
COPY certs/*.crt /usr/local/share/ca-certificates/

# Update CA bundle
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

FROM cephaloproxy:latest
COPY --from=ca-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
```

### Verification

Test that custom CAs are trusted:

```bash
# Start container with custom CA
docker run -d --name ca-test cephaloproxy:custom-ca

# Test TLS connection to internal service
docker exec ca-test curl https://internal.company.com

# Should succeed without certificate errors
```

---

## 4. Troubleshooting Without Shell

The distroless runtime image has **NO shell** (`/bin/sh`, `/bin/bash`) and **NO debugging tools** (`ps`, `top`, `netstat`, etc.). This is intentional for security but requires different troubleshooting approaches.

### Debug Container Pattern (Recommended)

Use an ephemeral debug container to inspect the distroless container:

```bash
# Start your distroless container
docker run -d --name cephaloproxy cephaloproxy:distroless

# Attach a debug container to the same PID namespace
docker run -it --rm \
  --pid=container:cephaloproxy \
  --network=container:cephaloproxy \
  debian:13-slim \
  /bin/bash

# Inside the debug container, you now have shell access
# and can inspect processes, network, filesystem
ps aux | grep squid
netstat -tlnp
ls -la /proc/*/fd
```

### Distroless Debug Variant (Alternative)

Google provides debug variants of distroless images with a busybox shell:

```dockerfile
# Use debug variant for troubleshooting
FROM gcr.io/distroless/python3-debian13:debug AS runtime
# ... rest of Dockerfile unchanged
```

**Warning**: Debug variants include a shell and should **NOT** be used in production. Use only for development/troubleshooting.

### Log Analysis Strategies

Since there's no shell, rely heavily on container logs:

```bash
# View real-time logs
docker logs -f cephaloproxy

# View logs with timestamps
docker logs -t cephaloproxy

# View last 100 lines
docker logs --tail 100 cephaloproxy

# Search logs for errors
docker logs cephaloproxy 2>&1 | grep -i error

# Export logs for analysis
docker logs cephaloproxy > cephaloproxy-logs.txt
```

### Python Logging Output

The distroless image uses Python logging for initialization scripts (FR-007):

- **Format**: Plain text with timestamps
- **Level**: INFO
- **Output**: stdout/stderr
- **Example**: `2025-12-31 10:30:45 [INFO] Cache directory validated: /var/spool/squid`

### Health Check Debugging

```bash
# Check health endpoint directly
curl -v http://localhost:8080/health

# Check ready endpoint
curl -v http://localhost:8080/ready

# Inspect health check failures
docker inspect cephaloproxy | jq '.[0].State.Health'
```

### Volume Mount Verification

If the container fails to start due to missing volumes (FR-005), check logs for specific error messages:

```bash
# Expected error format from init-squid.py:
# ERROR: Required volume not mounted: /var/spool/squid
# ERROR: cache_dir directive found in squid.conf but volume not writable

# Verify volumes are mounted
docker inspect cephaloproxy | jq '.[0].Mounts'
```

### Common Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Missing cache volume | `ERROR: Required volume not mounted: /var/spool/squid` | Mount `-v cache:/var/spool/squid` |
| Permission denied | `ERROR: Cache directory not writable` | Check volume permissions, ensure GID 0 compatibility |
| SSL-bump cert missing | `ERROR: TLS certificate not found: /etc/squid/ssl_cert/tls.crt` | Mount TLS secret to `/etc/squid/ssl_cert/` |
| Health check fails | Container marked unhealthy | Check port 8080 is exposed and health server started |
| Squid config invalid | Container fails validation | Check `docker logs` for config syntax errors |

### Container Inspection Without Shell

```bash
# Inspect running processes (from host)
docker top cephaloproxy

# Inspect filesystem
docker exec cephaloproxy ls /var/log/squid

# Copy files out for analysis
docker cp cephaloproxy:/var/log/squid/access.log ./access.log

# Inspect environment variables
docker exec cephaloproxy env

# Note: These commands work because they're executed by Docker, not by a shell inside the container
```

### Network Debugging

```bash
# Test proxy connectivity from host
curl -x http://localhost:3128 http://example.com -v

# Test from another container
docker run --rm --network container:cephaloproxy \
  curlimages/curl:latest \
  curl -x http://localhost:3128 http://example.com

# Inspect network settings
docker inspect cephaloproxy | jq '.[0].NetworkSettings'
```

---

## Quick Reference

### Essential Commands

```bash
# Build
docker build -t cephaloproxy:distroless .

# Run
docker run -d -p 3128:3128 -p 8080:8080 cephaloproxy:distroless

# Test
curl -x http://localhost:3128 http://example.com

# Health check
curl http://localhost:8080/health

# Logs
docker logs -f cephaloproxy

# Stop (graceful)
docker stop --time=30 cephaloproxy

# Debug
docker run -it --rm --pid=container:cephaloproxy debian:13-slim /bin/bash
```

### Performance Targets

| Metric | Current (Gentoo) | Target (Distroless) | Success Criteria |
|--------|------------------|---------------------|------------------|
| Image size | ~500MB | ≤300MB | ≥40% reduction (SC-001) |
| Package count | ~hundreds | <50 components | ≥80% reduction (SC-002) |
| CVE count | Baseline | 60%+ fewer | ≥60% reduction (SC-003) |
| Build time | 20-30 min | 6-9 min | ≥70% reduction (SC-008) |
| Startup time | Baseline | ≤110% | Max 10% increase (SC-005) |

---

## Additional Resources

- **Feature Specification**: [spec.md](spec.md)
- **Implementation Plan**: [plan.md](plan.md)
- **Research Findings**: [research.md](research.md)
- **Task Breakdown**: [tasks.md](tasks.md)
- **Dockerfile**: `/container/Dockerfile`
- **Integration Tests**: `/tests/integration/*.bats`

For questions or issues, refer to the troubleshooting section above or consult the implementation plan.
