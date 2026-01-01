# Feature Specification: Distroless Container Migration

**Feature Branch**: `002-distroless-migration`
**Created**: 2025-12-31
**Status**: Draft
**Input**: User description: "I want to reduce the number of dependencies in cephaloproxy by moving it towards a distroless implementation. The focus should be on reducing the threat surface from unused libraries and dependencies. To further reduce dependencies I want to migrate the existing bash scripts to python."

**Constitutional Compliance**: All features must comply with CephaloProxy Constitution v1.0.0 (see `.specify/memory/constitution.md`)

## Clarifications

### Session 2025-12-31

- Q: What logging approach should the Python initialization scripts use? → A: Python logging module writes to stdout/stderr with INFO level, structured as plain text with timestamps (matches current bash script behavior)
- Q: How should the Python initialization scripts handle missing required volumes (e.g., /var/spool/squid cache directory not mounted)? → A: Fail immediately with an error if required volumes are not mounted. Use the squid.conf file to determine if an "optional" volume, like the cache directory, is required for the current implementation

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Container Image Security Audit (Priority: P1)

Security-conscious operations teams need to validate that container images have minimal attack surface by auditing installed packages and dependencies, so they can meet organizational security compliance requirements and reduce vulnerability exposure.

**Why this priority**: Security is foundational - reducing the attack surface is the primary goal and must be validated before any other benefits can be realized.

**Independent Test**: Can be fully tested by scanning the container image with vulnerability scanners (Trivy, Snyk) and comparing CVE count and dependency count before/after migration. Delivers immediate security value through measurable reduction in exposed packages.

**Acceptance Scenarios**:

1. **Given** a security team scans the current Gentoo-based container image, **When** they compare it to the new minimal container image, **Then** they observe a measurable reduction (target: 80%+) in the number of installed packages
2. **Given** a vulnerability scanner runs against both images, **When** results are compared, **Then** the new image shows fewer total CVEs due to reduced package count
3. **Given** the container starts successfully, **When** operations verify running processes, **Then** only essential proxy processes are running with no unnecessary system daemons
4. **Given** an enterprise user needs custom CA certificates, **When** they review the documentation, **Then** they find clear instructions for extending CephaloProxy image with their custom CAs using multi-stage build pattern

---

### User Story 2 - Operational Reliability Validation (Priority: P2)

System administrators need to verify that the minimized container maintains full operational capability for proxy functionality, health checks, and graceful shutdown, so they can confidently deploy in production without functionality regressions.

**Why this priority**: After security is validated, operational reliability ensures the migration doesn't break existing workflows and maintains feature parity.

**Independent Test**: Can be tested by running the integration test suite against the new container and comparing results with the current container. Validates all core proxy features work identically.

**Acceptance Scenarios**:

1. **Given** the integration tests for basic proxy functionality, **When** run against the new minimal container, **Then** all tests pass with same behavior as current container
2. **Given** health check endpoints (/health, /ready) are tested, **When** queried during container startup and runtime, **Then** endpoints respond correctly with appropriate status codes
3. **Given** the container receives a termination signal, **When** graceful shutdown is initiated, **Then** active connections complete and cache is properly closed before exit

---

### User Story 3 - Maintenance Efficiency Improvement (Priority: P3)

Development teams need unified tooling and reduced script complexity to maintain container initialization logic, so they can make changes faster and with fewer bugs across different runtime environments.

**Why this priority**: While valuable for long-term maintainability, this is lower priority than security and operational correctness.

**Independent Test**: Can be tested by executing startup initialization scripts and validating outputs match current behavior. Measures script execution time and complexity reduction.

**Acceptance Scenarios**:

1. **Given** container startup initialization scripts, **When** executed in various environments (local Docker, Kubernetes, OpenShift), **Then** initialization completes successfully with consistent behavior
2. **Given** error conditions during startup (missing volumes, permission issues), **When** initialization scripts encounter these errors, **Then** clear error messages are logged specifying the missing volume path or permission issue, and container fails immediately (exit code 1)
3. **Given** a squid.conf with cache_dir directive, **When** the cache volume is not mounted, **Then** Python initialization script detects the missing required volume by parsing squid.conf and fails with error message identifying the expected volume path
4. **Given** the legacy bash scripts, **When** comparing line count and complexity metrics to new implementation, **Then** new implementation shows measurable reduction in complexity

---

### Edge Cases

- **Missing required volumes**: Python initialization scripts parse squid.conf to identify required volumes (e.g., cache_dir directive indicates cache volume required). Container fails immediately with error message specifying missing volume path if required volume not mounted or not writable
- **Missing optional dependencies**: Container starts successfully since distroless image includes only required runtime dependencies. FR-002 ensures all required dependencies present
- **Shell utilities unavailable**: FR-007 ensures Python logging provides sufficient diagnostic information. Debug scenarios use distroless debug variant or ephemeral debug container pattern
- **Persistent state during restarts**: Persistent volumes (/var/spool/squid, /var/lib/squid, /var/log/squid) maintain state across restarts. Python scripts validate persistence layer accessibility during initialization
- **Health checks without debugging tools**: Python-based health check server (healthcheck.py) uses HTTP endpoints without requiring shell utilities

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Container image MUST maintain identical proxy functionality including HTTP/HTTPS handling, SSL-bump capability, ACL filtering, and caching behavior
- **FR-002**: Container MUST include only runtime dependencies required for proxy operation (Squid binary, Python runtime for scripts, required shared libraries)
- **FR-003**: Health check endpoints MUST remain operational with /health and /ready returning appropriate status codes
- **FR-004**: Container MUST support graceful shutdown handling with proper signal trapping and connection draining
- **FR-005**: Initialization logic MUST handle all current startup scenarios including cache initialization, SSL certificate setup, configuration validation, and permission checks. Python scripts MUST parse squid.conf to determine required volumes (e.g., cache_dir directive presence) and fail immediately with clear error messages if required volumes are not mounted or writable
- **FR-006**: Container MUST work in OpenShift with arbitrary UID/GID assignment maintaining current compatibility
- **FR-007**: Error messages and logging MUST provide sufficient diagnostic information for troubleshooting without requiring interactive shell access. Python initialization scripts MUST use the Python logging module configured to write to stdout/stderr at INFO level with plain text format including timestamps, matching current bash script behavior
- **FR-008**: Container startup time MUST not increase by more than 10% compared to current Gentoo-based image
- **FR-009**: Container MUST expose the same ports (3128 for proxy, 8080 for health checks) with identical behavior
- **FR-010**: All existing volume mounts (/etc/squid/squid.conf, /etc/squid/conf.d/, /etc/squid/ssl_cert/, /var/spool/squid, /var/log/squid) MUST work identically
- **FR-011**: Container MUST include default system CA certificates and provide documentation for users to extend the image with custom CAs if needed (enterprise requirement)

### Key Entities

- **Container Image**: Minimal Linux container containing only essential runtime components (base OS layer, Python runtime, Squid binary, initialization scripts)
- **Initialization Scripts**: Logic executed during container startup to prepare the runtime environment (cache setup, permission validation, SSL database initialization)
- **Runtime Dependencies**: Shared libraries and binaries required for proxy operation (libc, SSL libraries, Python standard library modules)
- **Health Check System**: HTTP endpoints and monitoring logic that validate container health and readiness

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Container image size reduces by at least 40% compared to current Gentoo-based image
- **SC-002**: Number of installed packages in container reduces by at least 80% compared to current image
- **SC-003**: Vulnerability scan shows at least 60% reduction in total CVE count compared to current image
- **SC-004**: All existing integration tests pass without modification when run against new container
- **SC-005**: Container startup time remains within 110% of current startup time (no more than 10% increase)
- **SC-006**: No operational regressions - all current functionality works identically in production deployments
- **SC-007**: Initialization script complexity reduces by at least 30% as measured by cyclomatic complexity or line count
- **SC-008**: Build time for container image reduces by at least 70% through migration to Debian-based multi-stage build with distroless runtime (compared to Gentoo source compilation)

### Quality Measures

- Zero crashes or errors during container startup across test scenarios
- Health check endpoints respond within same latency as current implementation
- Container continues to pass all security scanning gates in CI/CD pipeline
- No increase in error rates or support tickets after production deployment

## Scope & Boundaries

### In Scope

- Migration from Gentoo-based image to Debian → gcr.io/distroless multi-stage build
- Conversion of bash initialization scripts to Python equivalents
- Removal of unnecessary packages and runtime dependencies
- Validation that all existing features work identically
- Updating CI/CD pipeline for new build process
- Documentation updates for new container architecture
- Documentation for extending CephaloProxy image with custom CA certificates (enterprise use case)

### Out of Scope

- Changes to Squid proxy configuration or features
- Modifications to API endpoints or external interfaces
- Changes to deployment manifests (Kubernetes, Docker Compose)
- Performance optimizations beyond dependency reduction
- New features or functionality additions
- Changes to logging format or structure (unless required by migration)

## Assumptions

- Python runtime footprint is smaller than bash + coreutils + other shell dependencies
- Debian-based multi-stage build to gcr.io/distroless runtime achieves true distroless architecture
- Squid can be compiled on Debian with --enable-ssl-crtd and --with-openssl flags for SSL-bump support
- Current bash scripts can be directly ported to Python without architectural changes
- Multi-stage build approach separates compilation (Debian) from runtime (distroless) for minimal final image
- All current deployment targets (Docker, Kubernetes, OpenShift) support distroless containers
- Development team has Python proficiency for maintaining migrated scripts
- CA certificates bundle (system defaults) must be included in distroless runtime for TLS certificate validation
- CephaloProxy build uses default system CAs only - no custom CA injection at CephaloProxy build time
- Users requiring custom CAs can extend the CephaloProxy image using `FROM cephaloproxy:latest` pattern with their own CA injection logic

### Research Findings on Base Image Selection

Based on analysis of production Squid SSL-bump container implementations and distroless requirements:

**Debian Slim → gcr.io/distroless (Recommended)**:

- True distroless runtime: No shell, no package manager, minimal attack surface
- Multi-stage build: Compile Squid on Debian Slim, copy binaries to gcr.io/distroless/cc-debian12
- SSL-bump support: Compile with --enable-ssl-crtd and --with-openssl flags (verified in Debian build system)
- Build time reduction: 60-70% compared to Gentoo (apt binary packages + faster compilation than emerge)
- Final image size: ~80-120MB (85% smaller than current 500MB+ Gentoo image)
- Security: Google-maintained distroless base images, regularly updated with security patches
- CA certificates: gcr.io/distroless/cc-debian12 includes ca-certificates for TLS validation
- glibc compatibility: Uses glibc (same as Gentoo), avoiding musl compatibility issues

**Alternative Approaches Evaluated**:

- **Alpine Linux**: 8MB images with pre-built Squid, but NOT truly distroless (includes shell, apk package manager)
- **Chainguard squid-proxy**: True distroless with zero CVEs, but requires licensing for production use
- **Kubler + Gentoo**: True distroless capability, but unmaintained (last update 2020) and same slow build times as current Gentoo

**Decision Rationale**: Debian → distroless provides the optimal balance of true distroless architecture, reasonable build times (meeting SC-008), active maintenance, and SSL-bump support. The glibc-based runtime ensures compatibility with compiled Squid binaries without musl-related issues.

## Dependencies

- Debian Slim base image for build stage (compile Squid with SSL-bump support)
- gcr.io/distroless/cc-debian12 for runtime stage (includes glibc, ca-certificates, minimal dependencies)
- Squid source code or Debian package sources for compilation with --enable-ssl-crtd --with-openssl
- Python 3.11+ for runtime (copied from python:3.11-slim or compiled)
- CA certificates bundle for TLS validation (included in distroless/cc base)
- CI/CD pipeline supports multi-stage builds for creating minimal images
- Security scanning tools (Trivy) can analyze distroless-based container images

## Risks

- **Compilation Complexity**: Compiling Squid from source on Debian may require identifying all build dependencies and configure flags
- **Dependency Mapping**: Must identify exact shared libraries needed in distroless runtime (ldd analysis required)
- **Migration Complexity**: Converting bash scripts to Python may introduce subtle behavioral differences requiring extensive testing
- **Debug Difficulty**: Lack of shell and debugging utilities in distroless container will complicate troubleshooting production issues (no interactive debugging)
- **Base Image Support**: Chosen distroless base image must receive timely security updates (mitigated by Google's maintenance commitment)
- **Dependency Discovery**: May discover hidden dependencies during migration that aren't immediately obvious from current scripts
- **Performance Regression**: Python startup overhead might impact container initialization time
- **CA Certificate Updates**: Must ensure CA certificates stay current in distroless base (Google maintains this)
- **Custom CA Extension Pattern**: Users needing custom CAs must extend CephaloProxy image with multi-stage build (documented pattern provided), as distroless runtime lacks update-ca-certificates utility

## Non-Functional Requirements

- **Security**: Container must pass all current vulnerability scanning gates with improved scores
- **Maintainability**: New Python scripts must be well-documented and follow Python best practices
- **Compatibility**: Must maintain 100% backward compatibility with current deployment methods
- **Performance**: No degradation in proxy throughput, latency, or cache hit rates
- **Observability**: Maintain current logging levels and diagnostic capabilities. Python initialization scripts use Python logging module with INFO level, plain text format to stdout/stderr with timestamps
