# Data Model: Python Entrypoint State Machine

**Feature**: 003-distroless-completion
**Date**: 2026-01-01
**Purpose**: Define entrypoint behavior, state transitions, and process lifecycle

## Overview

The Python entrypoint (`entrypoint.py`) manages container initialization, process orchestration, and graceful shutdown through a state machine. This document defines all states, transitions, and invariants.

## Entrypoint State Machine

### States

```text
┌─────────────┐
│ INITIALIZING│ (Entry point)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ VALIDATING  │ (Config validation, directory checks)
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│ STARTING_HEALTH  │ (Launch healthcheck.py)
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ STARTING_SQUID   │ (Launch Squid process)
└──────┬───────────┘
       │
       ▼
┌─────────────┐
│   RUNNING   │ (Monitor Squid, handle requests)
└──────┬──────┘
       │ (SIGTERM/SIGINT)
       ▼
┌──────────────┐
│ SHUTTING_DOWN│ (30s graceful shutdown)
└──────┬───────┘
       │
       ▼
┌─────────────┐
│   EXITED    │ (Terminal state)
└─────────────┘

  (Any state) → ERROR → EXITED (Exit code 1)
```

### State Descriptions

| State | Description | Entry Actions | Exit Conditions |
|-------|-------------|---------------|-----------------|
| **INITIALIZING** | Container startup, logger setup | Configure logging, detect UID/GID, log startup banner | Auto-transition to VALIDATING |
| **VALIDATING** | Pre-flight checks before starting services | Run init-squid.py, validate squid.conf via `squid -k parse`, check directory permissions, merge SSL certs if needed | Success → STARTING_HEALTH, Failure → ERROR |
| **STARTING_HEALTH** | Launch health check HTTP server | Start healthcheck.py as subprocess, wait 2s, verify PID exists via /proc | Success → STARTING_SQUID, Failure → ERROR |
| **STARTING_SQUID** | Launch Squid proxy process | Execute `squid -N -f /etc/squid/squid.conf`, wait for PID file creation | Success → RUNNING, Failure → ERROR |
| **RUNNING** | Normal operation, monitoring loop | Monitor Squid PID via /proc every 1s, handle signals (SIGTERM/SIGINT) | Squid dies → ERROR, Signal received → SHUTTING_DOWN |
| **SHUTTING_DOWN** | Graceful shutdown sequence | Send SIGTERM to Squid, cancel async tasks, wait 30s timeout, force SIGKILL if needed | Always → EXITED |
| **ERROR** | Fatal error occurred | Log error message to stderr, cleanup resources | Always → EXITED (exit code 1) |
| **EXITED** | Container termination | Exit with code 0 (clean shutdown) or 1 (error) | Terminal state |

### State Transitions

**Success Path**:
```
INITIALIZING → VALIDATING → STARTING_HEALTH → STARTING_SQUID → RUNNING → SHUTTING_DOWN → EXITED (0)
```

**Error Paths**:
```
VALIDATING → ERROR → EXITED (1)           # Config validation failed
STARTING_HEALTH → ERROR → EXITED (1)      # Health server failed to start
STARTING_SQUID → ERROR → EXITED (1)       # Squid failed to start
RUNNING → ERROR → EXITED (1)              # Squid died unexpectedly
RUNNING → SHUTTING_DOWN → EXITED (0)      # Signal received, clean shutdown
```

### Invariants

1. **Single Direction**: State machine only moves forward (no backward transitions)
2. **Error Terminates**: ERROR state always leads to EXITED with code 1
3. **Fail Fast**: Validation errors in VALIDATING immediately transition to ERROR
4. **Signal Handling**: SIGTERM/SIGINT only handled in RUNNING state
5. **Timeout Enforcement**: SHUTTING_DOWN enforces strict 30-second timeout
6. **Process Monitoring**: RUNNING state continuously monitors Squid via /proc every 1 second

## Process Lifecycle

### Squid Process Model

```python
class SquidProcess:
    """Model for Squid subprocess managed by entrypoint."""

    pid: int                    # Process ID from asyncio.subprocess
    state: str                  # 'starting', 'running', 'terminating', 'dead'
    start_time: float           # Unix timestamp of process start
    pid_file: Path              # /var/run/squid/squid.pid
    config_file: Path           # /etc/squid/squid.conf

    # Methods
    async def start() -> SquidProcess
    async def terminate(timeout: float = 30.0) -> None
    async def kill() -> None
    def is_running() -> bool    # Check /proc/<pid> existence
```

**Squid States**:

| State | Condition | Action |
|-------|-----------|--------|
| `starting` | Subprocess launched, waiting for PID file | Poll for PID file creation (max 30 iterations @ 0.1s) |
| `running` | PID file exists, /proc/<pid> exists | Monitor via /proc/<pid> every 1s |
| `terminating` | SIGTERM sent, waiting for exit | Wait up to 30s for graceful exit |
| `dead` | /proc/<pid> missing or returncode set | Log exit code, transition entrypoint to ERROR or EXITED |

### Health Check Process Model

```python
class HealthCheckProcess:
    """Model for healthcheck.py subprocess."""

    pid: int                    # Process ID from asyncio.subprocess
    port: int                   # HTTP port (default 8080)
    state: str                  # 'starting', 'running', 'stopped'
    start_time: float           # Unix timestamp of process start

    # Methods
    async def start() -> HealthCheckProcess
    async def stop() -> None
    def is_running() -> bool    # Check /proc/<pid> existence
```

**Health Check States**:

| State | Condition | Action |
|-------|-----------|--------|
| `starting` | Subprocess launched, waiting for startup | Sleep 2s, verify /proc/<pid> exists |
| `running` | /proc/<pid> exists | Passive monitoring (no active health checks) |
| `stopped` | Process terminated during shutdown | No action required |

## Configuration Model

### Squid Configuration Validation

```python
class SquidConfig:
    """Model for Squid configuration validation."""

    config_file: Path           # /etc/squid/squid.conf
    default_config: Path        # /etc/squid/squid.conf.default
    ssl_enabled: bool           # Detected via grep for 'ssl-bump' in config
    ssl_cert_dir: Path          # /etc/squid/ssl_cert
    merged_cert: Path           # /var/lib/squid/squid-ca.pem

    # Validation methods
    def exists() -> bool
    def is_readable() -> bool
    async def validate() -> ValidationResult  # Execute 'squid -k parse'
    def detect_ssl_bump() -> bool             # grep for 'ssl-bump' directive
    async def merge_ssl_certificates() -> None
```

**Validation Sequence**:

1. Check if `/etc/squid/squid.conf` exists (if not, copy from squid.conf.default)
2. Execute `squid -k parse -f /etc/squid/squid.conf`
3. Capture stdout/stderr, check return code
4. If ssl-bump detected:
   - Verify `/etc/squid/ssl_cert/tls.crt` exists
   - Verify `/etc/squid/ssl_cert/tls.key` exists
   - Merge to `/var/lib/squid/squid-ca.pem`
   - Set permissions to 600
5. Return ValidationResult (success/failure + error messages)

### Directory Structure

```python
class RuntimeDirectories:
    """Model for required runtime directories."""

    directories: List[Path] = [
        Path('/var/run/squid'),
        Path('/var/log/squid'),
        Path('/var/lib/squid'),
        Path('/var/spool/squid'),
        Path('/var/cache/squid'),
    ]

    # Validation methods
    async def validate_all() -> List[ValidationError]
    def create_if_missing(path: Path) -> None
    def check_writable(path: Path) -> bool
```

**Directory Validation**:

| Directory | Purpose | Validation | Failure Action |
|-----------|---------|------------|----------------|
| `/var/run/squid` | PID file storage | Must be writable | Exit with error |
| `/var/log/squid` | Squid logs | Must be writable | Exit with error |
| `/var/lib/squid` | SSL certs, metadata | Must be writable | Exit with error |
| `/var/spool/squid` | Cache storage | Must be writable | Exit with error |
| `/var/cache/squid` | Cache metadata | Must be writable | Exit with error |

**Permission Check**:
```python
def check_writable(path: Path) -> bool:
    """Test write permission without modifying directory."""
    try:
        test_file = path / '.write_test'
        test_file.touch()
        test_file.unlink()
        return True
    except (PermissionError, OSError):
        return False
```

## Error Taxonomy

### Exit Codes

| Exit Code | Meaning | Triggered By |
|-----------|---------|--------------|
| 0 | Clean shutdown | Graceful SIGTERM/SIGINT handling completed |
| 1 | Startup validation failed | Config validation, directory permissions, SSL cert issues |
| 1 | Subprocess start failed | Squid or health check failed to start |
| 1 | Squid died unexpectedly | Squid process exit detected during RUNNING state |
| 130 | Interrupted (SIGINT) | Ctrl+C during shutdown (Python default) |
| 143 | Terminated (SIGTERM) | Docker stop (Python default after timeout) |

### Error Categories

```python
class ErrorCategory(Enum):
    """Categorization of error types for logging and diagnostics."""

    CONFIG_VALIDATION = "Configuration validation failed"
    PERMISSION_ERROR = "Directory permission denied"
    SSL_CERT_ERROR = "SSL certificate validation failed"
    SUBPROCESS_START_ERROR = "Failed to start subprocess"
    SUBPROCESS_DIED = "Subprocess exited unexpectedly"
    SIGNAL_TIMEOUT = "Graceful shutdown timeout exceeded"
```

**Error Messages** (logged to stderr):

| Category | Example Message | Exit Code |
|----------|-----------------|-----------|
| CONFIG_VALIDATION | `ERROR: Squid configuration validation failed: [squid -k parse output]` | 1 |
| PERMISSION_ERROR | `ERROR: Directory /var/run/squid is not writable (UID: 1000, GID: 0)` | 1 |
| SSL_CERT_ERROR | `ERROR: SSL-bump enabled but TLS certificate not found: /etc/squid/ssl_cert/tls.crt` | 1 |
| SUBPROCESS_START_ERROR | `ERROR: Failed to start Squid: [exception details]` | 1 |
| SUBPROCESS_DIED | `ERROR: Squid process died with exit code 127` | 1 |
| SIGNAL_TIMEOUT | `WARN: Graceful shutdown timeout (30s) exceeded, forcing kill` | 0 (warning only) |

### Logging Format

**Log Structure** (Python logging module):

```python
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
```

**Example Logs**:
```
2026-01-01 12:00:00 [INFO] CephaloProxy entrypoint starting (UID: 1000, GID: 0)
2026-01-01 12:00:00 [INFO] Validating Squid configuration...
2026-01-01 12:00:01 [INFO] Configuration validation passed
2026-01-01 12:00:01 [INFO] Starting health check server on port 8080
2026-01-01 12:00:03 [INFO] Health check server started (PID: 45)
2026-01-01 12:00:03 [INFO] Starting Squid proxy...
2026-01-01 12:00:05 [INFO] Squid started with PID 123
2026-01-01 12:00:05 [INFO] Container ready, entering monitoring loop
2026-01-01 12:05:00 [INFO] Received signal SIGTERM, initiating graceful shutdown...
2026-01-01 12:05:00 [INFO] Sending SIGTERM to Squid (PID: 123)
2026-01-01 12:05:02 [INFO] Squid shutdown complete
2026-01-01 12:05:02 [INFO] Shutdown complete
```

## /proc Filesystem Parsing

### Process Monitoring Pattern

```python
async def monitor_process(pid: int, name: str = "Process") -> None:
    """
    Monitor process via /proc filesystem.

    Args:
        pid: Process ID to monitor
        name: Process name for logging

    Raises:
        SystemExit: When process dies (exit code 1)
    """
    while True:
        if not Path(f"/proc/{pid}").exists():
            logging.error(f"{name} (PID: {pid}) is no longer running")
            sys.exit(1)

        await asyncio.sleep(1.0)  # Check every second
```

### /proc/[pid] File Structure

**Files Used**:

| File | Purpose | Parsing Method |
|------|---------|----------------|
| `/proc/[pid]/` | Process existence check | `Path.exists()` |
| `/proc/[pid]/status` | Process state, memory (optional) | Key-value parsing |
| `/proc/[pid]/cmdline` | Command line (verification) | Read full file |

**Example /proc/[pid]/status Parsing**:

```python
def parse_proc_status(pid: int) -> Dict[str, str]:
    """Parse /proc/[pid]/status into key-value dict."""
    status_file = Path(f"/proc/{pid}/status")

    if not status_file.exists():
        return {}

    info = {}
    with open(status_file, 'r') as f:
        for line in f:
            if ':' in line:
                key, value = line.split(':', 1)
                info[key.strip()] = value.strip()

    return info
```

**Used Fields**:
- `Name`: Process name (should be "squid")
- `State`: Process state (R=running, S=sleeping, Z=zombie, T=stopped)
- `Pid`: Process ID (verification)
- `VmRSS`: Resident memory (optional diagnostics)

## Signal Handling Model

### Asyncio Signal Registration

```python
async def main():
    """Main entrypoint with signal handler registration."""
    loop = asyncio.get_running_loop()

    # Register handlers for graceful shutdown signals
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(
            sig,
            lambda s=sig: asyncio.create_task(shutdown_handler(s))
        )

    # Start Squid and monitor
    squid_process = await start_squid()
    await monitor_process(squid_process.pid, "Squid")
```

### Shutdown Sequence

**Phase 1: Signal Reception** (0-1s):
1. Log signal received
2. Send SIGTERM to Squid process
3. Cancel all async tasks

**Phase 2: Graceful Wait** (0-30s):
1. Wait for Squid to exit (`asyncio.wait_for(process.wait(), timeout=30)`)
2. Gather all async tasks with `return_exceptions=True`
3. If completed within timeout → log success

**Phase 3: Force Kill** (30s+):
1. If Squid still running after timeout → send SIGKILL
2. Wait up to 5s for final cleanup
3. Exit container

**Shutdown State Diagram**:

```text
Signal Received
     │
     ▼
Send SIGTERM to Squid
     │
     ▼
Wait (max 30s)
     │
     ├─ Squid exits → Log success
     │                     │
     │                     ▼
     │                Exit code 0
     │
     └─ Timeout → Send SIGKILL
                       │
                       ▼
                  Wait (max 5s)
                       │
                       ▼
                  Exit code 0
```

## Environment Variables

### Supported Variables

| Variable | Default | Purpose | Used In State |
|----------|---------|---------|---------------|
| `SQUID_PORT` | 3128 | Squid proxy port | VALIDATING (logging only) |
| `HEALTH_PORT` | 8080 | Health check HTTP port | STARTING_HEALTH |
| `LOG_LEVEL` | INFO | Python logging level | INITIALIZING |

**Note**: These are inherited from current bash entrypoint for compatibility. Not all are actively used in Python implementation.

## Asyncio Task Model

### Task Structure

```python
async def main():
    """Main entrypoint orchestrating all tasks."""

    # Initialization (INITIALIZING state)
    setup_logging()
    log_startup_banner()

    # Validation (VALIDATING state)
    await run_init_squid()
    await validate_config()
    await validate_directories()
    await merge_ssl_certs_if_needed()

    # Start health server (STARTING_HEALTH state)
    health_process = await start_health_server()

    # Start Squid (STARTING_SQUID state)
    squid_process = await start_squid()

    # Register signal handlers
    register_signal_handlers(squid_process)

    # Monitor (RUNNING state)
    await monitor_process(squid_process.pid, "Squid")
```

### Task Dependencies

```text
main()
  ├─ setup_logging()                    # Synchronous
  ├─ log_startup_banner()               # Synchronous
  ├─ await run_init_squid()             # Async (subprocess)
  ├─ await validate_config()            # Async (subprocess: squid -k parse)
  ├─ await validate_directories()       # Async (I/O operations)
  ├─ await merge_ssl_certs_if_needed()  # Async (file I/O)
  ├─ await start_health_server()        # Async (subprocess)
  │     └─ asyncio.create_subprocess_exec()
  ├─ await start_squid()                # Async (subprocess)
  │     └─ asyncio.create_subprocess_exec()
  ├─ register_signal_handlers()         # Synchronous
  └─ await monitor_process()            # Async (infinite loop)
        └─ asyncio.sleep(1.0)
```

## Data Model Summary

This data model defines:
- ✅ 8 entrypoint states with clear transitions
- ✅ 2 subprocess models (Squid, HealthCheck)
- ✅ Configuration validation workflow
- ✅ Directory structure and permissions
- ✅ Error taxonomy with exit codes
- ✅ /proc filesystem parsing patterns
- ✅ Signal handling and shutdown sequence
- ✅ Asyncio task orchestration

**Next**: See [contracts/entrypoint-contract.md](contracts/entrypoint-contract.md) for behavioral contracts and invariants.
