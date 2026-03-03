# CephaloProxy - Squid Proxy Container

A containerized Squid proxy with SSL-bump support for HTTPS caching, traffic
filtering via ACLs, and flexible configuration.

## Features

- **Zero-configuration deployment**: Works out of the box with sensible defaults
- **HTTPS caching**: SSL-bump support for decrypting and caching HTTPS traffic
- **Traffic filtering**: ACL-based domain blocking and access control
- **Health checks**: HTTP endpoints for Kubernetes/OpenShift liveness and
  readiness probes
- **OpenShift compatible**: Supports arbitrary UID/GID for security context
  constraints
- **Production-ready**: Non-root execution, graceful shutdown, configuration
  validation

## Quick Start

See the [deployment guide](docs/deployment.md) for detailed deployment
instructions.

## Building with Docker Bake

The CephaloProxy container supports Docker Bake for multi-platform builds and
optimized caching. Docker Bake is enabled by default in modern Docker versions.

### Prerequisites

- Docker Engine 20.10+ with BuildKit support
- Docker BuildKit enabled (default in modern Docker versions)

### Build Commands

#### Build for All Platforms (Recommended for CI/CD)

```bash
docker buildx bake
```

Builds for both linux/amd64 and linux/arm64 with GitHub Actions cache
integration.

**Cache Backend**: GitHub Actions cache (gha backend)

- Native CI/CD integration
- Persists across workflow runs
- No registry access required
- Max mode with zstd compression for optimal cache size

#### Build for Single Platform (Testing)

```bash
# Build for amd64 only
docker buildx bake amd64-only

# Build for arm64 only
docker buildx bake arm64-only
```

#### Local Development Build

```bash
docker buildx bake dev
```

Builds for amd64 only with local cache for faster rebuilds.

**Cache Backend**: Local filesystem cache (local backend)

- Full control over cache location
- Faster than registry-based cache
- Exported to `/tmp/docker-build-cache-new` for reuse
- Not pushed to registry - use only for local development

#### Override Base Image Version

```bash
docker buildx bake \
  --var DISTROLESS_BASE=gcr.io/distroless/python3-debian13 \
  --var DEBIAN_VERSION=13
```

### Build Targets

| Target | Platforms | Description |
|--------|-----------|-------------|
| `cephaloproxy` | amd64, arm64 | Multi-platform main target |
| `amd64-only` | amd64 | Single platform for testing |
| `arm64-only` | arm64 | Single platform for testing |
| `dev` | amd64 | Development build with local cache |

See
[specs/004-docker-bake-build/quickstart.md](specs/004-docker-bake-build/quickstart.md)
for detailed build instructions and troubleshooting.

### Basic Usage (Docker)

```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  cephaloproxy:latest

# Test the proxy
export http_proxy=http://localhost:3128
curl -I http://example.com
```

### Health Checks

```bash
curl http://localhost:8080/health  # Liveness probe
curl http://localhost:8080/ready   # Readiness probe
```

## Configuration

- **Default mode**: No volumes required, ephemeral cache in /tmp
- **Custom config**: Mount your own squid.conf at `/etc/squid/squid.conf`
- **ACL filtering**: Mount ACL files to `/etc/squid/conf.d/`
- **SSL-bump**: Mount CA certificate to `/etc/squid/ssl_cert/`
- **Persistent cache**: Mount volume to `/var/spool/squid`

## Documentation

- [Deployment Guide](docs/deployment.md) - Docker, Kubernetes, OpenShift
  deployment
- [Configuration Reference](docs/configuration.md) - All configuration options
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Constitutional Compliance

This project adheres to the
[CephaloProxy Constitution](specs/001-squid-proxy-container/plan.md#constitution-check):

- **Container-First Architecture**: ✅ Fully containerized with multi-stage
  Dockerfile, health checks, graceful shutdown
- **Test-First Development**: ✅ Integration tests organized by user story, TDD
  workflow
- **Squid Proxy Integration**: ✅ Squid 6.x pinned, declarative configuration,
  validation on startup
- **Security by Default**: ✅ Non-root user (UID 1000/GID 0), secrets via
  volumes, no hardcoded credentials
- **Observable by Default**: ✅ Health endpoints (/health, /ready), Squid access
  and cache logs

## Architecture

Built on Gentoo Linux to compile Squid with SSL-bump support (not available in
most binary distributions).

### Ports

- **3128**: Squid proxy (HTTP/HTTPS)
- **8080**: Health check HTTP server

### Volume Mounts

| Path | Purpose | Required |
| ---- | ------- | -------- |
| `/etc/squid/squid.conf` | Custom configuration | Optional |
| `/etc/squid/conf.d/` | ACL files | Optional |
| `/etc/squid/ssl_cert/` | TLS secret (tls.crt, tls.key) | Required for SSL-bump |
| `/var/spool/squid` | Persistent cache | Required if `cache_dir` configured* |

- If your `squid.conf` contains a `cache_dir` directive, the cache volume
  **must** be mounted and writable. Omit `cache_dir` for pure proxy mode (no
  caching).

## Performance

- Startup time: < 10 seconds
- Throughput: 1000+ req/s
- Latency overhead: < 50ms (P95)
- Cache hit rate: > 40% (typical workloads)
- Memory: < 512MB baseline

## Security

- Runs as non-root user (UID 1000)
- OpenShift arbitrary UID support (GID 0)
- TLS 1.2+ for encrypted traffic
- Configuration validation on startup
- No hardcoded credentials

## License

- [GNU GENERAL PUBLIC LICENSE v3](LICENSE.md)

## Contributing

- To Do
