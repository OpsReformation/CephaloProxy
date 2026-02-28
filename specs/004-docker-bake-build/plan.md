# Implementation Plan: Docker Build System Update

**Branch**: `004-docker-bake-build` | **Date**: 2026-02-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-docker-bake-build/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature migrates the CephaloProxy container build system to use Docker Bake for multi-platform support (amd64, arm64). The implementation creates a `docker-bake.hcl` configuration file that defines build targets for both architectures using Docker BuildKit's native multi-platform caching. GitHub Actions workflow and manual build instructions will be updated to use Docker Bake commands instead of direct `docker build` calls.

## Technical Context

**Language/Version**: Python 3.11+ (runtime), Bash (build-time)
**Primary Dependencies**: Docker BuildKit, Docker Bake (HCL config), Docker Compose
**Storage**: Stateless container; Squid cache/logs managed via external persistent volumes
**Testing**: pytest (for Python scripts), bats (for shell scripts)
**Target Platform**: Linux containers (amd64, arm64)
**Project Type**: Single container project
**Performance Goals**: Not prioritized for this feature (explicitly stated: "do not worry about improving build times")
**Constraints**: Must use Docker BuildKit (no fallback), must support multi-platform builds (amd64, arm64), must maintain distroless Debian 12 base image
**Scale/Scope**: Single container image with multi-platform support, CI/CD integration, build documentation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Container-First Architecture ✅ PASS
- Multi-platform container builds supported via Docker Bake
- Base image (debian12 distroless) maintained
- Configuration injectable via Dockerfile ARGs and environment variables
- Image reproducibility maintained through BuildKit caching

### II. Test-First Development ✅ PASS
- Tests for Docker bake configuration validation needed
- Integration tests to verify multi-platform builds
- TDD workflow applied for any Python scripts added

### III. Squid Proxy Integration ✅ PASS
- Existing Dockerfiles maintained (Dockerfile.distroless is production-ready)
- No changes to Squid configuration or behavior
- Build system enhancement only

### IV. Security by Default ✅ PASS
- BuildKit security features utilized
- No security regressions introduced
- Distroless security posture maintained

### V. Observable by Default ⚠️ PARTIAL
- Build logs and errors will be observable
- No runtime observability changes
- Acceptable for build system feature

**Status**: PASS with minor observation on observability (acceptable for build-only feature)

## Project Structure

### Documentation (this feature)

```text
specs/004-docker-bake-build/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
container/
├── Dockerfile          # Gentoo-based original (legacy, maintained for reference)
├── Dockerfile.distroless # Debian 12 distroless (production, will be used by Bake)
├── docker-bake.hcl     # NEW: Docker Bake configuration file
└── [existing scripts]

.github/
└── workflows/
    └── build-and-test.yml  # UPDATED: Use Docker Bake commands

deploy/
└── docker-compose.production.yml  # UPDATED: Reference Docker Bake targets

README.md  # UPDATED: Add Docker Bake build instructions
```

**Structure Decision**: Single container project with container-focused directories. The `container/` directory contains all Dockerfiles and scripts. The build configuration will be added as `docker-bake.hcl` in the repository root for easy access and CI/CD integration.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | All requirements met constitutionally | N/A |

**No constitutional violations.** All requirements are aligned with the CephaloProxy Constitution. The implementation maintains container-first architecture, test-first development, Squid proxy integration, security by default, and observable by default principles.

## Phase 0: Research Output

**Status**: ✅ COMPLETE

**File**: [research.md](./research.md)

**Key Decisions**:
1. Single target with platform overrides using base target inheritance
2. Registry-based cache for CI/CD environments
3. Environment variables for base image configuration (workaround for external JSON loading)
4. Fail fast on BuildKit unavailability
5. Minimal Dockerfile adaptations (add ARG declarations for platform detection)

## Phase 1: Design Output

**Status**: ✅ COMPLETE

**Files**:
- [data-model.md](./data-model.md) - Build configuration entities and relationships
- [contracts/build-api.md](./contracts/build-api.md) - Build command contracts and expected outputs
- [quickstart.md](./quickstart.md) - User guide for Docker Bake usage

**Agent Context**: ✅ UPDATED

**Changes to CLAUDE.md**:
- Added Docker BuildKit, Docker Bake (HCL config), Docker Compose to Active Technologies
- Updated recent changes section

**Re-evaluation**: Constitution Check re-validated. No violations identified.

## Next Steps

After completing this planning phase, proceed with:

1. **Generate Tasks**: Run `/speckit.tasks` to create actionable task breakdown
2. **Implement**: Execute tasks in order using `/speckit.implement`
3. **Verify**: Ensure all functional and non-functional requirements are met

**Recommended Command**: `/speckit.tasks` to generate the task breakdown
