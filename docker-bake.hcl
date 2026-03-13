# Docker Bake Configuration for CephaloProxy
# Multi-platform container build system using Docker BuildKit
# Reference: specs/004-docker-bake-build/

# Version variable for tagging
variable "VERSION" {
  default = "latest"
}

# =============================================================================
# Base Target - Common settings inherited by all other targets
# =============================================================================
target "base" {
  context    = "."
  dockerfile = "container/Dockerfile.distroless"

  # Build arguments for base image configuration
  # Note: BUILDPLATFORM and TARGETPLATFORM are set automatically by BuildKit
  # from the target's platforms list — do not hardcode them here.
  args = {
    DISTROLESS_BASE     = "gcr.io/distroless/python3-debian12"
    DISTROLESS_BASE_SHA = "sha256:8ce6bba3f793ba7d834467dfe18983c42f9b223604970273e9e3a22b1891fc27"
    DEBIAN_VERSION      = "12"
  }
}

# =============================================================================
# CI target: amd64 — single-platform, loads into Docker daemon for testing
# =============================================================================
target "amd64-only" {
  inherits  = ["base"]
  platforms = ["linux/amd64"]
  tags      = ["cephaloproxy:latest", "cephaloproxy:amd64-${VERSION}"]
  load      = true

  # Scoped per-platform so amd64 and arm64 cache entries don't collide
  cache-from = ["type=gha,scope=linux/amd64"]
  cache-to   = ["type=gha,mode=max,scope=linux/amd64"]
}

# =============================================================================
# CI target: arm64 — single-platform, loads into Docker daemon for testing
# =============================================================================
target "arm64-only" {
  inherits  = ["base"]
  platforms = ["linux/arm64"]
  tags      = ["cephaloproxy:latest", "cephaloproxy:arm64-${VERSION}"]
  load      = true

  cache-from = ["type=gha,scope=linux/arm64"]
  cache-to   = ["type=gha,mode=max,scope=linux/arm64"]
}

# =============================================================================
# Release target: multi-platform push to registry
# load = true is intentionally absent — multi-platform images cannot be loaded
# into the local Docker daemon; they must be pushed directly to a registry.
# =============================================================================
target "cephaloproxy" {
  inherits  = ["base"]
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["cephaloproxy:latest", "cephaloproxy:${VERSION}"]

  cache-from = ["type=gha,scope=linux/amd64", "type=gha,scope=linux/arm64"]
  cache-to   = ["type=gha,mode=max,scope=linux/amd64", "type=gha,mode=max,scope=linux/arm64"]
}

# =============================================================================
# Development target: local build with local filesystem cache
# =============================================================================
target "dev" {
  inherits  = ["base"]
  platforms = ["linux/amd64"]
  tags      = ["cephaloproxy:dev"]
  load      = true

  cache-from = ["type=local,src=/tmp/docker-build-cache"]
  cache-to   = ["type=local,dest=/tmp/docker-build-cache-new,mode=max"]
}

# =============================================================================
# Build Groups
# =============================================================================

# Default group — multi-platform release build (push only, no load)
group "default" {
  targets = ["cephaloproxy"]
}

# CI group — builds each platform separately so images can be loaded and tested
group "ci" {
  targets = ["amd64-only", "arm64-only"]
}

# Development group — local amd64 build with local cache
group "dev" {
  targets = ["dev"]
}
