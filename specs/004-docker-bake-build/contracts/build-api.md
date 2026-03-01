# Build API Contracts: Docker Bake

## Overview

This document defines the contracts for Docker Bake build commands and their
expected outputs. The "API" consists of build commands that can be executed and
their responses.

## Commands

### Multi-Platform Build


**Command**:

```bash
docker buildx bake
```

**Expected Behavior**:

- Builds container for both linux/amd64 and linux/arm64
- Uses cache from `cephaloproxy:buildcache`
- Exports cache to `cephaloproxy:buildcache` (max mode, zstd compression)
- Fails fast on any error with clear error message
- Fails immediately if Docker BuildKit not available

**Expected Output**:

```
[+] Building 120.5s (45/45) FINISHED
[+] Exporting cache to registry
[+] Exporting image to docker
cephaloproxy:latest (linux/amd64)
cephaloproxy:latest (linux/arm64)
cephaloproxy:buildcache
```

**Error Response**:

```
Error: Docker BuildKit is disabled. Set DOCKER_BUILDKIT=1 or create a buildx builder.
```

### Single Platform Build (amd64)

**Command**:

```bash
docker buildx bake --set *.platform=linux/amd64
```

**Expected Behavior**:

- Builds container for linux/amd64 only
- Uses cache from `cephaloproxy:buildcache`
- Exports cache to `cephaloproxy:buildcache-amd64`
- Fails fast on any error

**Expected Output**:

```
[+] Building 60.2s (35/35) FINISHED
[+] Exporting cache to registry
[+] Exporting image to docker
cephaloproxy:amd64-latest
cephaloproxy:amd64-latest
cephaloproxy:buildcache-amd64
```

### Single Platform Build (arm64)

**Command**:

```bash
docker buildx bake --set *.platform=linux/arm64
```

**Expected Behavior**:

- Builds container for linux/arm64 only
- Uses cache from `cephaloproxy:buildcache`
- Exports cache to `cephaloproxy:buildcache-arm64`
- Fails fast on any error

**Expected Output**:

```
[+] Building 65.1s (36/36) FINISHED
[+] Exporting cache to registry
[+] Exporting image to docker
cephaloproxy:arm64-latest
cephaloproxy:arm64-latest
cephaloproxy:buildcache-arm64
```

### Development Build

**Command**:

```bash
docker buildx bake dev
```

**Expected Behavior**:

- Builds container for linux/amd64 only (for development)
- Uses local and registry cache
- Exports to local cache for faster subsequent builds
- Fails fast on any error

**Expected Output**:

```
[+] Building 58.3s (34/34) FINISHED
[+] Exporting cache to local
[+] Exporting image to docker
cephaloproxy:dev
```

### Override Base Image Version

**Command**:

```bash
docker buildx bake \
  --var DISTROLESS_BASE=gcr.io/distroless/python3-debian13 \
  --var DEBIAN_VERSION=13
```

**Expected Behavior**:

- Builds container with custom base image
- Passes custom values via variables
- Fails fast if base image not found

**Expected Output**:

```
[+] Building 115.8s (42/42) FINISHED
[+] Exporting cache to registry
[+] Exporting image to docker
cephaloproxy:latest
cephaloproxy:latest
cephaloproxy:buildcache
```

## Target References

### Base Target

**Target**: `base`

**Description**: Base target with common settings

**Configuration**:

- Context: `./container`
- Dockerfile: `Dockerfile.distroless`
- Args: DISTROLESS_BASE, DISTROLESS_BASE_SHA, DEBIAN_VERSION, BUILDPLATFORM,
  TARGETPLATFORM
- Cache from: `cephaloproxy:buildcache`

**Usage**: Inherited by other targets

### Multi-Platform Target

**Target**: `cephaloproxy`

**Description**: Main target for multi-platform builds

**Configuration**:

- Inherits: `base`
- Platforms: `linux/amd64`, `linux/arm64`
- Tags: `cephaloproxy:latest`, `cephaloproxy:${VERSION}`
- Cache to: `cephaloproxy:buildcache,mode=max,compression=zstd`

**Usage**: Default target for `docker buildx bake`

### Single Platform Targets

**Target**: `amd64-only`

**Description**: amd64-only build target

**Configuration**:

- Inherits: `base`
- Platforms: `linux/amd64`
- Tags: `cephaloproxy:amd64-latest`, `cephaloproxy:amd64-${VERSION}`
- Cache to: `cephaloproxy:buildcache-amd64,mode=max,compression=zstd`

**Target**: `arm64-only`

**Description**: arm64-only build target

**Configuration**:

- Inherits: `base`
- Platforms: `linux/arm64`
- Tags: `cephaloproxy:arm64-latest`, `cephaloproxy:arm64-${VERSION}`
- Cache to: `cephaloproxy:buildcache-arm64,mode=max,compression=zstd`

**Usage**: For testing individual platforms

### Development Target

**Target**: `dev`

**Description**: Local development build

**Configuration**:

- Inherits: `base`
- Platforms: `linux/amd64`
- Tags: `cephaloproxy:dev`
- Cache from: `cephaloproxy:buildcache`,
  `type=local,src=/tmp/docker-build-cache`
- Cache to: `type=local,dest=/tmp/docker-build-cache-new`

**Usage**: Local development with local cache

## Groups

### Default Group

**Group**: `default`

**Targets**: `cephaloproxy`

**Description**: Default group for multi-platform build

### Single Platform Group

**Group**: `single-platform`

**Targets**: `amd64-only`, `arm64-only`

**Description**: Group for single-platform builds

### Development Group

**Group**: `dev`

**Targets**: `dev`

**Description**: Group for development builds

## Expected Errors

### BuildKit Not Available

**Error Message**:

```
Error: Docker BuildKit is disabled. Set DOCKER_BUILDKIT=1 or create a buildx builder.
```

**Exit Code**: 1

**Recovery**: Enable BuildKit or create buildx builder

### Invalid Base Image

**Error Message**:

```
Error: Failed to pull base image gcr.io/distroless/python3-debian13@sha256:invalid
```

**Exit Code**: 1

**Recovery**: Check base image name and SHA

### Invalid ARG Value

**Error Message**:

```
Error: ARG DISTROLESS_BASE is required but not set
```

**Exit Code**: 1

**Recovery**: Set required ARG via --var flag

### Missing Dockerfile

**Error Message**:

```
Error: No such file or directory: container/Dockerfile.distroless
```

**Exit Code**: 1

**Recovery**: Verify Dockerfile path

### Platform Not Supported

**Error Message**:

```
Error: Requested platform linux/arm/v7 is not supported by Dockerfile
```

**Exit Code**: 1

**Recovery**: Use supported platform (linux/amd64, linux/arm64)

## Output Schema

### Success Output

```json
{
  "status": "success",
  "targets": {
    "cephaloproxy": {
      "platforms": ["linux/amd64", "linux/arm64"],
      "tags": ["cephaloproxy:latest"],
      "cache": ["cephaloproxy:buildcache"]
    }
  },
  "duration_ms": 120500
}
```

### Error Output

```json
{
  "status": "error",
  "error": "Error: Docker BuildKit is disabled...",
  "exit_code": 1
}
```

## Integration Points

### GitHub Actions

**Before Build**:

```yaml
- name: Check BuildKit availability
  run: |
    if [ -n "$BUILDKIT_DISABLE" ]; then
      echo "Error: Docker BuildKit is disabled"
      exit 1
    fi
    docker buildx version
```

**Build Command**:

```yaml
- name: Build multi-platform container image
  run: docker buildx bake
```

**Expected Artifact**:

- Container image loaded into Docker daemon
- Build cache pushed to registry

### Docker Compose

**Reference**: `docker-compose.production.yml` can reference build targets:

```yaml
services:
  squid:
    image: cephaloproxy:latest
    build:
      target: cephaloproxy
```

### Local Development

**Command**: `docker buildx bake dev`

**Expected Behavior**:

- Build completes in ~60 seconds
- Cache exported to `/tmp/docker-build-cache-new`
- Image tagged as `cephaloproxy:dev`

## Validation

### Syntax Validation

**Command**:

```bash
docker buildx bake --print
```

**Expected Output**: Valid HCL syntax, no errors

### Target Validation

**Command**:

```bash
docker buildx bake --list=targets
```

**Expected Output**: List of all defined targets

### Cache Validation

**Command**:

```bash
docker buildx bake --progress=plain
```

**Expected Output**: Detailed build logs with cache status

## Versioning

The build API is version-agnostic. The Dockerfile maintains compatibility with
any Docker version that supports BuildKit. The bake configuration is backward
compatible with existing Dockerfiles.
