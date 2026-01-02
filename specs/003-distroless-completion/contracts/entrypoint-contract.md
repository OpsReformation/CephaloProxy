# Entrypoint Behavioral Contract

**Feature**: 003-distroless-completion
**Date**: 2026-01-01
**Purpose**: Define precise behavioral contracts for Python entrypoint

## Contract Overview

This document specifies the **behavioral contract** for `entrypoint.py` - the inputs it accepts, outputs it produces, invariants it maintains, and failure modes it handles. This contract is implementation-independent and serves as the specification for testing.

## Input Contract

### Command-Line Interface

**Signature**:
```python
# Executed as:  /usr/bin/python3 /usr/local/bin/entrypoint.py
# No command-line arguments supported
```

**Preconditions**:
- Container must be run with valid UID (any UID ≥ 0)
- GID 0 (root group) required for OpenShift compatibility
- Python 3.11+ runtime must be available at `/usr/bin/python3`

### Environment Variables

| Variable | Type | Required | Default | Validation |
|----------|------|----------|---------|------------|
| `SQUID_PORT` | int | No | 3128 | 1-65535 |
| `HEALTH_PORT` | int | No | 8080 | 1-65535 |
| `LOG_LEVEL` | str | No | INFO | DEBUG\|INFO\|WARN\|ERROR |

**Contract**: Environment variables MAY be missing (defaults used). Invalid values MUST log warning and use default.

### Mounted Volumes

| Path | Type | Required | Purpose | Validation |
|------|------|----------|---------|------------|
| `/etc/squid/squid.conf` | File | Conditional | Squid configuration | If missing, copy from squid.conf.default |
| `/etc/squid/ssl_cert/tls.crt` | File | Conditional | TLS certificate | Required only if ssl-bump in config |
| `/etc/squid/ssl_cert/tls.key` | File | Conditional | TLS private key | Required only if ssl-bump in config |
| `/var/run/squid` | Directory | Yes | PID file storage | Must be writable |
| `/var/log/squid` | Directory | Yes | Squid logs | Must be writable |
| `/var/lib/squid` | Directory | Yes | SSL certs, metadata | Must be writable |
| `/var/spool/squid` | Directory | Yes | Cache storage | Must be writable |
| `/var/cache/squid` | Directory | Yes | Cache metadata | Must be writable |

**Contract**: All required directories MUST exist and be writable. Missing or non-writable directories MUST cause immediate exit with code 1.

### Signal Inputs

| Signal | Behavior | Timing |
|--------|----------|--------|
| SIGTERM | Graceful shutdown (30s timeout) | Handled only in RUNNING state |
| SIGINT | Graceful shutdown (30s timeout) | Handled only in RUNNING state |
| SIGHUP | Graceful shutdown (30s timeout) | Handled only in RUNNING state |
| SIGKILL | Immediate termination | Cannot be caught (OS-level) |

**Contract**: Signals received before RUNNING state are ignored. Signals in RUNNING state MUST trigger graceful shutdown within 30 seconds.

## Output Contract

### Exit Codes

| Exit Code | Condition | Stdout Content | Stderr Content |
|-----------|-----------|----------------|----------------|
| 0 | Clean shutdown after SIGTERM/SIGINT | Startup logs + shutdown logs | Empty (or warnings only) |
| 1 | Config validation failed | Validation attempt logs | Error message with squid -k parse output |
| 1 | Directory permission error | Validation attempt logs | Error message with path and UID/GID |
| 1 | SSL certificate missing | Validation attempt logs | Error message with missing file path |
| 1 | Subprocess start failed | Startup attempt logs | Error message with exception details |
| 1 | Squid died unexpectedly | Runtime logs | Error message with exit code |

**Contract**: Exit code 0 MUST only occur after successful shutdown. All errors MUST exit with code 1. Exit MUST happen immediately after error detection (fail-fast).

### Stdout Logging

**Format**:
```
YYYY-MM-DD HH:MM:SS [LEVEL] Message
```

**Guaranteed Log Lines** (in order):

1. **Startup Banner**:
   ```
   2026-01-01 12:00:00 [INFO] CephaloProxy entrypoint starting (UID: 1000, GID: 0)
   ```

2. **Validation Start**:
   ```
   2026-01-01 12:00:00 [INFO] Validating Squid configuration...
   ```

3. **Validation Success**:
   ```
   2026-01-01 12:00:01 [INFO] Configuration validation passed
   ```

4. **Health Server Start**:
   ```
   2026-01-01 12:00:01 [INFO] Starting health check server on port 8080
   ```

5. **Health Server Ready**:
   ```
   2026-01-01 12:00:03 [INFO] Health check server started (PID: <pid>)
   ```

6. **Squid Start**:
   ```
   2026-01-01 12:00:03 [INFO] Starting Squid proxy...
   ```

7. **Squid Ready**:
   ```
   2026-01-01 12:00:05 [INFO] Squid started with PID <pid>
   ```

8. **Ready State**:
   ```
   2026-01-01 12:00:05 [INFO] Container ready, entering monitoring loop
   ```

9. **Shutdown Signal** (if received):
   ```
   2026-01-01 12:05:00 [INFO] Received signal SIGTERM, initiating graceful shutdown...
   ```

10. **Shutdown Complete**:
    ```
    2026-01-01 12:05:02 [INFO] Shutdown complete
    ```

**Contract**: Log lines MUST appear in this order. Timestamps MUST be monotonically increasing. Each line MUST include timestamp, level, and message.

### Stderr Logging

**Purpose**: Error messages only

**Format**:
```
YYYY-MM-DD HH:MM:SS [ERROR] Error message with details
```

**Example Error Messages**:

```
2026-01-01 12:00:01 [ERROR] Squid configuration validation failed:
  squid: ERROR: No running copy
  squid: (1) Unable to open HTTP port

2026-01-01 12:00:01 [ERROR] Directory /var/run/squid is not writable (UID: 1000, GID: 0)

2026-01-01 12:00:01 [ERROR] SSL-bump enabled but TLS certificate not found: /etc/squid/ssl_cert/tls.crt

2026-01-01 12:00:05 [ERROR] Failed to start Squid: FileNotFoundError: /usr/sbin/squid

2026-01-01 12:05:00 [ERROR] Squid process died with exit code 127
```

**Contract**: Stderr MUST only contain ERROR-level messages. Each error MUST include enough context for diagnosis without shell access.

### File System Side Effects

| Path | Action | Timing | Permissions |
|------|--------|--------|-------------|
| `/etc/squid/squid.conf` | Copy from default if missing | VALIDATING state | 644 |
| `/var/lib/squid/squid-ca.pem` | Merge tls.crt + tls.key | VALIDATING state (if SSL-bump) | 600 |
| `/var/run/squid/squid.pid` | Created by Squid | STARTING_SQUID state | 644 |
| `/run/squid.pid` | Symlink to /var/run/squid/squid.pid | VALIDATING state | 777 (symlink) |

**Contract**: Entrypoint MUST NOT create files beyond listed side effects. All files MUST be owned by current UID. Permissions MUST match specified values.

### Process Tree

**Expected Process Hierarchy**:

```
PID 1:    /usr/bin/python3 /usr/local/bin/entrypoint.py
  ├─ PID X:  /usr/bin/python3 /usr/local/bin/healthcheck.py
  └─ PID Y:  /usr/sbin/squid -N -f /etc/squid/squid.conf
       └─ (Squid helper processes)
```

**Contract**:
- Python entrypoint MUST run as PID 1
- Health check server MUST be child of entrypoint
- Squid MUST be child of entrypoint
- Entrypoint MUST remain running until all children exit

## Behavioral Invariants

### Timing Invariants

| Invariant | Value | Measurement |
|-----------|-------|-------------|
| **I1**: Startup time | ≤ 110% of baseline | Time from container start to "Container ready" log |
| **I2**: Config validation | ≤ 5 seconds | Time from "Validating..." to "validation passed" log |
| **I3**: Shutdown timeout | Exactly 30 seconds | Maximum wait for Squid SIGTERM → force SIGKILL |
| **I4**: Process monitoring interval | 1 second ± 100ms | Time between /proc existence checks |
| **I5**: Health server startup | 2 seconds ± 500ms | Time from launch to PID verification |

**Contract**: Timing invariants MUST be maintained across all supported platforms (amd64, arm64). Violations MAY occur under extreme resource contention but MUST be logged.

### State Invariants

| Invariant | Condition | Verification |
|-----------|-----------|--------------|
| **I6**: Unidirectional state machine | States only move forward | Code review + state logging |
| **I7**: Single error exit | ERROR state always → exit code 1 | Exit code assertion |
| **I8**: Squid monitoring | While in RUNNING, /proc/<squid_pid> checked every 1s | Async loop verification |
| **I9**: Signal handling isolation | Signals only handled in RUNNING state | Signal handler registration timing |
| **I10**: Resource cleanup | All subprocesses terminated before exit | Process tree inspection |

**Contract**: State invariants MUST hold for all execution paths. Violation indicates implementation bug.

### Security Invariants

| Invariant | Requirement | Enforcement |
|-----------|-------------|-------------|
| **I11**: No shell execution | Zero subprocess calls to sh/bash | Code review (only python3, squid binaries) |
| **I12**: File permissions | Merged SSL cert = 600, configs = 644 | os.chmod() validation |
| **I13**: UID preservation | Entrypoint runs as startup UID (no privilege escalation) | os.getuid() check |
| **I14**: Secret handling | SSL certs never logged to stdout/stderr | Logging filter |
| **I15**: Error message safety | No sensitive data in error messages | Manual review |

**Contract**: Security invariants are non-negotiable. Violations MUST be treated as critical bugs.

## Failure Modes

### Handled Failures

| Failure | Detection | Recovery | Exit Code |
|---------|-----------|----------|-----------|
| Config validation error | `squid -k parse` returns non-zero | Log error, exit immediately | 1 |
| Directory not writable | `Path.touch()` raises PermissionError | Log error with path and UID, exit | 1 |
| SSL cert missing | `Path.exists()` returns False | Log error with expected path, exit | 1 |
| Health server crash | /proc/<pid> missing after 2s | Log error, exit | 1 |
| Squid start failure | PID file not created in 30s | Log error, exit | 1 |
| Squid runtime crash | /proc/<pid> missing during monitoring | Log error with last known PID, exit | 1 |
| Shutdown timeout | 30s elapsed, Squid still running | Log warning, send SIGKILL, exit cleanly | 0 |

**Contract**: All failures MUST be detected within 30 seconds. Detection MUST trigger logged action. No silent failures.

### Unhandled Failures (Crash)

| Failure | Behavior | Mitigation |
|---------|----------|------------|
| Python interpreter crash | Immediate container termination | None (OS-level) |
| Out of memory | Python MemoryError exception | Container restart (orchestrator) |
| Disk full | OSError during logging or file writes | Log to stderr (best effort), exit 1 |
| /proc filesystem unavailable | FileNotFoundError in monitoring loop | Log error, exit 1 |

**Contract**: Unhandled failures result in container crash. Orchestrator MUST restart container. Entrypoint MUST NOT attempt automatic recovery.

## Concurrency Contract

### Asyncio Event Loop

**Single-Threaded Model**:
- Only ONE asyncio event loop
- All I/O operations are async (no blocking calls)
- Subprocess management via `asyncio.create_subprocess_exec()`

**Task Lifecycle**:

```python
main_task = asyncio.run(main())  # Entry point
  ├─ health_server_task           # Background task
  ├─ squid_monitor_task           # Background task
  └─ signal_handler_tasks         # Created on-demand
```

**Contract**: All tasks MUST be cancellable. No task MUST block the event loop for > 100ms. Subprocess waits MUST use async APIs.

### Signal Handler Concurrency

**Guarantee**: Only one signal handler executes at a time (event loop serialization).

**Race Conditions Prevented**:
- Multiple SIGTERM signals → Only one shutdown sequence
- SIGTERM during Squid startup → Handled after Squid reaches RUNNING state
- SIGTERM during shutdown → Ignored (already shutting down)

**Contract**: Signal handlers MUST be idempotent. Multiple invocations MUST be safe.

## Performance Contract

### Resource Limits

| Resource | Limit | Measurement |
|----------|-------|-------------|
| Memory (entrypoint) | ≤ 50 MB RSS | Process memory from /proc |
| CPU (entrypoint) | ≤ 5% of 1 core | Averaged over 1 minute |
| File handles | ≤ 20 open FDs | /proc/<pid>/fd count |
| Startup time | ≤ 10 seconds | Wall clock time to "Container ready" |

**Contract**: Resource limits apply to entrypoint process only (excluding Squid). Exceeding limits MAY indicate memory leaks or bugs.

### Scalability Contract

**Constraint**: Entrypoint is designed for SINGLE container instance.

**NOT Supported**:
- Managing multiple Squid processes
- Load balancing across Squid instances
- Horizontal scaling of entrypoint itself

**Contract**: One entrypoint → One Squid. Horizontal scaling achieved via container replication (Kubernetes pods), not internal process management.

## Testing Contract

### Unit Test Coverage

**Required Tests**:

1. `/proc` parsing functions
   - `/proc/<pid>` existence check (positive/negative)
   - `/proc/<pid>/status` parsing (valid/invalid/missing)

2. Configuration validation
   - Valid squid.conf → success
   - Invalid squid.conf → error + stderr output
   - Missing squid.conf → copy from default

3. Directory validation
   - All directories writable → success
   - One directory non-writable → error + exit 1

4. SSL certificate handling
   - ssl-bump enabled + certs present → merge successful
   - ssl-bump enabled + certs missing → error + exit 1
   - ssl-bump disabled → skip cert validation

5. Signal handling
   - SIGTERM in RUNNING → graceful shutdown
   - SIGTERM during startup → ignored
   - Shutdown timeout → force SIGKILL

**Contract**: Unit tests MUST cover all code paths with ≥ 90% branch coverage.

### Integration Test Requirements

**Required Integration Tests** (Bats):

1. **test-container-startup.bats**
   - Container starts successfully
   - All log lines appear in correct order
   - Squid PID file created
   - Health endpoint responds 200 OK

2. **test-shell-absence.bats**
   - `docker exec <container> /bin/sh` fails
   - `docker exec <container> /bin/bash` fails
   - `docker exec <container> sh` fails
   - Image scan confirms zero shell binaries

3. **test-graceful-shutdown.bats**
   - `docker stop <container>` completes in ≤ 35s (30s + 5s buffer)
   - Squid logs show clean shutdown
   - Exit code = 0

4. **test-process-monitoring.bats**
   - Kill Squid process directly (`kill -9 <squid_pid>`)
   - Container exits with code 1 within 2 seconds
   - Logs show "Squid process died" error

5. **test-openshift-uid.bats**
   - Run container with arbitrary UID (e.g., 1234567)
   - Container starts successfully
   - All functionality works

**Contract**: Integration tests MUST run against built container image. All tests MUST pass before merge.

## Compatibility Contract

### Backward Compatibility

**Preserved Behaviors** (from bash entrypoint):

| Behavior | Bash Version | Python Version |
|----------|--------------|----------------|
| Log format | Color codes (GREEN/RED/YELLOW) | Plain text (no colors) |
| SSL cert location | /var/lib/squid/squid-ca.pem | /var/lib/squid/squid-ca.pem |
| PID file location | /var/run/squid/squid.pid | /var/run/squid/squid.pid |
| Config selection | Custom > default | Custom > default |
| Shutdown timeout | 30 seconds | 30 seconds |

**Contract**: Python version MUST maintain functional equivalence. Minor differences (log colors) are acceptable.

### Breaking Changes

**Intentional Breaking Changes**:

| Change | Bash Behavior | Python Behavior | Rationale |
|--------|---------------|-----------------|-----------|
| Log colors | ANSI escape codes | Plain text | Distroless lacks shell color support, structured logs more parseable |
| Process monitoring | `pgrep`, `ps` commands | /proc parsing | No shell utilities in distroless runtime |

**Contract**: Breaking changes MUST be documented. Alternative patterns (ephemeral debug containers) MUST be provided.

## Contract Verification

### Pre-Deployment Checklist

- [ ] Exit code contract verified (0 on clean shutdown, 1 on errors)
- [ ] Log format contract verified (all required log lines present)
- [ ] Timing invariants measured (startup ≤ 110%, shutdown = 30s)
- [ ] Signal handling tested (SIGTERM/SIGINT trigger graceful shutdown)
- [ ] Error messages verified (contain actionable diagnostic info)
- [ ] File permissions verified (SSL cert = 600, configs = 644)
- [ ] Resource limits measured (memory ≤ 50MB, CPU ≤ 5%)
- [ ] Integration tests passing (startup, shutdown, monitoring, shell absence)

**Contract**: All checklist items MUST pass before production deployment.

## Contract Summary

This behavioral contract defines:

- ✅ Input contract (CLI, env vars, volumes, signals)
- ✅ Output contract (exit codes, logs, file system effects, process tree)
- ✅ 15 behavioral invariants (timing, state, security)
- ✅ 7 handled failure modes with recovery strategies
- ✅ 4 unhandled failure modes with mitigation
- ✅ Concurrency model (asyncio, signal handling)
- ✅ Performance contract (resource limits, scalability)
- ✅ Testing requirements (unit + integration)
- ✅ Compatibility guarantees (backward compat + breaking changes)

**Next**: See [quickstart.md](../quickstart.md) for developer setup and testing workflow.
