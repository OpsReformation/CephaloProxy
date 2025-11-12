# Implementation Plan: Squid Proxy Container

**Branch**: `001-squid-proxy-container` | **Date**: 2025-11-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-squid-proxy-container/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a containerized Squid proxy with SSL-bump support for HTTPS caching, traffic filtering via ACLs, and flexible configuration. The container uses Gentoo Linux as the base to compile Squid with SSL-bump support (not available in most binary distributions). Key capabilities include: default-working configuration, volume mounts for cache/certificates/ACLs, health check endpoints, and OpenShift compatibility with random UID/GID support.

## Technical Context

**Base Image**: gentoo/stage3 (Gentoo Linux base for compiling Squid with SSL-bump)
**Package Manager**: Portage (gentoo/portage overlay)
**Primary Dependencies**:
- Squid 6.x (pinned via Portage slot, compiled with --enable-ssl-crtd for SSL-bump support)
- OpenSSL (for TLS/SSL support)
- Python 3.11+ (for health check HTTP server on :8080)

**Storage**: File-based (cache in /var/spool/squid or /tmp, configs in /etc/squid/)
**Testing**: Bash/bats integration tests with Docker Compose for multi-container scenarios
**Target Platform**: Linux containers (Docker, Podman, Kubernetes, OpenShift)
**Project Type**: Single containerized application
**Performance Goals**: 1000 req/s minimum throughput, P95 < 50ms added latency, 40%+ cache hit rate
**Constraints**:
- <512MB memory baseline
- <1 CPU core at 1000 req/s
- <10 second startup time
- Support random UID/GID for OpenShift compatibility

**Scale/Scope**: Single-container deployment, horizontally scalable via orchestrator replication

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Initial Check (Before Phase 0)

Verify compliance with CephaloProxy Constitution v1.0.0:

- [x] **Container-First Architecture**: ✅ Feature is 100% containerized - Dockerfile, health checks planned, graceful shutdown via SIGTERM handling
- [x] **Test-First Development**: ✅ Test structure planned (tests/integration/) organized by user story, TDD workflow enforced
- [x] **Squid Proxy Integration**: ✅ Squid 6.x pinned, configs declarative (squid.conf), validation via `squid -k parse`
- [x] **Security by Default**: ✅ Non-root user (UID 1000/GID 0), secrets via volume mounts, OpenShift arbitrary UID support
- [x] **Observable by Default**: ✅ Health endpoints (/health, /ready) specified in contracts/, Squid logging configured

**Additional Compliance**:

- [x] Security Requirements: ✅ TLS 1.2+ via OpenSSL, SSL-bump for encrypted traffic, audit logging for denied requests, vulnerability scanning planned in CI/CD
- [x] Performance Standards: ✅ Targets specified (P95 < 50ms, 1000 req/s, <512MB memory, 10s startup)
- [x] Observability Requirements: ✅ Squid native logging (best practices), health endpoints specified, metrics endpoint reserved for future

**Result**: ✅ **PASS** - All constitutional requirements met

### Post-Design Re-Check (After Phase 1)

- [x] **Container-First Architecture**: ✅ Confirmed - Multi-stage Dockerfile design, healthcheck.py implementation, entrypoint.sh with graceful shutdown
- [x] **Test-First Development**: ✅ Confirmed - Test files mapped to user stories (test_basic_proxy.sh → US1, test_acl_filtering.sh → US2, etc.)
- [x] **Squid Proxy Integration**: ✅ Confirmed - Gentoo Portage build strategy ensures Squid version pinning, SSL-bump USE flags documented
- [x] **Security by Default**: ✅ Confirmed - Volume permissions (group-writable GID 0), secret injection via /etc/squid/ssl_cert, no hardcoded credentials
- [x] **Observable by Default**: ✅ Confirmed - healthcheck.py provides liveness/readiness probes, Squid access.log and cache.log configured

**Additional Compliance Re-Check**:

- [x] Security Requirements: ✅ Confirmed - SSL certificates via volume mount, ACL-based authorization, non-root execution verified
- [x] Performance Standards: ✅ Confirmed - Cache configuration (250MB ephemeral default, configurable), performance targets in success criteria
- [x] Observability Requirements: ✅ Confirmed - Squid logging per industry standards (access.log with cache_status), health check API contract documented

**Result**: ✅ **PASS** - All constitutional requirements validated post-design

**No violations to justify** - All complexity is inherent to the feature requirements (SSL-bump requires custom compilation, OpenShift requires GID 0 support)

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
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
├── Dockerfile                 # Multi-stage Gentoo-based build
├── entrypoint.sh             # Container entrypoint with startup logic
├── healthcheck.py            # HTTP server for /health and /ready endpoints
├── squid.conf.default        # Default Squid configuration template
└── init-squid.sh             # Initialization script (cache dirs, permissions)

config-examples/
├── ssl-bump/
│   └── squid.conf            # Example SSL-bump configuration
├── filtering/
│   ├── squid.conf            # Example ACL filtering configuration
│   └── blocked-domains.acl   # Example ACL file
└── advanced/
    └── squid.conf            # Example advanced configuration

tests/
├── integration/
│   ├── test_basic_proxy.sh          # Test US1: Basic proxy deployment
│   ├── test_acl_filtering.sh        # Test US2: Traffic filtering
│   ├── test_ssl_bump.sh             # Test US3: SSL-bump caching
│   ├── test_custom_config.sh        # Test US4: Advanced configuration
│   └── test_health_checks.sh        # Test health endpoints
└── fixtures/
    ├── test-certs/                   # Test SSL certificates
    └── test-configs/                 # Test configuration files

docs/
├── deployment.md             # Deployment guide (Docker, K8s, OpenShift)
├── configuration.md          # Configuration reference
└── troubleshooting.md        # Common issues and solutions

.github/
└── workflows/
    └── build-and-test.yml    # CI/CD pipeline
```

**Structure Decision**: Container-first architecture with all containerization artifacts in `container/` directory. The repository is organized around the container build process rather than traditional source code structure, as the primary deliverable is the container image itself. Test structure follows user story organization for independent verification.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
