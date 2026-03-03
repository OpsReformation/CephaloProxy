# Quick Start Guide: Docker Bake

## Overview

This guide provides quick instructions for building the CephaloProxy container
using Docker Bake. Docker Bake allows you to build multi-platform containers
(amd64, arm64) with a single command.

## Prerequisites

- Docker Engine 20.10+ with BuildKit support
- Docker BuildKit enabled (default in modern Docker versions)
- At least 2GB free disk space for cache
- Internet connection for pulling base images

## Quick Build Commands

### Build for All Platforms (Recommended for CI/CD)

```bash
docker buildx bake
```

**What this does**:

- Builds for both linux/amd64 and linux/arm64
- Uses registry cache for faster builds
- Exports cache for future builds

**Expected time**: ~120 seconds

### Build for Single Platform (Testing)

```bash
# Build for amd64 only
docker buildx bake amd64-only

# Build for arm64 only
docker buildx bake arm64-only
```

**What this does**:

- Builds for a single architecture
- Useful for testing before full multi-platform build

**Expected time**: ~60 seconds

### Local Development Build

```bash
docker buildx bake dev
```

**What this does**:

- Builds for amd64 only
- Uses local cache for faster rebuilds
- Exports cache to `/tmp/docker-build-cache-new`

**Expected time**: ~60 seconds

## Registry-Based Cache

By default, Docker Bake uses registry-based caching. This means:

- Cache is stored in your container registry
- Cache persists across builds
- Cache is shared across platforms
- No local cache management needed

**Example Registry**: GitHub Container Registry

```bash
# Build with custom registry
docker buildx bake --set REGISTRY=myregistry.io/cephaloproxy
```

## Local Cache (Development)

If you want to use local cache for faster builds:

```bash
# Create local cache directory
mkdir -p /tmp/docker-build-cache

# Build with local cache
docker buildx bake dev
```

**Note**: Local cache is not pushed to registry. Use it only for local
development.

## Base Image Overrides

You can override the base image version:

```bash
# Use Debian 13 (if available)
docker buildx bake \
  --var DISTROLESS_BASE=gcr.io/distroless/python3-debian13 \
  --var DEBIAN_VERSION=13
```

## Build Targets

Docker Bake defines several targets:

| Target | Platforms | Description |
|--------|-----------|-------------|
| `base` | - | Base settings, inherited by others |
| `cephaloproxy` | amd64, arm64 | Multi-platform main target |
| `amd64-only` | amd64 | Single platform for testing |
| `arm64-only` | arm64 | Single platform for testing |
| `dev` | amd64 | Development build with local cache |

**List all targets**:

```bash
docker buildx bake --list=targets
```

## Build Groups

**Default group** (multi-platform):

```bash
docker buildx bake
```

**Development group**:

```bash
docker buildx bake dev
```

## Verification

### Verify Build Success

```bash
# Check built images
docker images | grep cephaloproxy

# Expected output:
# cephaloproxy    latest    <digest>    <size>    ...
# cephaloproxy    buildcache    <digest>    <size>    ...
```

### Test Container

```bash
# Run container
docker run -d --name test-squid -p 3128:3128 -p 8080:8080 cephaloproxy:latest

# Wait for startup
sleep 10

# Check health endpoint
curl http://localhost:8080/health

# Check proxy functionality
curl -x http://localhost:3128 -I http://example.com

# Cleanup
docker stop test-squid
docker rm test-squid
```

### Verify Cache

```bash
# Check build cache in registry
docker buildx du

# Expected output:
# NAME                        SIZE     PLATFORMS
# cephaloproxy:buildcache     500MB    linux/amd64, linux/arm64
```

## Troubleshooting

### BuildKit Not Available

**Error**:

```
Error: Docker BuildKit is disabled. Set DOCKER_BUILDKIT=1 or create a buildx builder.
```

**Solution**:

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Or create buildx builder
docker buildx create --name buildkit --use --driver=docker
```

### Base Image Not Found

**Error**:

```
Error: failed to solve: gcr.io/distroless/python3-debian12@sha256:invalid
```

**Solution**: Check base image name and SHA in `docker-bake.hcl`

### Permission Denied

**Error**:

```
Error: permission denied while trying to connect to the Docker daemon socket
```

**Solution**: Run with appropriate permissions or add user to docker group

### Cache Issues

**Symptom**: Build takes too long or doesn't use cache

**Solution**:

```bash
# Clear build cache
docker buildx prune

# Force rebuild
docker buildx bake --no-cache
```

## Best Practices

1. **Always use BuildKit**: `export DOCKER_BUILDKIT=1`
2. **Use multi-platform builds** in CI/CD for production
3. **Test single platforms** before full multi-platform builds
4. **Use registry cache** for CI/CD environments
5. **Use local cache** for local development
6. **Monitor cache size**: `docker buildx du`
7. **Clean up cache periodically**: `docker buildx prune`

## Advanced Usage

### Dry Run

```bash
docker buildx bake --print
```

**Shows**: Validated configuration without building

### Progress Output

```bash
docker buildx bake --progress=plain
```

**Shows**: Detailed build logs with cache status

### Override Multiple Variables

```bash
docker buildx bake \
  --var REGISTRY=myregistry.io/cephaloproxy \
  --var VERSION=1.0.0 \
  --var DEBIAN_VERSION=12
```

### Build Specific Target

```bash
docker buildx bake amd64-only
```

### Check BuildKit Status

```bash
docker buildx version
docker buildx ls
docker buildx inspect default
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Build container
  run: docker buildx bake

- name: Push to registry
  run: docker buildx bake --push
```

### Docker Compose Example

```yaml
services:
  squid:
    image: cephaloproxy:latest
    build:
      target: cephaloproxy
```

## Next Steps

- Review [data-model.md](./data-model.md) for configuration details
- Review [build-api.md](./contracts/build-api.md) for API contracts
- Update [README.md](../README.md) with these commands
- Update `.github/workflows/build-and-test.yml` to use Docker Bake
