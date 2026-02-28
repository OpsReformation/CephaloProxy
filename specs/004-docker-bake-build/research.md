# Research: Docker Build System Update

## Decision: Docker Bake HCL Configuration

**Chosen Approach**: Single target with platform overrides using base target inheritance

**Rationale**:
- Clean configuration management through base target inheritance
- Supports both multi-platform and single-platform builds
- Easy to test individual platforms without affecting others
- Maintains backward compatibility with existing Dockerfiles

**Alternative Considered**: Multiple targets per platform
- More verbose configuration
- Duplicate common settings
- Harder to maintain when base images or settings change
- Rejected because it violates the "single target with overrides" requirement

## Decision: Native Multi-Platform Caching

**Chosen Approach**: Registry-based cache with BuildKit's native caching

**Rationale**:
- Best for CI/CD environments (GitHub Actions)
- Cache persists across builds
- Supports automatic layer reuse across platforms
- No local cache management required
- Automatic compression optimization (zstd)

**Configuration**:
```hcl
cache-from = ["type=registry,ref=cephaloproxy:buildcache"]
cache-to = ["type=registry,ref=cephaloproxy:buildcache,mode=max,compression=zstd"]
```

**Alternative Considered**: Local cache
- Easier for local development
- Doesn't work well in CI/CD
- Cache invalidation challenges
- Rejected because it's not suitable for GitHub Actions integration

## Decision: External Configuration for Base Images

**Chosen Approach**: Environment variables passed via CLI

**Rationale**:
- Docker Bake HCL natively supports variables
- Can be set via CLI for different configurations
- No need for external JSON/YAML parsing in HCL
- Simpler and more portable
- Aligns with Docker's build arg pattern

**Implementation**:
```bash
docker buildx bake \
  --var DISTROLESS_BASE=gcr.io/distroless/python3-debian12 \
  --var DISTROLESS_BASE_SHA=sha256:8ce6bba3f793ba7d834467dfe18983c42f9b223604970273e9e3a22b1891fc27 \
  --var DEBIAN_VERSION=12
```

**Alternative Considered**: External JSON file loaded in HCL
- Requires external plugin for JSON parsing
- More complex configuration
- Less portable between CI/CD environments
- Rejected because it adds unnecessary complexity

## Decision: BuildKit Validation

**Chosen Approach**: Fail immediately with clear error message if BuildKit not available

**Rationale**:
- Ensures consistent build behavior
- Prevents silent failures
- Provides immediate actionable feedback
- Aligns with FR-006 requirement

**Validation in CI/CD**:
```bash
if [ -n "$BUILDKIT_DISABLE" ]; then
  echo "Error: Docker BuildKit is disabled. Set DOCKER_BUILDKIT=1 or create a buildx builder."
  exit 1
fi
if ! docker buildx version > /dev/null 2>&1; then
  echo "Error: Docker buildx is not available."
  exit 1
fi
```

**Alternative Considered**: Warn and continue
- Could lead to unexpected behavior
- Doesn't provide clear guidance
- Rejected because it violates fail-fast principle

## Decision: Dockerfile Adaptations

**Chosen Approach**: Minimal changes to existing Dockerfile.distroless

**Rationale**:
- Maintain existing build process
- Add platform detection via ARGs
- Use BuildKit's TARGETARCH for architecture-specific operations
- No changes to distroless security posture

**Changes Made**:
- Added ARG declarations for platform detection
- Maintained existing base image SHA for immutability
- No changes to build stages or RUN commands

**Alternative Considered**: Complete rewrite
- Unnecessary complexity
- Risk of regressions
- Rejected because it's over-engineering

## Decision: GitHub Actions Integration

**Chosen Approach**: Update workflow to use `docker buildx bake` command

**Rationale**:
- Single command for multi-platform builds
- Native support for BuildKit features
- Maintains existing test and validation steps
- No changes to test infrastructure

**Updated Commands**:
```yaml
- name: Build multi-platform container image
  run: docker buildx bake --set *.platform=linux/amd64,linux/arm64
```

**Alternative Considered**: Keep existing `docker build` command
- More verbose
- Doesn't support multi-platform builds
- Rejected because it violates feature requirements

## Decision: Manual Build Instructions

**Chosen Approach**: Add Docker Bake commands to README.md

**Rationale**:
- Consistent with CI/CD workflow
- Clear and simple commands
- Includes cache management tips
- Platform-specific build options documented

**Commands Documented**:
- Multi-platform build: `docker buildx bake`
- Single platform: `docker buildx bake --set *.platform=linux/amd64`
- Local development: `docker buildx bake dev`
- Override configuration: `--var` flags

**Alternative Considered**: Keep separate shell scripts
- Additional maintenance burden
- Less discoverable
- Rejected because it adds unnecessary complexity

## Decision: Build Target Structure

**Chosen Approach**: Base target + platform-specific targets + groups

**Rationale**:
- Base target contains all common settings
- Platform targets inherit from base
- Groups provide convenient build commands
- Easy to extend for future platforms

**Target Structure**:
- `base`: Common settings, ARGs, cache-from
- `cephaloproxy`: Multi-platform (amd64, arm64)
- `amd64-only`: Single platform for testing
- `arm64-only`: Single platform for testing
- `dev`: Local development with local cache
- Groups: `default`, `single-platform`, `dev`

**Alternative Considered**: Single target with CLI overrides
- Less organized
- Harder to discover available options
- Rejected because it lacks clarity

## Technology Stack

- **Docker BuildKit**: v0.12+ (native multi-platform build system)
- **Docker Bake**: v0.12+ (HCL configuration for builds)
- **HCL**: Configuration language (supported natively by Docker)
- **GitHub Actions**: v4+ (CI/CD integration)
- **Bash**: Shell scripting (build validation)

## Dependencies

- Docker daemon with BuildKit support
- Buildx builder instance (created if needed)
- Internet access for registry pulls (build cache)
- No additional Python or shell dependencies

## Integration Points

- GitHub Actions workflow: Uses `docker buildx bake` command
- Docker Compose: Can reference build targets
- Docker CLI: No breaking changes
- Existing Dockerfiles: Minimal adaptations required

## Security Considerations

- BuildKit security features utilized
- Distroless security posture maintained
- No secrets in build configuration
- Base image SHA pinned for immutability
