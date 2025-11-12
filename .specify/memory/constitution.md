<!--
SYNC IMPACT REPORT
==================
Version Change: NONE → 1.0.0
Change Type: MAJOR - Initial constitution ratification
Modified Principles: N/A (initial creation)
Added Sections:
  - Core Principles (5 principles)
  - Security Requirements
  - Performance Standards
  - Observability Requirements
  - Governance
Removed Sections: N/A
Templates Status:
  ✅ .specify/templates/plan-template.md - Aligned with constitution check requirements
  ✅ .specify/templates/spec-template.md - Aligned with test-first and container requirements
  ✅ .specify/templates/tasks-template.md - Aligned with TDD workflow and observability tasks
Follow-up TODOs: None - all placeholders resolved
-->

# CephaloProxy Constitution

## Core Principles

### I. Container-First Architecture

CephaloProxy MUST be deployed as a Docker container with the following non-negotiable requirements:

- All functionality MUST be containerized with proper health checks and graceful shutdown
- Configuration MUST be injectable via environment variables or mounted config files
- Container images MUST be reproducible, tagged with semantic versions, and scannable for vulnerabilities
- Container MUST support both standalone and orchestrated (Docker Compose, Kubernetes) deployments
- Host dependencies MUST be minimized; container MUST be self-contained

**Rationale**: Container-first architecture ensures portability, consistent deployment environments, and seamless integration with modern infrastructure automation.

### II. Test-First Development (NON-NEGOTIABLE)

Test-Driven Development is mandatory for all feature work:

- Tests MUST be written BEFORE implementation
- User MUST approve tests
- Tests MUST fail initially (red phase)
- Implementation proceeds only after failing tests confirmed
- Red-Green-Refactor cycle strictly enforced
- Integration tests MUST verify container behavior, network communication, and Squid proxy functionality

**Rationale**: TDD ensures requirements are testable, prevents scope creep, and validates that tests detect actual failures before implementation begins.

### III. Squid Proxy Integration

CephaloProxy wraps Squid Proxy with operational enhancements:

- Squid configuration MUST be version-controlled and validated before container startup
- Caching, filtering, and transformation rules MUST be declarative and testable
- Squid logs MUST be aggregated and forwarded to structured logging systems
- Configuration changes MUST trigger validation and automated testing before deployment
- Squid version MUST be explicitly pinned; upgrades MUST be tested in isolation

**Rationale**: Squid is a mature, battle-tested proxy. CephaloProxy adds containerization, observability, and operational rigor without reinventing core proxy logic.

### IV. Security by Default

Security is non-negotiable and MUST be built-in:

- TLS termination and mutual TLS support for encrypted upstream/downstream communication
- Access control lists (ACLs) MUST be enforced and auditable
- Secrets (certificates, credentials) MUST be injected securely (never hardcoded)
- Container MUST run as non-root user with minimal privileges
- All security events (denied requests, authentication failures) MUST be logged
- Vulnerability scanning MUST be part of CI/CD pipeline

**Rationale**: Proxies are security-critical infrastructure. Default-secure configuration prevents accidental exposure and enforces least-privilege principles.

### V. Observable by Default

Observability is mandatory for production readiness:

- Structured logging (JSON format) with request IDs for traceability
- Metrics exposure (Prometheus format) for cache hit rates, request latency, error rates
- Health check endpoints for container orchestrators
- Graceful shutdown with connection draining to prevent dropped requests
- Configuration reload without downtime where possible

**Rationale**: Proxies are critical path infrastructure. Observability enables debugging, capacity planning, and rapid incident response.

## Security Requirements

CephaloProxy MUST enforce the following security standards:

- **Authentication**: Support for basic auth, bearer tokens, or mutual TLS as configured
- **Authorization**: ACLs based on source IP, destination domain, HTTP method, or custom headers
- **Encryption**: TLS 1.2+ for upstream/downstream connections; deprecated protocols explicitly blocked
- **Audit Logging**: All denied requests logged with source, destination, reason, and timestamp
- **Vulnerability Management**: Container base images updated within 7 days of critical CVE disclosure
- **Secret Management**: Integration with Docker secrets, Kubernetes secrets, or Vault for credential injection

## Performance Standards

CephaloProxy MUST meet these performance requirements:

- **Latency**: P95 latency < 50ms added overhead (proxy processing time excluding upstream)
- **Throughput**: Support minimum 1000 requests/second per container instance
- **Cache Efficiency**: Cache hit rate > 40% for cacheable content (measured via metrics)
- **Resource Usage**: < 512MB memory baseline, < 1 CPU core at 1000 req/s
- **Startup Time**: Container ready (health check passing) within 10 seconds
- **Connection Limits**: Configurable max connections with graceful rejection beyond limits

## Observability Requirements

CephaloProxy MUST provide:

- **Structured Logs**: JSON format with fields: timestamp, level, request_id, source_ip, destination, method, status_code, latency_ms, cache_status
- **Metrics**: Exposed on `/metrics` endpoint:
  - `cephaloproxy_requests_total{method,status,cache_status}`
  - `cephaloproxy_request_duration_seconds{method,status}`
  - `cephaloproxy_cache_hit_rate`
  - `cephaloproxy_upstream_errors_total{upstream}`
  - `cephaloproxy_active_connections`
- **Health Checks**: `/health` (liveness) and `/ready` (readiness) endpoints
- **Tracing**: Optional distributed tracing integration (OpenTelemetry compatible)

## Governance

This constitution supersedes all other development practices and serves as the single source of truth for CephaloProxy's non-negotiable requirements.

**Amendment Procedure**:

- Constitutional amendments MUST be proposed via written rationale documenting the problem, proposed change, and impact
- Amendments MUST update the version according to semantic versioning (MAJOR for breaking changes, MINOR for additions, PATCH for clarifications)
- All dependent templates (plan, spec, tasks) MUST be updated for consistency
- Amendment approval requires validation that existing features remain compliant

**Compliance**:

- All pull requests MUST verify constitutional compliance before merge
- Plan documents MUST include a "Constitution Check" section validating adherence
- Any complexity or deviation MUST be explicitly justified in plan documentation
- Automated tests MUST validate security, performance, and observability requirements

**Version**: 1.0.0 | **Ratified**: 2025-11-11 | **Last Amended**: 2025-11-11
