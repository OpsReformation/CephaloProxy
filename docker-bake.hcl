# Docker Bake Configuration for CephaloProxy
# Multi-platform container build system using Docker BuildKit
# Reference: specs/004-docker-bake-build/

variable "VERSION" {
  default = "latest"
}

# =============================================================================
# Stub target populated by docker/metadata-action bake-file in CI.
# Empty here so local builds work without the generated file present.
# =============================================================================
target "docker-metadata-action" {}

# =============================================================================
# Base target — common Dockerfile and build args inherited by all targets.
# BUILDPLATFORM and TARGETPLATFORM are set automatically by BuildKit from
# the target's platforms list and must not be hardcoded here.
# =============================================================================
target "base" {
  context    = "."
  dockerfile = "container/Dockerfile.distroless"
  args = {
    DISTROLESS_BASE     = "gcr.io/distroless/python3-debian12"
    DISTROLESS_BASE_SHA = "sha256:8ce6bba3f793ba7d834467dfe18983c42f9b223604970273e9e3a22b1891fc27"
    DEBIAN_VERSION      = "12"
  }
}

# =============================================================================
# Main build target.
#
# In CI the workflow overrides platform, output, cache, and tags via `set`:
#   *.platform        — one platform per matrix job
#   *.output          — push-by-digest to registry (no tag applied yet)
#   *.cache-from/to   — registry-backed cache keyed per arch
#   *.tags=           — cleared; tags are applied at the merge step
#
# Locally (docker buildx bake image) it builds for the host platform,
# loads into the Docker daemon, and applies the fallback tags below.
# =============================================================================
target "image" {
  inherits = ["base", "docker-metadata-action"]
  tags     = ["cephaloproxy:latest", "cephaloproxy:${VERSION}"]
  load     = true
}

# =============================================================================
# Local development target with local filesystem cache.
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
# Build groups
# =============================================================================

group "default" {
  targets = ["image"]
}
