# Feature Specification: Docker Build System Update

**Feature Branch**: `004-docker-bake-build` **Created**: 2026-02-23 **Status**:
Draft

## Overview

This feature updates the Docker build system to utilize Docker Bake for
multi-platform builds and improved build performance. Docker Bake will allow us
to define build configurations in a single file that can build for multiple
platforms.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Multi-platform builds

As a CI/CD engineer, I want to build Docker images for multiple platforms
(amd64, arm64) from a single configuration, so that I can build for different
architectures efficiently.

**Acceptance Criteria**:

- [ ] Single `docker buildx bake` command successfully builds images for both
  linux/amd64 and linux/arm64 architectures
- [ ] Build output includes both platform-specific image IDs with correct tags
- [ ] Error handling provides actionable feedback if either platform fails to
  build
- [ ] Cache sharing works correctly between platforms (build cache persists
  across platform builds)

### User Story 2 - Improved build performance

As a DevOps engineer, I want to leverage Docker BuildKit's caching and parallel
builds to reduce build times and improve developer experience.

**Acceptance Criteria**:

- [ ] `docker buildx bake dev` command uses local filesystem cache for faster
  rebuilds
- [ ] Subsequent rebuilds show cache hit (no redundant layer builds)
- [ ] Build logs show cache status (HIT/MISS) for each layer
- [ ] GitHub Actions workflow uses GitHub Actions cache backend for CI/CD builds
- [ ] Cache effectiveness measured via build time comparison (first build vs.
  rebuild)

### User Story 3 - Simplified multi-platform builds

As a system administrator, I want to build Docker images for different platforms
with a single command, so that I can deploy consistently across different
environments.

**Acceptance Criteria**:

- [ ] `docker buildx bake single-platform` command successfully builds
  amd64-only and arm64-only images
- [ ] Platform-specific tags are correctly applied (e.g.,
  `cephaloproxy:amd64-latest`)
- [ ] Single-platform builds can be run independently of multi-platform builds
- [ ] Platform-specific targets inherit correctly from base target configuration

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Docker bake configuration must support building for multiple
  platforms (amd64, arm64)
- **FR-002**: The Docker bake configuration must support building with cache
  sharing between platforms using Docker BuildKit's cache backends
  - CI/CD: GitHub Actions cache (gha backend)
  - Local development: Local filesystem cache (local backend)
  - No registry cache backend required
- **FR-003**: The Docker bake configuration must support multi-stage builds for
  multi-platform support
- **FR-004**: The Docker bake configuration must support building for different
  architectures with different base images
- **FR-005**: The Docker bake system must fail fast on any build error,
  providing immediate error messages with the following format:
  - Build error: "Build failed: [error details from Docker BuildKit]"
  - BuildKit unavailable: "Docker BuildKit is required but not available. Enable
    it by setting DOCKER_BUILDKIT=1 or removing DOCKER_BUILDKIT_DISABLE=1 from
    your environment."
  - Error must include actionable remediation steps
- **FR-006**: The Docker bake system must fail immediately if Docker BuildKit is
  not available, with a clear error message explaining how to enable it
- **FR-007**: Base images for different platforms must be defined via
  environment variables (DISTROLESS_BASE, DEBIAN_VERSION) passed via CLI
  arguments to Docker Bake commands. Default values: DISTROLESS_BASE=debian12,
  DEBIAN_VERSION=12
- **FR-008**: Existing docker-compose.yml build commands must be deprecated with
  migration strategy:
  - Deprecation period: 30 days from feature release
  - Alternative: Use `docker buildx bake` commands documented in README.md
  - Rollback: Restore previous docker-compose.yml build commands if needed
  - Deprecation warning: "WARNING: docker build and docker-compose build
    commands are deprecated. Use 'docker buildx bake' instead."
- **FR-009**: Docker Bake must be the only supported build method; direct docker
  build commands are not supported
- **FR-010**: Breaking change is acceptable - no backward compatibility required
  for docker build commands. All workflows must transition to Docker Bake
  commands within 30 days of feature release.
- **FR-011**: (DEPRECATED - merged into FR-002) Documentation must specify cache
  backend requirements
- **FR-012**: Documentation must explain how to enable Docker BuildKit if not
  available (see FR-006 error message format)
- **FR-013**: Docker Bake image output must preserve the same tag format as
  previous builds: `cephaloproxy:latest`, `cephaloproxy:${VERSION}`, and
  platform-specific tags: `cephaloproxy:${VERSION}-${platform}` for
  single-platform builds
- **FR-014**: Docker Bake image output must preserve the same container labels
  as previous builds, including: `org.opencontainers.image.created`,
  `org.opencontainers.image.version`, `org.opencontainers.image.revision`, and
  project-specific labels

### Non-functional Requirements

- **NF-001**: Docker Bake must replace existing docker build commands in all
  workflows; direct docker build commands are not supported
- **NF-002**: Documentation must provide Docker Bake usage training for teams
  adopting the new build system, including:
  - Quick start guide with common commands
  - Multi-platform build examples
  - Cache backend configuration guide
  - Troubleshooting section for BuildKit setup
- **NF-003**: Docker Bake configuration must replace existing docker-compose.yml
  build configurations in deploy/ directory (production and any staging
  environments)
- **NF-004**: Dockerfile behavior must remain unchanged; Bake configuration is
  additive only
- **NF-005**: CI/CD workflows must be completely rewritten to use Docker Bake
  exclusively
- **NF-006**: At least 3-5 configuration files must be updated:
  - docker-bake.hcl (NEW - core configuration)
  - GitHub Actions workflow (CI/CD integration)
  - docker-compose.production.yml (reference Bake targets)
  - README.md (build documentation)
  - CLAUDE.md (active technologies)
  - Expected changes: 1 file new, 3 files modified (moderate changes - ARG
    additions, command updates, documentation updates)

## Clarifications

### Session 2026-02-27

- Q: How should the build system handle build failures? → A: Fail fast - stop
  immediately with clear error
- Q: What caching strategy should be used for cross-platform builds? → A: Hybrid
  cache model using GitHub Actions cache for CI/CD and local cache for
  development
- Q: How should the build configuration be organized in the bake file? → A:
  Single target with overrides
- Q: What should be the behavior when Docker BuildKit is not available? → A:
  Fail with error
- Q: How should the system determine which base image to use for each platform?
  → A: Environment variables passed via CLI arguments
- Q: Should existing docker-compose.yml files work without modification? → A:
  Required updates; breaking change acceptable
- Q: Should direct docker build commands continue to work alongside Docker Bake?
  → A: No, breaking change acceptable
- Q: Should documentation provide migration path for existing workflows? → A: No
  migration path needed; training provided
- Q: How many configuration files should be updated? → A: 3-5 files with
  moderate changes
- Q: Should Dockerfile behavior be preserved? → A: Yes, Dockerfile must remain
  unchanged
- Q: Should CI/CD workflows be completely rewritten? → A: Yes, complete workflow
  rewrite required
- Q: Should deprecation warnings be included? → A: No warnings required
- Q: Should a rollback strategy be documented? → A: No rollback required
- Q: What CI/CD integration requirements? → A: GitHub Actions cache (gha
  backend) - no registry required
- Q: What troubleshooting should be documented? → A: BuildKit setup instructions
  required
- Q: What image output format should be preserved? → A: Tag format and container
  labels must be preserved
- Q: Should build time performance be specified? → A: Not a priority
- Q: What should error messages look like? → A: Format specified in FR-005 (see
  spec update)
- Q: What is the deprecation timeline? → A: 30-day transition period with
  explicit migration strategy (see FR-008 update)
- Q: What are the specific configuration files to update? → A: List provided in
  NF-006 (see spec update)
- Q: What acceptance criteria should define "efficiently" and "simplified"? → A:
  No specific metrics defined for this feature; focus on correctness and
  usability

## Assumptions

- The project will continue to use the same Squid proxy base image with SSL-bump
  support
- The multi-stage build process will remain the same but will be enhanced with
  Docker Bake features
- Teams adopting the Docker Bake build system will receive training on its usage
- CI/CD workflows will be updated to use Docker Bake exclusively