# Multi-Platform Build Support

## Overview

The distroless container supports both **amd64 (x86_64)** and **arm64 (aarch64)** architectures through Docker buildx multi-platform builds.

## Architecture Detection

The Dockerfile uses wildcards to automatically detect and copy the correct architecture-specific libraries:

```dockerfile
# Works for both aarch64-linux-gnu (arm64) and x86_64-linux-gnu (amd64)
COPY --from=squid-builder --chmod=644 /usr/lib/*-linux-gnu*/libnettle.so.8* /usr/lib/
```

This approach:
- ✅ No hardcoded architecture paths
- ✅ Works for both development (Mac ARM64) and production (Linux x86_64)
- ✅ Single Dockerfile for all platforms
- ✅ No build-time conditionals needed

## Building for Multiple Platforms

### Quick Start

```bash
# Build for current platform only (fast, loads into local Docker)
./container/build-multiplatform.sh --load

# Build for both amd64 and arm64 and push to registry
./container/build-multiplatform.sh \
    --registry ghcr.io/opsreformation \
    --platform linux/amd64,linux/arm64 \
    --tag latest \
    --push

# Build for specific registry (e.g., Quay.io)
./container/build-multiplatform.sh \
    --registry quay.io/myorg \
    --image cephaloproxy \
    --platform linux/amd64,linux/arm64 \
    --tag v1.0.0 \
    --push
```

### Manual Build Commands

```bash
# Create buildx builder (one-time setup)
docker buildx create --name cephaloproxy-builder --use
docker buildx inspect --bootstrap

# Build for both platforms and push to registry
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --file container/Dockerfile.distroless \
    --tag ghcr.io/opsreformation/cephaloproxy:distroless \
    --push \
    .

# Build for single platform and load locally
docker buildx build \
    --platform linux/arm64 \
    --file container/Dockerfile.distroless \
    --tag cephaloproxy:distroless \
    --load \
    .
```

## Platform-Specific Details

### ARM64 (aarch64-linux-gnu)
- **Development**: Mac with Apple Silicon
- **Library path**: `/usr/lib/aarch64-linux-gnu/`
- **Use case**: Local development, AWS Graviton, Raspberry Pi

### AMD64 (x86_64-linux-gnu)
- **Production**: Most Linux servers, cloud VMs
- **Library path**: `/usr/lib/x86_64-linux-gnu/`
- **Use case**: Production deployments, CI/CD, x86 servers

## OpenShift Compatibility

Both architectures maintain OpenShift compatibility through:

```dockerfile
# Set ownership: UID 1000, GID 0 (root group for OpenShift)
chown -R 1000:0 /runtime

# chmod g=u ensures group has same permissions as user (critical for OpenShift)
chmod -R g=u \
    /runtime/var/spool/squid \
    /runtime/var/log/squid \
    /runtime/var/lib/squid \
    ...
```

The `chmod -R g=u` pattern ensures:
- ✅ Group (GID 0) has same permissions as owner (UID 1000)
- ✅ OpenShift arbitrary UID (e.g., UID 1001234) in GID 0 can write
- ✅ Works for both Docker (UID 1000) and OpenShift (arbitrary UID)

## Verification

### Check Built Platform

```bash
# Inspect image metadata
docker buildx imagetools inspect cephaloproxy:distroless

# Expected output shows both platforms:
# Name:      cephaloproxy:distroless
# MediaType: application/vnd.docker.distribution.manifest.list.v2+json
# Digest:    sha256:...
# Manifests:
#   Name:      cephaloproxy:distroless@sha256:...
#   MediaType: application/vnd.docker.distribution.manifest.v2+json
#   Platform:  linux/amd64
#
#   Name:      cephaloproxy:distroless@sha256:...
#   MediaType: application/vnd.docker.distribution.manifest.v2+json
#   Platform:  linux/arm64
```

### Test on Different Architectures

```bash
# Force run on specific platform (useful for testing)
docker run --platform linux/amd64 --rm cephaloproxy:distroless /usr/sbin/squid -v
docker run --platform linux/arm64 --rm cephaloproxy:distroless /usr/sbin/squid -v
```

## CI/CD Integration

For GitHub Actions, GitLab CI, or other CI systems:

```yaml
# Example GitHub Actions
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v2

- name: Build and push multi-platform image
  uses: docker/build-push-action@v4
  with:
    context: .
    file: container/Dockerfile.distroless
    platforms: linux/amd64,linux/arm64
    push: true
    tags: |
      ghcr.io/opsreformation/cephaloproxy:latest
      ghcr.io/opsreformation/cephaloproxy:distroless
```

## Troubleshooting

### Issue: "multiple platforms feature is currently not supported"

**Solution**: Enable Docker buildx:
```bash
docker buildx install  # Install buildx as default builder
docker buildx ls       # Verify buildx is available
```

### Issue: "failed to solve: failed to copy files"

**Problem**: Library paths don't match architecture

**Solution**: Verify wildcard pattern matches:
```bash
# Check what libraries exist in builder stage
docker build --target squid-builder -t test-builder -f container/Dockerfile.distroless .
docker run --rm test-builder ls -la /usr/lib/*-linux-gnu*/libnettle*
```

### Issue: "--load and --push are not compatible"

**Solution**: Use `--load` for single platform only, `--push` for multi-platform:
```bash
# Single platform + load (development)
docker buildx build --platform linux/arm64 --load ...

# Multi-platform + push (production)
docker buildx build --platform linux/amd64,linux/arm64 --push ...
```

## Performance Notes

- **Single platform build**: ~2-3 minutes (cached)
- **Multi-platform build**: ~4-6 minutes (cached)
- **First build**: ~10-15 minutes (no cache)

Multi-platform builds are slower because Docker must build each architecture separately and create a manifest list.

## References

- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [Multi-platform images](https://docs.docker.com/build/building/multi-platform/)
- [OpenShift Arbitrary User IDs](https://docs.openshift.com/container-platform/4.12/openshift_images/create-images.html#images-create-guide-openshift_create-images)
