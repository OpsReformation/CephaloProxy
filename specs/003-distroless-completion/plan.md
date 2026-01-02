# Implementation Plan: Distroless Migration Completion

**Branch**: `003-distroless-completion` | **Date**: 2026-01-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-distroless-completion/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Complete the distroless migration by:
1. Upgrading base image from Debian 12 to Debian 13 (Trixie) distroless
2. Migrating entrypoint.sh to entrypoint.py using Python 3.11+ with asyncio
3. Removing debug variant to eliminate all shell binaries from runtime image
4. Implementing /proc filesystem parsing for process monitoring (no external dependencies)
5. Using asyncio-based graceful shutdown with 30-second timeout

**Primary Goals**: Eliminate shell access for maximum security hardening, upgrade to latest OS base for current security patches, and unify all initialization logic in Python for maintainability.

## Technical Context

**Language/Version**: Python 3.11+ (3.12 preferred), Bash (build-time only in Debian 13 slim builder stage)
**Primary Dependencies**: Python standard library only (os, sys, subprocess, signal, pathlib, logging, time, re, shutil, asyncio) - NO external packages
**Storage**: N/A (stateless container, persistent volumes for Squid cache/logs managed externally)
**Testing**: Bats (container integration tests), Python unittest for entrypoint unit tests, Trivy (vulnerability scanning), shellcheck (build scripts only)
**Target Platform**: Linux containers (Docker, Kubernetes, OpenShift) on amd64 and arm64 architectures
**Project Type**: Container infrastructure (Dockerfile multi-stage build + Python initialization scripts)
**Performance Goals**: Container startup time ≤110% of current bash implementation, no degradation in proxy throughput
**Constraints**: Zero shell binaries in runtime image, Python stdlib only (no pip packages), /proc filesystem available for process monitoring, asyncio compatible with Python 3.11+
**Scale/Scope**: Single container entrypoint script (~300-400 lines Python), 3 Python scripts total (entrypoint.py, init-squid.py, healthcheck.py), Dockerfile.distroless migration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Verify compliance with CephaloProxy Constitution v1.0.0:

- [x] **Container-First Architecture**: Feature improves container security by removing shell, maintains health checks (/health, /ready), graceful shutdown (asyncio-based SIGTERM/SIGINT handling), and reduces host dependencies
- [x] **Test-First Development**: Tests written and approved BEFORE implementation begins (container startup tests, shell absence tests, graceful shutdown tests, process monitoring tests)
- [x] **Squid Proxy Integration**: No changes to Squid configuration - migration is transparent to Squid, maintaining declarative config validation via `squid -k parse`
- [x] **Security by Default**: Enhances security by removing shell binaries, maintains non-root user (UID 1000/arbitrary UID for OpenShift), secrets injected via mounted volumes (no changes)
- [x] **Observable by Default**: Maintains current Squid native logging, Python logging module for entrypoint diagnostics, preserves /health and /ready endpoints via healthcheck.py

**Additional Compliance**:

- [x] Security Requirements: No TLS changes (existing SSL-bump support maintained), audit logging unchanged (Squid access.log), vulnerability scanning improved (fewer packages in distroless)
- [x] Performance Standards: P95 latency unchanged (entrypoint migration doesn't affect proxy path), startup time constraint ≤110% enforced in SC-005, memory baseline reduced (smaller image)
- [x] Observability Requirements: Squid native access.log/cache.log maintained, Python logging to stdout/stderr with timestamps and log levels, /health and /ready endpoints unchanged

**Constitution Compliance Summary**: ✅ Full compliance. Migration enhances security posture while maintaining all constitutional requirements. No violations or deviations.

## Project Structure

### Documentation (this feature)

```text
specs/003-distroless-completion/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Debian 13 availability, Python entrypoint patterns
├── data-model.md        # Phase 1 output - Entrypoint state machine, process lifecycle
├── quickstart.md        # Phase 1 output - Developer setup, testing without shell
├── contracts/           # Phase 1 output - Entrypoint behavior contracts, error codes
│   └── entrypoint-contract.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Container infrastructure project
container/
├── Dockerfile.distroless        # Multi-stage build (Debian 13 slim → distroless Debian 13)
├── entrypoint.py                # NEW: Python entrypoint (replaces entrypoint.sh)
├── entrypoint.sh                # DEPRECATED: Bash entrypoint (to be removed after migration)
├── init-squid.py                # Existing: Squid cache initialization (no changes)
├── healthcheck.py               # Existing: Health check HTTP server (no changes)
├── squid.conf.default           # Existing: Default Squid configuration (no changes)
└── build-multiplatform.sh       # Build script for amd64/arm64 (minor updates for Debian 13)

tests/
├── integration/
│   ├── test-container-startup.bats      # NEW: Test Python entrypoint startup
│   ├── test-shell-absence.bats          # NEW: Verify no shell binaries
│   ├── test-graceful-shutdown.bats      # NEW: Test asyncio shutdown handling
│   ├── test-process-monitoring.bats     # NEW: Test /proc parsing
│   └── test-openshift-uid.bats          # Existing: Arbitrary UID compatibility
└── unit/
    └── test-entrypoint.py               # NEW: Unit tests for entrypoint.py functions

.specify/
└── memory/
    └── CLAUDE.md                        # Updated: Add Python 3.11+, asyncio, Debian 13
```

**Structure Decision**: Container infrastructure project - single container/ directory for all container-related files, tests/ for integration and unit tests. Python entrypoint.py replaces bash entrypoint.sh while maintaining same initialization sequence. No application code changes (Squid, init-squid.py, healthcheck.py unchanged).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. This section is empty.

## Phase 0: Research & Resolution

**Objective**: Resolve all technical unknowns and validate assumptions before design.

### Research Tasks

1. **Debian 13 Distroless Image Availability**
   - **Question**: Does gcr.io/distroless/python3-debian13 exist? If not, what's the fallback strategy?
   - **Research**: Query Google Container Registry, check distroless repository for Debian 13 images
   - **Deliverable**: Confirmed base image selection (distroless/python3-debian13 or distroless/cc-debian13 + compiled Python)

2. **Python Asyncio Signal Handling Patterns**
   - **Question**: How to implement graceful shutdown with 30s timeout using asyncio?
   - **Research**: Best practices for asyncio signal handlers, timeout patterns, subprocess management
   - **Deliverable**: Reference implementation pattern for asyncio-based entrypoint

3. **/proc Filesystem Process Monitoring**
   - **Question**: How to reliably monitor Squid process using /proc without psutil?
   - **Research**: /proc/<pid>/status parsing, process existence checks, edge cases
   - **Deliverable**: Robust /proc parsing implementation pattern

4. **Python Entrypoint Direct Execution**
   - **Question**: Can distroless non-debug variant execute Python script as ENTRYPOINT without shell?
   - **Research**: Verify ENTRYPOINT ["/usr/bin/python3", "/entrypoint.py"] works in distroless
   - **Deliverable**: Confirmed Dockerfile ENTRYPOINT syntax for shell-free execution

5. **Debian 13 Squid Runtime Dependencies**
   - **Question**: Are all Squid runtime libraries compatible with Debian 13?
   - **Research**: Verify Squid 5.x/6.x shared library dependencies on Debian 13
   - **Deliverable**: Complete list of required shared libraries for distroless runtime

### Research Output Location

`specs/003-distroless-completion/research.md`

## Phase 1: Design Artifacts

**Objective**: Create detailed design documents defining entrypoint behavior, state transitions, and contracts.

### 1.1 Data Model

**File**: `specs/003-distroless-completion/data-model.md`

**Contents**:
- **Entrypoint State Machine**: States (INITIALIZING, VALIDATING, STARTING_HEALTH_CHECK, STARTING_SQUID, RUNNING, SHUTTING_DOWN, ERROR, EXITED)
- **Process Lifecycle**: Squid process states, health check process states, monitoring loops
- **Configuration Model**: Squid config validation, SSL certificate merging, directory structure
- **Error Taxonomy**: Startup errors, runtime errors, shutdown errors with exit codes

### 1.2 Contracts

**Directory**: `specs/003-distroless-completion/contracts/`

**Files**:
- `entrypoint-contract.md`: Entrypoint behavior contract
  - Input: Environment variables, mounted volumes, signals
  - Output: Stdout/stderr logs, exit codes, process states
  - Invariants: Fail-fast on startup errors, 30s shutdown timeout, /proc monitoring
  - Error Codes: Exit code mapping (1=startup error, 130=SIGINT, 143=SIGTERM, etc.)

### 1.3 Quickstart Guide

**File**: `specs/003-distroless-completion/quickstart.md`

**Contents**:
- Build Debian 13 distroless image locally
- Run container with Python entrypoint
- Test graceful shutdown (docker stop)
- Verify shell absence (docker exec attempts)
- Debug using ephemeral debug containers
- Run integration test suite

### 1.4 Agent Context Update

**Action**: Run `.specify/scripts/bash/update-agent-context.sh claude`

**Updates to CLAUDE.md**:
- Add Python 3.11+ (asyncio patterns for entrypoint)
- Add Debian 13 (Trixie) as container base OS
- Note: No shell in runtime (debugging via ephemeral containers only)

## Phase 2: Task Decomposition

**NOTE**: Task decomposition is handled by `/speckit.tasks` command, NOT by `/speckit.plan`.

This plan provides the foundation for task generation. The `/speckit.tasks` command will:
1. Read this plan and spec.md
2. Generate dependency-ordered tasks in tasks.md
3. Include TDD workflow (write tests → approve → implement → verify)

## Implementation Approach

### Migration Strategy

**Incremental Approach**:
1. **Phase 0**: Research Debian 13 availability and Python patterns (non-breaking)
2. **Phase 1**: Create entrypoint.py alongside entrypoint.sh (parallel existence)
3. **Phase 2**: Update Dockerfile.distroless to use Debian 13 + Python entrypoint
4. **Phase 3**: Integration testing with new image (feature branch)
5. **Phase 4**: Merge after all tests pass, deprecate entrypoint.sh

**Rollback Safety**:
- Keep entrypoint.sh until entrypoint.py fully validated
- Dockerfile.distroless changes are isolated to feature branch
- Can revert to Debian 12 debug variant if Debian 13 issues found

### Key Technical Decisions

1. **Asyncio Architecture**: Entrypoint.py uses asyncio.run() as main entry point, async def main(), signal handlers set via loop.add_signal_handler()

2. **Process Monitoring**: Read /proc/<pid>/status every 1 second, check for process existence via os.path.exists(f'/proc/{pid}')

3. **Graceful Shutdown**: asyncio.wait_for(shutdown_squid(), timeout=30.0) with forced kill after timeout

4. **Error Handling**: sys.exit(1) for all startup errors, structured logging via logging module with INFO level

5. **No External Dependencies**: Pure Python stdlib - no pip install in Dockerfile, no requirements.txt

## Risk Mitigation

1. **Distroless Debian 13 Unavailable**:
   - Mitigation: Fallback to distroless/cc-debian13 + compile Python 3.12 from source in builder stage
   - Detection: Check gcr.io registry during research phase

2. **Asyncio Signal Handling Issues**:
   - Mitigation: Extensive integration testing with docker stop, SIGTERM, SIGINT
   - Detection: Test graceful shutdown in Phase 1 testing

3. **/proc Parsing Reliability**:
   - Mitigation: Handle edge cases (pid reuse, /proc mount issues), fallback to exception handling
   - Detection: Unit tests for /proc parsing, integration tests for process monitoring

4. **Startup Performance Regression**:
   - Mitigation: Benchmark startup time, optimize Python import loading, lazy imports
   - Detection: SC-005 automated test (≤110% of bash version)

5. **Debian 13 Squid Incompatibility**:
   - Mitigation: Test Squid startup with Debian 13 libraries in research phase
   - Detection: Build Debian 13 image early, verify Squid functionality

## Success Criteria Validation

All success criteria from spec.md will be validated via:

- **SC-001, SC-002**: Integration tests verify no shell binaries, exec commands fail
- **SC-003, SC-004**: Image inspection tests verify Debian 13 and Python 3.11+
- **SC-005**: Automated benchmark comparing startup time to baseline
- **SC-006**: Existing integration test suite runs against new image
- **SC-007**: Cyclomatic complexity analysis (radon or similar tool)
- **SC-008**: Integration test sends SIGTERM, validates 30s shutdown
- **SC-009**: Trivy scan comparing CVE counts

## Appendix: Constitutional Alignment

This migration strengthens CephaloProxy's constitutional compliance:

- **Security by Default**: Removing shell eliminates entire attack surface class
- **Container-First Architecture**: Maintains all container requirements while improving security
- **Observable by Default**: Preserves all observability (Squid logs, health checks, metrics)
- **Test-First Development**: TDD workflow enforced throughout migration
- **Squid Proxy Integration**: Zero impact on Squid - transparent migration

**Compliance Status**: ✅ Enhanced compliance through security hardening
