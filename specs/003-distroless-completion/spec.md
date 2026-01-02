# Feature Specification: Distroless Migration Completion

**Feature Branch**: `003-distroless-completion`
**Created**: 2026-01-01
**Status**: Draft
**Input**: User description: "I want to finish the distroless migration we started in 002-distroless-migration. Lets finish migrating the entry.sh script to python and update our base image to distroless debian 13 - its been released. Install a current version of python in the image, if a preexisting image for debian 13 + python doesn't exist. We also want to move away from the debug variant of the base image, so that we can remove the shell."

**Constitutional Compliance**: All features must comply with CephaloProxy Constitution v1.0.0 (see `.specify/memory/constitution.md`)

## Clarifications

### Session 2026-01-01

- Q: Should Python entrypoint use psutil library or /proc filesystem parsing for process monitoring? → A: Use /proc filesystem parsing only (pure stdlib, no external deps)
- Q: Should graceful shutdown timeout use signal.alarm(), threading, or asyncio? → A: Use asyncio with timeout (modern approach, requires async refactor)
- Q: How should Python entrypoint handle unexpected startup errors (permission issues, missing files)? → A: Exit immediately with error (fail fast principle)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete Shell Removal (Priority: P1)

Security-conscious operations teams need to deploy containers without any shell or debugging tools to minimize attack surface and comply with zero-trust security policies that prohibit interactive access to production containers.

**Why this priority**: Removing the shell is the primary security goal - it eliminates entire classes of container escape vulnerabilities and prevents attackers from executing arbitrary commands even if they compromise the application.

**Independent Test**: Can be fully tested by attempting to execute shell commands in the running container (docker exec, kubectl exec) and verifying all attempts fail with "executable not found". Delivers immediate security value through complete elimination of shell access.

**Acceptance Scenarios**:

1. **Given** the container is running, **When** an operator attempts `docker exec -it <container> /bin/sh`, **Then** the command fails with "executable not found"
2. **Given** the container is running, **When** an operator attempts `docker exec -it <container> /bin/bash`, **Then** the command fails with "executable not found"
3. **Given** the container is running in Kubernetes, **When** an operator attempts `kubectl exec -it <pod> -- /bin/sh`, **Then** Kubernetes returns error indicating no shell is available
4. **Given** a security audit scans the container image, **When** checking for shell binaries, **Then** no shell executables are found (no bash, sh, busybox, dash, zsh)
5. **Given** the container image is inspected, **When** listing files in /bin and /usr/bin, **Then** only Python interpreter and required binaries exist (no shell utilities)

---

### User Story 2 - Debian 13 Base Image Migration (Priority: P2)

Platform engineering teams need to use the latest stable operating system base images to ensure they receive current security patches, updated system libraries, and long-term support for their containerized applications.

**Why this priority**: After shell removal is validated, upgrading to Debian 13 provides the latest security patches and ensures long-term maintainability. This is secondary to shell removal because it's a quality improvement rather than a security hardening step.

**Independent Test**: Can be tested by inspecting the container image metadata and verifying the base OS version is Debian 13. Validates that all dependencies work correctly on the new base without requiring the shell removal to be complete.

**Acceptance Scenarios**:

1. **Given** the container image is inspected, **When** checking OS release information, **Then** the base OS is Debian 13 (Trixie)
2. **Given** the container starts successfully, **When** Python runtime executes initialization scripts, **Then** all Python standard library modules work correctly on Debian 13
3. **Given** vulnerability scanners analyze the image, **When** comparing Debian 12 vs Debian 13 base, **Then** Debian 13 shows reduced or equal CVE count due to updated packages
4. **Given** the distroless Debian 13 base image is used, **When** building the container, **Then** build completes successfully with all required runtime dependencies available

---

### User Story 3 - Complete Python Migration for Entrypoint (Priority: P3)

Development teams need all container initialization logic in a single language (Python) to simplify maintenance, improve error handling, and eliminate shell script complexity that makes debugging difficult.

**Why this priority**: While valuable for long-term maintainability and code quality, this is lower priority than security hardening (shell removal) and platform updates (Debian 13). The feature delivers value even if entrypoint migration is delayed.

**Independent Test**: Can be tested by starting the container and verifying all initialization steps complete successfully via Python scripts. Measures complexity reduction through cyclomatic complexity analysis and line count comparison.

**Acceptance Scenarios**:

1. **Given** the container starts, **When** initialization executes, **Then** all logic (configuration validation, SSL certificate handling, directory creation, health check startup, Squid launch, signal handling) runs via Python entrypoint script
2. **Given** SSL-bump is enabled in configuration, **When** the Python entrypoint validates certificates, **Then** TLS certificate and key are merged correctly and permissions set appropriately (same behavior as bash version)
3. **Given** the container receives SIGTERM, **When** the Python entrypoint handles shutdown, **Then** Squid shuts down gracefully, health check server stops, and container exits cleanly
4. **Given** the Python entrypoint script, **When** comparing to the legacy bash entrypoint, **Then** the Python version has equivalent or better error messages and logging clarity
5. **Given** configuration validation fails, **When** the Python entrypoint detects invalid squid.conf, **Then** container exits with clear error message indicating the validation failure

---

### Edge Cases

- **Missing Python in distroless Debian 13**: If gcr.io/distroless/python3-debian13 doesn't exist, multi-stage build compiles current Python version (3.11 or 3.12) and copies to distroless/cc-debian13 base
- **Shell-dependent operations**: All current shell operations (file I/O, process management, signal handling) must be reimplemented in Python using standard library (os, subprocess, signal, pathlib modules)
- **Process monitoring without pgrep**: Python entrypoint uses `/proc` filesystem parsing to monitor Squid process instead of shell commands (no external dependencies)
- **Startup script execution order**: Python entrypoint maintains same initialization sequence as bash version (config validation → SSL setup → cache init → health check start → Squid launch)
- **OpenShift arbitrary UID**: Python scripts detect current UID/GID using `os.getuid()` and `os.getgid()` instead of shell `id` command
- **Graceful shutdown timeout**: Python entrypoint implements same 30-second timeout for Squid shutdown using asyncio with timeout
- **Startup errors (permission issues, missing files)**: Python entrypoint exits immediately with exit code 1 and clear error message to stdout/stderr (fail fast principle for container initialization)
- **Debugging without shell access**: Operators use ephemeral debug containers (kubectl debug, docker debug) or distroless debug variant for troubleshooting instead of exec into running container

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Container image MUST use Debian 13 (Trixie) as the base operating system for both build and runtime stages
- **FR-002**: Container image MUST use non-debug distroless variant (gcr.io/distroless/python3-debian13 or gcr.io/distroless/cc-debian13 with Python compiled) eliminating all shell binaries
- **FR-003**: Container MUST include a current Python version (Python 3.11 minimum, Python 3.12 preferred) for running initialization and health check scripts
- **FR-004**: All entrypoint logic currently in entrypoint.sh MUST be migrated to Python entrypoint script (entrypoint.py) including configuration validation, SSL certificate handling, directory creation, health check server startup, Squid process launch, and graceful shutdown handling
- **FR-005**: Python entrypoint MUST handle SIGTERM and SIGINT signals for graceful shutdown with identical behavior to current bash implementation (30-second timeout using asyncio, connection draining)
- **FR-006**: Python entrypoint MUST validate Squid configuration by executing `squid -k parse` and handling output/errors appropriately
- **FR-007**: Python entrypoint MUST detect and merge SSL-bump certificates (tls.crt + tls.key → squid-ca.pem) when SSL-bump is enabled in configuration
- **FR-008**: Python entrypoint MUST create required runtime directories (/var/run/squid, /var/log/squid, etc.) and validate write permissions, exiting immediately with exit code 1 and clear error message if validation fails
- **FR-009**: Python entrypoint MUST start health check server as background process and monitor its health before starting Squid
- **FR-010**: Python entrypoint MUST monitor Squid process using /proc filesystem parsing (no external dependencies) and exit if Squid dies unexpectedly
- **FR-011**: Container MUST maintain OpenShift arbitrary UID/GID compatibility without shell dependencies
- **FR-012**: Container startup time MUST not increase by more than 10% compared to current bash-based entrypoint
- **FR-013**: All logging from Python entrypoint MUST use Python logging module with structured output (timestamps, log levels) matching current bash script format
- **FR-014**: Container MUST NOT include any shell executables (bash, sh, busybox, dash, zsh) in the final runtime image

### Key Entities

- **Python Entrypoint Script**: Main initialization script that replaces entrypoint.sh, responsible for configuration validation, SSL setup, directory initialization, process management, and signal handling
- **Distroless Base Image**: Minimal Debian 13-based runtime image containing only Python interpreter, system libraries, and CA certificates (no shell, no package manager)
- **Multi-stage Build**: Build process with separate builder stage (Debian 13 slim for Squid compilation) and minimal runtime stage (distroless Debian 13)
- **Python Runtime**: Python 3.11+ interpreter and standard library modules required for entrypoint, initialization, and health check functionality

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Container image contains zero shell executables when scanned with `find / -name "bash" -o -name "sh" -o -name "busybox" 2>/dev/null`
- **SC-002**: Container exec commands attempting shell access (`docker exec -it <container> /bin/sh`) fail with "executable not found" error
- **SC-003**: Container image uses Debian 13 (Trixie) as base OS verified by inspecting /etc/os-release or image metadata
- **SC-004**: Container includes Python 3.11 or newer verified by executing `python3 --version` during build
- **SC-005**: Container startup time remains within 110% of current bash-based implementation (no more than 10% increase)
- **SC-006**: All existing integration tests pass without modification when run against new Python-based container
- **SC-007**: Python entrypoint script is less complex than bash version as measured by cyclomatic complexity (target: 30% reduction)
- **SC-008**: Container successfully handles SIGTERM gracefully with same 30-second timeout behavior as current implementation
- **SC-009**: Security scanners show reduced or equal CVE count compared to Debian 12 distroless debug variant

### Quality Measures

- Zero crashes or errors during container startup across all test scenarios
- Python entrypoint provides equivalent or better error messages compared to bash version
- Container exits immediately (fail fast) with clear error messages for all startup validation failures
- Container continues to pass OpenShift arbitrary UID/GID compatibility tests
- No increase in error rates or support requests after production deployment
- Debugging workflows using ephemeral debug containers work correctly

## Scope & Boundaries

### In Scope

- Migration from gcr.io/distroless/python3-debian12:debug to gcr.io/distroless/python3-debian13 (or equivalent non-debug variant)
- Compilation or inclusion of Python 3.11+ if distroless Python3 Debian 13 image doesn't exist
- Complete rewrite of entrypoint.sh as entrypoint.py in Python
- Migration of all bash logic to Python standard library (no shell subprocess calls)
- Validation that all container functionality works without shell access
- Documentation updates for debugging without shell (ephemeral debug containers)
- CI/CD pipeline updates for new base image and Python entrypoint

### Out of Scope

- Changes to init-squid.py or healthcheck.py (already Python, no changes needed)
- Modifications to Squid proxy configuration or features
- Changes to health check endpoints or protocols
- Modifications to deployment manifests (Kubernetes, Docker Compose)
- Performance optimizations beyond entrypoint migration
- New features or functionality additions
- Changes to logging format or structure beyond maintaining parity

## Assumptions

- gcr.io/distroless/python3-debian13 base image exists OR gcr.io/distroless/cc-debian13 can be used with compiled Python
- If Python must be compiled, Python 3.11+ compiles successfully on Debian 13 slim builder image
- Python standard library provides all necessary functionality for entrypoint logic (os, subprocess, signal, pathlib, logging, sys, time, re, asyncio)
- Debian 13 (Trixie) provides compatible versions of all Squid runtime dependencies
- Multi-stage build pattern (Debian 13 slim builder → distroless Debian 13 runtime) remains viable
- All current deployment targets (Docker, Kubernetes, OpenShift) support containers without shell
- Development team has Python proficiency for maintaining Python entrypoint
- Python process spawning (for health check server) and signal handling work correctly in distroless environment
- Debugging workflows can transition to ephemeral debug containers or distroless debug variant for troubleshooting

### Research Findings on Debian 13 Distroless Availability

**Status Check Required**: As of December 2025, Debian 13 (Trixie) was released but distroless images may not be immediately available. The implementation must verify:

1. **Check if gcr.io/distroless/python3-debian13 exists**: Query Google Container Registry for distroless Python Debian 13 images
2. **Fallback strategy if unavailable**:
   - Use gcr.io/distroless/cc-debian13 (base C/C++ runtime) and compile Python 3.11+ in builder stage
   - Copy compiled Python interpreter and standard library to distroless runtime
   - Ensure all Python dependencies (shared libraries) are included

**Python Version Selection**:
- Prefer Python 3.12 (latest stable as of 2026) for improved performance and security
- Minimum acceptable version: Python 3.11 (current version in existing container)
- Verify Python version is compatible with all standard library modules used in scripts

**Non-Debug Variant Verification**:
- Confirm non-debug distroless images contain NO shell binaries
- Validate that entrypoint can be set to Python script directly without shell wrapper
- Test that ENTRYPOINT ["/usr/bin/python3", "/usr/local/bin/entrypoint.py"] works correctly

## Dependencies

- Debian 13 (Trixie) slim image for build stage
- gcr.io/distroless/python3-debian13 OR gcr.io/distroless/cc-debian13 for runtime stage
- Python 3.11+ source code (if compilation required)
- Python standard library modules: os, sys, subprocess, signal, pathlib, logging, time, re, shutil, asyncio
- All current Squid runtime dependencies must be compatible with Debian 13
- CI/CD pipeline supports multi-stage builds with Debian 13 base images
- Security scanning tools can analyze distroless containers without shell

## Risks

- **Distroless Debian 13 Availability**: gcr.io/distroless/python3-debian13 may not exist yet, requiring Python compilation from source (adds build complexity)
- **Python Compilation Complexity**: Building Python from source increases build time and requires identifying all build dependencies
- **Signal Handling Differences**: Python signal handling may behave differently than bash traps (requires thorough testing)
- **Process Monitoring**: Python process monitoring without pgrep/ps requires robust /proc filesystem parsing implementation
- **Debugging Difficulty**: Complete shell removal makes troubleshooting production issues harder (requires training on ephemeral debug containers)
- **Entrypoint Migration Complexity**: Subtle behavioral differences between bash and Python may introduce regressions (requires extensive integration testing)
- **Debian 13 Compatibility**: Squid or its dependencies may have compatibility issues with Debian 13 libraries
- **Startup Performance**: Python interpreter startup overhead may increase container startup time beyond 10% threshold

## Non-Functional Requirements

- **Security**: Container must pass all vulnerability scanning gates with improved or equivalent scores compared to debug variant
- **Maintainability**: Python entrypoint must be well-documented with clear error messages and logging
- **Compatibility**: Must maintain 100% backward compatibility with current deployment methods and OpenShift arbitrary UID
- **Performance**: No degradation in proxy throughput, latency, or container startup time (max 10% increase acceptable)
- **Observability**: Maintain current logging levels and diagnostic capabilities using Python logging module
- **Debuggability**: Provide clear documentation for debugging without shell access using ephemeral debug containers
