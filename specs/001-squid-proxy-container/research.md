# Research: Squid Proxy Container

**Feature**: 001-squid-proxy-container
**Date**: 2025-11-11
**Purpose**: Resolve technical clarifications for Gentoo-based Squid container with SSL-bump support

## Research Tasks

### 1. Squid Version Pinning

**Decision**: Pin to Squid 6.x (latest stable)

**Rationale**:
- Squid 6.x is the current stable branch with active security support
- Includes mature SSL-bump implementation (ssl_crtd)
- Well-documented in Gentoo Portage
- Performance improvements over 5.x series
- Long-term support expected through 2026+

**Alternatives Considered**:
- Squid 5.x: Older stable, but approaching EOL
- Squid 7.x: Development branch, not suitable for production pinning
- Specific version pinning (e.g., 6.6): Will use Portage slot pinning (net-proxy/squid:6) for major version while allowing minor/patch updates for security

**Implementation**: Use Portage package.accept_keywords and package.mask to pin `=net-proxy/squid-6*` in Dockerfile

---

### 2. Health Check Implementation Approach

**Decision**: Standalone Python HTTP server (healthcheck.py)

**Rationale**:
- Squid does not expose native HTTP health check endpoints suitable for orchestrators
- Squid's cachemgr.cgi requires configuration and is not designed for liveness/readiness checks
- Lightweight Python HTTP server adds <10MB to image, minimal runtime overhead (<5MB memory)
- Can perform actual Squid health validation (check process, test cache dirs, validate config)
- Provides separate /health (liveness) and /ready (readiness) semantics required by Kubernetes/OpenShift

**Alternatives Considered**:
- Shell script with nc (netcat): Limited HTTP protocol support, harder to parse requests for /health vs /ready
- Squid cachemgr: Not designed for this use case, security implications of exposing management interface
- External sidecar container: Adds deployment complexity, violates single-container principle

**Implementation**:
```python
# healthcheck.py (simplified example)
from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess
import os

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            # Liveness: Is Squid process running?
            if subprocess.run(['pgrep', 'squid'], capture_output=True).returncode == 0:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'OK')
            else:
                self.send_response(503)
                self.end_headers()
        elif self.path == '/ready':
            # Readiness: Is Squid ready to accept traffic?
            # Check cache dirs exist and are writable
            if os.path.isdir('/var/spool/squid') and os.access('/var/spool/squid', os.W_OK):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'READY')
            else:
                self.send_response(503)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(('', 8080), HealthCheckHandler).serve_forever()
```

---

### 3. Container Testing Framework

**Decision**: Shell-based integration tests (bash/bats) with Docker Compose for fixtures

**Rationale**:
- Container testing requires Docker runtime - shell scripts are simplest approach
- bats (Bash Automated Testing System) provides structured test framework
- Docker Compose allows multi-container test scenarios (proxy + client + upstream server)
- No additional language dependencies in CI/CD pipeline
- Easy to run locally: `./tests/integration/test_basic_proxy.sh`

**Alternatives Considered**:
- pytest with docker-py: Adds Python dependency, more complex for simple container tests
- Go-based container testing (testcontainers): Requires Go toolchain in CI
- Dockerfile RUN tests: Cannot test runtime behavior, volume mounts, networking

**Implementation Pattern**:
```bash
#!/usr/bin/env bats
# tests/integration/test_basic_proxy.sh

@test "Container starts with default config" {
    docker run -d --name test-squid -p 3128:3128 cephaloproxy:test
    sleep 5
    docker ps | grep test-squid
    docker stop test-squid && docker rm test-squid
}

@test "Proxy forwards HTTP requests" {
    docker run -d --name test-squid -p 3128:3128 cephaloproxy:test
    sleep 5
    curl -x http://localhost:3128 http://example.com -I
    docker stop test-squid && docker rm test-squid
}
```

---

### 4. Gentoo Portage Best Practices for Containers

**Research Finding**: Minimal Gentoo container build strategy

**Key Practices**:
1. **Multi-stage builds**: Compile in builder stage, copy binaries to runtime stage
2. **Portage cleanup**: Remove `/var/db/repos/gentoo` after package installation
3. **Package selection**: Use `--oneshot` for build dependencies to avoid world file bloat
4. **Binary packages**: Consider using binpkgs for common deps (OpenSSL) to speed rebuilds
5. **Layering**: Group related packages in single RUN commands to minimize layers

**Example Dockerfile Structure**:
```dockerfile
# Stage 1: Builder
FROM gentoo/stage3:latest AS builder
COPY --from=gentoo/portage:latest /var/db/repos/gentoo /var/db/repos/gentoo

# Install build dependencies
RUN emerge --oneshot sys-devel/gcc dev-libs/openssl

# Install Squid with SSL-bump support
RUN echo "net-proxy/squid ssl" >> /etc/portage/package.use/squid && \
    emerge =net-proxy/squid-6* && \
    # Cleanup
    rm -rf /var/db/repos/gentoo /var/cache/distfiles/*

# Stage 2: Runtime
FROM gentoo/stage3:latest
COPY --from=builder /usr/bin/squid /usr/bin/squid
COPY --from=builder /usr/lib64/squid /usr/lib64/squid
# ... copy necessary runtime files only
```

---

### 5. OpenShift Random UID/GID Support

**Research Finding**: OpenShift security context constraints (SCC) and arbitrary UIDs

**Key Requirements**:
1. **No hardcoded UID**: OpenShift assigns random UID in range 1000000000-2000000000
2. **GID 0 (root group)**: OpenShift always assigns GID 0, but without root privileges
3. **Directory permissions**: All writable paths must be group-writable (chmod g+w)
4. **Entrypoint flexibility**: Must not assume specific UID in scripts

**Implementation Strategy**:
- Set USER 1000 in Dockerfile (ignored by OpenShift, used by Docker/Podman)
- Make all data directories group-writable: `/var/spool/squid`, `/var/log/squid`, `/tmp`
- Use `chgrp -R 0` and `chmod -R g=u` for writable paths
- Entrypoint script detects UID at runtime: `id -u` and adjusts behavior

**Example Entrypoint Pattern**:
```bash
#!/bin/bash
# entrypoint.sh

# OpenShift compatibility: Detect arbitrary UID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "Running as UID:${CURRENT_UID} GID:${CURRENT_GID}"

# Ensure cache directory is writable
if [ ! -w /var/spool/squid ]; then
    echo "ERROR: /var/spool/squid not writable for UID ${CURRENT_UID}"
    exit 1
fi

# Initialize cache if needed
if [ ! -d /var/spool/squid/00 ]; then
    squid -z  # Initialize cache directories
fi

# Start Squid
exec squid -N  # -N: no daemon mode (foreground)
```

---

### 6. Squid SSL-Bump Compilation Flags

**Research Finding**: Required USE flags and dependencies for SSL-bump in Gentoo

**Portage Configuration**:
```bash
# /etc/portage/package.use/squid
net-proxy/squid ssl ssl-crtd

# Dependencies automatically pulled:
# - dev-libs/openssl
# - dev-libs/libltdl
```

**Squid Configuration Requirements**:
- `ssl_crtd` helper program for dynamic certificate generation
- SSL database directory: `/var/lib/squid/ssl_db`
- Must initialize SSL DB: `ssl_crtd -c -s /var/lib/squid/ssl_db`

**Compile-time verification**:
```bash
squid -v | grep -i ssl
# Expected output: --enable-ssl --enable-ssl-crtd
```

---

## Summary of Decisions

| Item | Decision | Impact |
|------|----------|--------|
| Squid Version | Pin to Squid 6.x via Portage slot | Stable SSL-bump, security support |
| Health Checks | Python HTTP server (healthcheck.py) | 8080/health and /ready endpoints |
| Testing | Bash/bats integration tests | Simple, no extra dependencies |
| Base Image | gentoo/stage3 multi-stage | Compile-time SSL-bump support |
| OpenShift Support | Group-writable dirs, flexible UID | Arbitrary UID/GID compatibility |
| Portage Strategy | Multi-stage build with cleanup | Minimal final image size |

## Next Steps

Phase 1 artifacts to generate:
1. **data-model.md**: Configuration file structures, volume mount specifications
2. **contracts/**: Health check API specifications (HTTP endpoints)
3. **quickstart.md**: Quick deployment guide for Docker, Kubernetes, OpenShift
