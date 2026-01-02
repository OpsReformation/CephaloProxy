# Implementation Plan: Distroless Container Migration

**Branch**: `002-distroless-migration` | **Date**: 2025-12-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-distroless-migration/spec.md`

## Summary

Migrate CephaloProxy from Gentoo-based container to Debian → gcr.io/distroless multi-stage build to achieve true distroless architecture with significant security improvements. Primary goals: reduce attack surface by 80%+ through package minimization, eliminate shell/package manager from runtime image, convert bash initialization scripts to Python, and reduce build time by 70% while maintaining 100% functional parity including SSL-bump support.

**Technical Approach**: Multi-stage Dockerfile with (1) Debian 13 Slim builder stage compiling Squid 6.x with --enable-ssl-crtd --with-openssl, (2) gcr.io/distroless/python3-debian13 runtime stage containing only Squid binaries, Python 3.11 runtime, and required shared libraries. Python replaces bash for all initialization logic (cache setup, SSL database init, permissions validation).

## Technical Context

**Language/Version**: Python 3.11 (initialization scripts), Bash (build-time only)
**Primary Dependencies**:
- Build: Debian Slim 13, Squid 6.x source/packages, build-essential, libssl-dev
- Runtime: gcr.io/distroless/python3-debian13, Squid binaries, Python 3.11, ca-certificates

**Storage**:
- Squid cache: /var/spool/squid (persistent volume)
- SSL database: /var/lib/squid/ssl_db (persistent volume)
- Logs: /var/log/squid (persistent volume)

**Testing**:
- Bats (shell integration tests - existing)
- Python unittest (new Python initialization scripts)
- Trivy (vulnerability scanning)
- Docker multi-stage build validation

**Target Platform**:
- Docker containers (standalone)
- Kubernetes/OpenShift (orchestrated)
- Architectures: linux/amd64 (primary), linux/arm64 (future)

**Project Type**: Container infrastructure (single Dockerfile, Python scripts, shell tests)

**Performance Goals**:
- Container startup time: ≤ 110% of current (FR-008)
- Build time: 70%+ reduction vs Gentoo (SC-008)
- Proxy throughput: No degradation (maintain 1000+ req/s)
- Image size: 40%+ reduction (SC-001)

**Constraints**:
- Distroless runtime: NO shell, NO package manager, NO debugging tools
- OpenShift compatibility: Arbitrary UID/GID (FR-006)
- SSL-bump requirement: MUST compile with --enable-ssl-crtd --with-openssl
- Backward compatibility: 100% functional parity (FR-001 through FR-011)
- CA certificates: Default system CAs only (user extension pattern documented)

**Scale/Scope**:
- Single container image
- 2-3 Python initialization scripts (replacing current bash scripts)
- Multi-stage Dockerfile (~150-200 lines estimated)
- Documentation for custom CA extension pattern
- CI/CD pipeline updates for new build process

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Verify compliance with CephaloProxy Constitution v1.1.0:

- [x] **Container-First Architecture**: Feature IS container migration - all functionality remains containerized with existing health checks, graceful shutdown maintained, minimal host dependencies (distroless reduces dependencies further)
- [x] **Test-First Development**: Tests written and approved BEFORE implementation begins (existing integration tests MUST pass unchanged per SC-004)
- [x] **Squid Proxy Integration**: Squid configuration unchanged, version explicitly pinned (Squid 6.x), validation and testing maintained, logs aggregated identically
- [x] **Security by Default**: Container runs as non-root (UID 1000, OpenShift arbitrary UID compatible), secrets injection unchanged, TLS/mTLS support maintained, ACLs enforced identically, audit logging preserved
- [x] **Observable by Default**: Squid native logging formats maintained (access.log, cache.log per Constitution v1.1.0), health check endpoints (/health, /ready) preserved, graceful shutdown maintained, metrics exposure unchanged

**Additional Compliance**:

- [x] Security Requirements: TLS 1.2+ maintained through Squid SSL-bump compilation, audit logging preserved in Squid logs, vulnerability scanning via Trivy in CI/CD (improved scores expected with distroless)
- [x] Performance Standards: P95 <50ms overhead maintained (proxy processing unchanged), 1000 req/s minimum maintained (Squid performance unchanged), <512MB memory baseline maintained (distroless reduces footprint), startup <10s maintained (FR-008: ≤110% current time)
- [x] Observability Requirements: Squid access.log/cache.log formats maintained per Constitution v1.1.0 Amendment, metrics endpoint unchanged, /health and /ready endpoints preserved (FR-003)

**Constitution Compliance Assessment**: ✅ PASS

This migration enhances constitutional compliance by:
- Reducing attack surface (Security by Default strengthened)
- Eliminating shell/package manager from runtime (Container-First security improved)
- Maintaining all observability, health checks, and functional requirements
- No deviations or violations identified

## Project Structure

### Documentation (this feature)

```text
specs/002-distroless-migration/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Debian Squid compilation research
├── data-model.md        # Phase 1 output - N/A (infrastructure, not data-driven)
├── quickstart.md        # Phase 1 output - Docker build quickstart guide
├── contracts/           # Phase 1 output - N/A (no API contracts for infrastructure)
├── checklists/          # Spec validation checklists
│   └── requirements.md  # Requirements checklist (PASSED)
└── spec.md              # Feature specification
```

### Source Code (repository root)

```text
container/
├── Dockerfile           # MODIFIED: Multi-stage Debian → distroless build
├── entrypoint.sh        # MODIFIED: Simplified for Python init scripts
├── init-squid.py        # NEW: Python replacement for init-squid.sh
├── healthcheck.py       # UNCHANGED: Existing Python health check
└── squid.conf.default   # UNCHANGED: Default Squid configuration

tests/
├── integration/
│   ├── test-basic-proxy.bats        # UNCHANGED: Must pass (SC-004)
│   ├── test-health-checks.bats      # UNCHANGED: Must pass (SC-004)
│   └── test-acl-filtering.bats      # UNCHANGED: Must pass (SC-004)
└── unit/
    └── test_init_squid.py           # NEW: Python unittest for init-squid.py

.github/workflows/
└── build-and-test.yml   # MODIFIED: Updated for distroless build, Trivy scanning

docs/
├── deployment.md        # MODIFIED: Add custom CA extension pattern
└── configuration.md     # UNCHANGED: Squid config docs unchanged
```

**Structure Decision**: Single project (container infrastructure). No frontend/backend/mobile components. Primary changes in `container/` directory with multi-stage Dockerfile and Python initialization scripts replacing bash.

## Complexity Tracking

**No violations identified**. All Constitution requirements met without exceptions.

---

## Phase 0: Research & Investigation

**Objective**: Resolve all technical unknowns identified in Technical Context and validate multi-stage build approach.

### Research Tasks

1. **Squid Compilation on Debian**
   - **Question**: How to compile Squid 6.x on Debian 13 with --enable-ssl-crtd --with-openssl flags?
   - **Deliverable**: Documented compilation steps, required build dependencies (build-essential, libssl-dev, etc.), configure flags
   - **Output Location**: research.md section "Squid Compilation Process"

2. **Distroless Runtime Dependencies**
   - **Question**: Which shared libraries must be copied from builder to distroless runtime for Squid + Python to function?
   - **Approach**: Use `ldd /usr/sbin/squid` and `ldd /usr/bin/python3.11` to identify dependencies
   - **Deliverable**: Complete list of required .so files with paths
   - **Output Location**: research.md section "Runtime Dependency Mapping"

3. **Python Equivalents for Bash Script Logic**
   - **Question**: How to port bash script functionality (cache init, SSL database, permissions) to Python?
   - **Deliverable**: Python stdlib modules mapping (subprocess, pathlib, os, stat for permissions)
   - **Output Location**: research.md section "Bash to Python Migration"

4. **CA Certificates in Distroless**
   - **Question**: Verify gcr.io/distroless/cc-debian13 includes ca-certificates bundle
   - **Deliverable**: Confirmation of /etc/ssl/certs/ca-certificates.crt presence, documentation pattern for custom CA extension
   - **Output Location**: research.md section "CA Certificates Handling"

5. **OpenShift Arbitrary UID Compatibility**
   - **Question**: Does distroless runtime support OpenShift arbitrary UID assignment with GID 0 permissions?
   - **Deliverable**: Verification strategy, permission setup in Dockerfile
   - **Output Location**: research.md section "OpenShift Compatibility"

6. **Build Time Benchmarking**
   - **Question**: Actual build time comparison: Gentoo emerge vs Debian apt + compilation
   - **Deliverable**: Baseline measurements, estimated reduction percentage
   - **Output Location**: research.md section "Build Performance Analysis"

### Research Output

**File**: `specs/002-distroless-migration/research.md`

**Required Sections**:
1. Squid Compilation Process (configure flags, dependencies, build steps)
2. Runtime Dependency Mapping (ldd output analysis, required .so files)
3. Bash to Python Migration (script logic mapping, Python stdlib modules)
4. CA Certificates Handling (distroless verification, extension pattern)
5. OpenShift Compatibility (arbitrary UID testing, permission strategy)
6. Build Performance Analysis (time measurements, optimization opportunities)

**Success Criteria**: All "NEEDS CLARIFICATION" items from Technical Context resolved with concrete technical decisions and documented rationale.

---

## Phase 1: Design & Contracts

**Prerequisites**: Phase 0 research.md complete

### Data Model

**N/A**: Infrastructure migration has no data entities. Skip data-model.md generation.

### API Contracts

**N/A**: Container infrastructure exposes no new APIs. Existing health check endpoints (/health, /ready) unchanged. Skip contracts/ generation.

### Quickstart Guide

**File**: `specs/002-distroless-migration/quickstart.md`

**Sections**:
1. **Building the Distroless Image**
   - Multi-stage build command
   - Build args (if any)
   - Expected build time vs current Gentoo build

2. **Testing the Migration**
   - Running existing integration tests against new image
   - Vulnerability scanning with Trivy
   - Size comparison commands

3. **Extending with Custom CAs** (FR-011 requirement)
   - Documented multi-stage pattern for custom CA injection
   - Example Dockerfile showing `FROM cephaloproxy:latest` extension
   - Update-ca-certificates in builder stage pattern

4. **Troubleshooting Without Shell**
   - Docker exec limitations (no shell in distroless)
   - Debug container pattern (ephemeral debug sidecar)
   - Log analysis strategies

### Implementation Artifacts

**Primary Deliverable**: Multi-stage Dockerfile architecture

**Dockerfile Stages**:
1. **Stage 1: Squid Builder** (`FROM debian:13-slim AS squid-builder`)
   - Install build-essential, libssl-dev, other build dependencies
   - Download/extract Squid 6.x source OR use Debian package with modifications
   - Configure with --enable-ssl-crtd --with-openssl --enable-ssl
   - Compile Squid
   - Verify ssl-bump support: `squid -v | grep -i ssl`

2. **Stage 2: Runtime** (`FROM gcr.io/distroless/python3-debian13`)
   - Copy Squid binaries from squid-builder
   - Python runtime already included in distroless/python3-debian13
   - Copy required shared libraries (libltdl only, per Phase 0 research)
   - CA certificates already included in distroless base
   - Set up directory structure with OpenShift-compatible permissions
   - USER 1000 (overridden by OpenShift)

**Python Scripts**:
1. **init-squid.py** (replaces init-squid.sh)
   - Parse squid.conf to detect cache_dir and SSL-bump configuration (FR-005)
   - Cache directory initialization: Fail if cache_dir configured but volume not writable, skip if no cache_dir (pure proxy mode)
   - SSL database initialization (`security_file_certgen -c`) if SSL-bump detected
   - Permission validation (required volumes fail, optional volumes warn)
   - Cache size validation (disk space checks vs configured cache_dir size)
   - Logging functions (Python logging module with timestamps and severity levels)

2. **entrypoint.sh** (simplified)
   - Execute init-squid.py
   - Merge SSL certificates if mounted
   - Start Squid daemon
   - Signal handling for graceful shutdown

### Agent Context Update

**Action**: Run `.specify/scripts/bash/update-agent-context.sh claude`

**Expected Updates**:
- Add "Distroless Containers" to technology list
- Add "Multi-stage Docker Builds" to technology list
- Add "gcr.io/distroless/python3-debian13" to dependencies
- Preserve existing Squid, Python, OpenShift technologies

---

## Phase 2: Task Breakdown

**NOT EXECUTED IN THIS COMMAND**

Task breakdown is generated by `/speckit.tasks` command after Phase 1 design is complete and approved.

Expected task categories:
- Dockerfile multi-stage build implementation
- Python initialization script migration
- CI/CD pipeline updates
- Integration test validation
- Documentation updates
- Vulnerability baseline establishment

---

## Success Criteria Mapping

| Success Criterion | Validation Method | Acceptance Threshold |
|-------------------|-------------------|---------------------|
| SC-001: Image size reduction ≥40% | `docker images` size comparison | Current 500MB+ → Target ≤300MB |
| SC-002: Package reduction ≥80% | `dpkg -l` in Gentoo vs distroless inspection | Current ~hundreds → Target <50 |
| SC-003: CVE reduction ≥60% | Trivy scan comparison | Baseline CVEs → 60%+ fewer |
| SC-004: Integration tests pass | `bats tests/integration/*.sh` | 100% pass rate, no modifications |
| SC-005: Startup time ≤110% | Container ready time measurement | Current baseline + max 10% |
| SC-006: No operational regressions | Production deployment validation | All functionality identical |
| SC-007: Script complexity -30% | Cyclomatic complexity or LOC comparison | Python vs bash metrics |
| SC-008: Build time -70% | CI/CD build time comparison | Gentoo baseline → 70%+ faster |

---

## Risk Mitigation

| Risk | Mitigation Strategy | Contingency Plan |
|------|---------------------|------------------|
| **Compilation Complexity** | Phase 0 research validates Squid compilation on Debian with documented steps | Use Debian's pre-built Squid package as starting point, patch if needed |
| **Dependency Mapping** | ldd analysis in Phase 0 identifies all shared libs | Create comprehensive dependency list, test iteratively |
| **Debug Difficulty** | Document debug container pattern, comprehensive logging in Python scripts | Provide debug variant with shell for troubleshooting |
| **OpenShift UID Issues** | Test with arbitrary UID locally before deployment | Maintain GID 0 permissions, validate with `docker run --user` tests |
| **Custom CA Limitation** | Document extension pattern clearly in quickstart.md | Provide working example Dockerfile for CA extension |
| **Build Time Regression** | Benchmark in Phase 0, optimize layer caching | If <70% reduction, consider Debian binary packages vs source compilation |

---

## Dependencies & Blockers

**External Dependencies**:
- gcr.io/distroless/cc-debian13 availability (Google maintains)
- Debian Squid package sources or Squid upstream tarball
- Python 3.11 runtime (from python:3.11-slim or Debian packages)

**Internal Dependencies**:
- Existing integration tests must be runnable (currently working)
- Current Gentoo-based Dockerfile as baseline for comparison
- CI/CD pipeline access for build time benchmarking

**Blockers**: None identified

---

## Timeline & Phases

**Phase 0 (Research)**: Complete technical investigation, produce research.md
- **Duration Estimate**: 1-2 days
- **Approval Gate**: Research findings reviewed and approved

**Phase 1 (Design)**: Complete quickstart.md, validate Dockerfile architecture
- **Duration Estimate**: 1 day
- **Approval Gate**: Dockerfile approach and Python script design approved

**Phase 2 (Implementation)**: Task execution via `/speckit.tasks` command
- **Duration Estimate**: Generated by tasks command
- **Approval Gate**: Per-task approval during implementation

**Total Estimated Duration**: 3-5 days for Phases 0-1 (planning), implementation duration TBD in Phase 2

---

## Appendix: Reference Materials

**Constitutional References**:
- CephaloProxy Constitution v1.1.0 (`.specify/memory/constitution.md`)
- Amendment 1.1.0: Squid native logging formats acceptable

**Technical References**:
- Feature Specification: `specs/002-distroless-migration/spec.md`
- Requirements Checklist: `specs/002-distroless-migration/checklists/requirements.md` (PASSED)
- Current Dockerfile: `container/Dockerfile` (Gentoo-based baseline)
- Existing Integration Tests: `tests/integration/test-*.bats`

**Research Sources**:
- Google Distroless Images: https://github.com/GoogleContainerTools/distroless
- Alpine Squid APKBUILD: https://git.alpinelinux.org/aports/tree/main/squid/APKBUILD (verified SSL-bump support)
- Debian Squid Compilation: https://grimore.org/linux/debian/compile_ssl_enabled_squid

**Decision Log**:
1. **Base Image**: Debian 13 Slim → gcr.io/distroless/python3-debian13 (chosen over Alpine due to true distroless requirement, glibc compatibility, Debian 13 stable as of Aug 2025)
2. **Scripting Language**: Python 3.11 (replaces bash for initialization, justified by reduced dependency footprint)
3. **CA Strategy**: Default system CAs only, user extension pattern documented (cleaner than build-time injection)
4. **Build Approach**: Multi-stage with source compilation (ensures SSL-bump support, faster than Gentoo emerge)

---

**Plan Status**: ✅ Phase 0-1 Ready for Execution
**Next Command**: `/speckit.tasks` (to generate implementation task breakdown)
