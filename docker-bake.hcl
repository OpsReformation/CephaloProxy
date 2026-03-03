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
  context = "."
  dockerfile = "container/Dockerfile.distroless"

  # Build arguments for platform detection and base image configuration
  args = {
    DISTROLESS_BASE = "gcr.io/distroless/python3-debian12"
    DISTROLESS_BASE_SHA = "sha256:8ce6bba3f793ba7d834467dfe18983c42f9b223604970273e9e3a22b1891fc27"
    DEBIAN_VERSION = "12"
    BUILDPLATFORM = "linux/amd64"
    TARGETPLATFORM = "linux/amd64"
  }

  # No cache configuration on base target - cache is configured in child targets
}

# =============================================================================
# User Story 1: Multi-platform builds (P1) - MVP
# =============================================================================
target "cephaloproxy" {
  inherits = ["base"]

  # Build for both amd64 and arm64 platforms
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]

  # Tags for the built images
  tags = [
    "cephaloproxy:latest",
    "cephaloproxy:${VERSION}"
  ]

  # Cache configuration for GitHub Actions CI/CD
  # Uses GitHub Actions cache backend with max mode and zstd compression
  cache-from = [
    "type=gha"
  ]
  cache-to = [
    "type=gha,mode=max,compression=zstd"
  ]

  # Load the image into Docker daemon for testing and local use
  load = true
}

# =============================================================================
# User Story 2: Development builds with local cache
# =============================================================================
target "dev" {
  inherits = ["base"]

  # Build for amd64 only (development environment)
  platforms = [
    "linux/amd64"
  ]

  # Development tag
  tags = [
    "cephaloproxy:dev"
  ]

  # Cache configuration for local development
  # Uses both GitHub Actions cache and local cache for faster builds
  cache-from = [
    "type=gha",
    "type=local,src=/tmp/docker-build-cache"
  ]
  cache-to = [
    "type=local,dest=/tmp/docker-build-cache-new,mode=max"
  ]

  # Load the image into Docker daemon
  load = true
}

# =============================================================================
# User Story 3: Single-platform builds for testing
# =============================================================================
target "amd64-only" {
  inherits = ["base"]

  # Build for amd64 only
  platforms = [
    "linux/amd64"
  ]

  # Platform-specific tags
  tags = [
    "cephaloproxy:amd64-latest",
    "cephaloproxy:amd64-${VERSION}"
  ]

  # Cache configuration for GitHub Actions
  cache-from = [
    "type=gha"
  ]
  cache-to = [
    "type=gha,mode=max,compression=zstd"
  ]

  # Load the image
  load = true
}

target "arm64-only" {
  inherits = ["base"]

  # Build for arm64 only
  platforms = [
    "linux/arm64"
  ]

  # Platform-specific tags
  tags = [
    "cephaloproxy:arm64-latest",
    "cephaloproxy:arm64-${VERSION}"
  ]

  # Cache configuration for GitHub Actions
  cache-from = [
    "type=gha"
  ]
  cache-to = [
    "type=gha,mode=max,compression=zstd"
  ]

  # Load the image
  load = true
}

# =============================================================================
# Build Groups
# =============================================================================

# Default group - multi-platform build (cephaloproxy target)
group "default" {
  targets = ["cephaloproxy"]
}

# Single platform group - build both amd64 and arm64 separately
group "single-platform" {
  targets = ["amd64-only", "arm64-only"]
}

# Development group - local development build with local cache
group "dev" {
  targets = ["dev"]
}
