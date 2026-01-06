#!/usr/bin/env python3
"""
CephaloProxy Python Entrypoint - Distroless Migration

This entrypoint replaces entrypoint.sh to enable shell-free operation in
distroless containers. It manages Squid initialization, process monitoring,
and graceful shutdown using Python asyncio.

State Machine:
    INITIALIZING → VALIDATING → STARTING_HEALTH → STARTING_SQUID →
    RUNNING → SHUTTING_DOWN → EXITED

Architecture:
    - Asyncio-based event loop for signal handling and process management
    - /proc filesystem parsing for process monitoring (no external dependencies)
    - 30-second graceful shutdown timeout with force SIGKILL fallback
    - Fail-fast error handling (immediate exit on validation failures)

Exit Codes:
    0 - Clean shutdown after SIGTERM/SIGINT
    1 - Validation failure, subprocess start failure, or unexpected death
"""

import asyncio
import logging
import os
import signal
import sys
from pathlib import Path
from typing import Optional

# Import utility modules
from logging_config import setup_logging
from proc_utils import check_process_running
from config_validator import validate_squid_config, detect_ssl_bump
from directory_validator import validate_directories
from ssl_cert_handler import check_ssl_certificates_exist, merge_ssl_certificates


# Global process references for signal handlers
squid_process: Optional[asyncio.subprocess.Process] = None
health_process: Optional[asyncio.subprocess.Process] = None
shutdown_event: Optional[asyncio.Event] = None


async def run_init_squid() -> None:
    """
    Execute init-squid.py to initialize Squid cache directories.

    Raises:
        SystemExit: If init-squid.py fails
    """
    logging.info("Running Squid initialization...")

    try:
        process = await asyncio.create_subprocess_exec(
            '/usr/bin/python3',
            '/usr/local/bin/init-squid.py',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await process.communicate()

        # Log init-squid.py output for debugging
        if stdout:
            stdout_text = stdout.decode('utf-8').strip()
            if stdout_text:
                for line in stdout_text.split('\n'):
                    logging.info(f"init-squid: {line}")

        if stderr:
            stderr_text = stderr.decode('utf-8').strip()
            if stderr_text:
                for line in stderr_text.split('\n'):
                    logging.warning(f"init-squid: {line}")

        if process.returncode != 0:
            error_msg = stderr.decode('utf-8').strip() if stderr else "Unknown error"
            logging.error(f"init-squid.py failed with exit code {process.returncode}")
            sys.exit(1)

        logging.info("Squid initialization complete")

    except Exception as e:
        logging.error(f"Failed to run init-squid.py: {str(e)}")
        sys.exit(1)


async def validate_configuration() -> None:
    """
    Validate Squid configuration and handle SSL certificate merging.

    Raises:
        SystemExit: If validation fails
    """
    logging.info("Validating Squid configuration...")

    # Check if custom config exists, otherwise copy default
    config_file = Path('/etc/squid/squid.conf')
    default_config = Path('/etc/squid/squid.conf.default')

    if not config_file.exists() and default_config.exists():
        logging.info("Custom squid.conf not found, copying from default")
        import shutil
        shutil.copy(default_config, config_file)

    # Check if SSL-bump is enabled and merge certificates BEFORE validation
    # This is critical because squid -k parse tries to load the certificate file
    if detect_ssl_bump(config_file):
        logging.info("SSL-bump detected in configuration")

        # Verify certificates exist
        cert_exists, cert_error = check_ssl_certificates_exist()
        if not cert_exists:
            logging.error(f"SSL-bump enabled but {cert_error}")
            sys.exit(1)

        # Merge certificates BEFORE config validation
        merge_success, merge_error = await merge_ssl_certificates()
        if not merge_success:
            logging.error(f"Failed to merge SSL certificates: {merge_error}")
            sys.exit(1)

    # Validate configuration (after SSL certificates are merged)
    success, error = await validate_squid_config(config_file)
    if not success:
        logging.error(f"Squid configuration validation failed:\n{error}")
        sys.exit(1)

    logging.info("Configuration validation passed")


async def validate_runtime_directories() -> None:
    """
    Validate that all required directories exist and are writable.

    Raises:
        SystemExit: If any directory is not writable
    """
    errors = validate_directories()

    if errors:
        logging.error("Directory validation failed:")
        for path, error in errors:
            logging.error(f"  {path}: {error}")
        sys.exit(1)

    logging.info("Directory validation passed")
    # Note: No PID symlink needed - squid.conf.default explicitly sets
    # pid_filename /var/run/squid/squid.pid


async def start_health_server() -> asyncio.subprocess.Process:
    """
    Start the health check HTTP server as a background process.

    Returns:
        Process object for health server

    Raises:
        SystemExit: If health server fails to start
    """
    health_port = os.getenv('HEALTH_PORT', '8080')
    logging.info(f"Starting health check server on port {health_port}")

    try:
        process = await asyncio.create_subprocess_exec(
            '/usr/bin/python3',
            '/usr/local/bin/healthcheck.py',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        # Wait for health server to start
        await asyncio.sleep(2.0)

        # Verify process is still running
        if not check_process_running(process.pid):
            logging.error("Health check server failed to start")
            sys.exit(1)

        logging.info(f"Health check server started (PID: {process.pid})")
        return process

    except Exception as e:
        logging.error(f"Failed to start health check server: {str(e)}")
        sys.exit(1)


async def log_stream(stream, prefix):
    """Log output from a subprocess stream."""
    while True:
        line = await stream.readline()
        if not line:
            break
        decoded = line.decode('utf-8').rstrip()
        if decoded:
            logging.info(f"{prefix}: {decoded}")


async def start_squid() -> asyncio.subprocess.Process:
    """
    Start Squid proxy process in non-daemon mode.

    Returns:
        Process object for Squid

    Raises:
        SystemExit: If Squid fails to start
    """
    logging.info("Starting Squid proxy...")

    try:
        process = await asyncio.create_subprocess_exec(
            '/usr/sbin/squid',
            '-N',  # No daemon mode (foreground)
            '-f', '/etc/squid/squid.conf',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        # Start background tasks to log Squid output
        asyncio.create_task(log_stream(process.stdout, "Squid"))
        asyncio.create_task(log_stream(process.stderr, "Squid"))

        # Give logging tasks time to start
        await asyncio.sleep(0.5)

        # Wait for PID file creation
        pid_file = Path('/var/run/squid/squid.pid')
        max_attempts = 300  # 30 seconds (300 * 0.1s)

        for attempt in range(max_attempts):
            if pid_file.exists():
                break

            # Check if process already exited
            if process.returncode is not None:
                # Wait a bit for log streams to finish reading
                await asyncio.sleep(1.0)
                logging.error(f"Squid exited during startup with code {process.returncode}")

                # Print Squid log files for debugging
                logging.error("Squid cache.log contents:")
                cache_log = Path('/var/log/squid/cache.log')
                if cache_log.exists():
                    try:
                        with open(cache_log, 'r') as f:
                            for line in f:
                                logging.error(f"  {line.rstrip()}")
                    except Exception as e:
                        logging.error(f"  Could not read cache.log: {e}")
                else:
                    logging.error("  cache.log does not exist")

                sys.exit(1)

            await asyncio.sleep(0.1)
        else:
            logging.error("Squid PID file not created within 30 seconds")
            process.kill()
            sys.exit(1)

        logging.info(f"Squid started with PID {process.pid}")
        return process

    except Exception as e:
        logging.error(f"Failed to start Squid: {str(e)}")
        sys.exit(1)


async def monitor_squid(process: asyncio.subprocess.Process) -> None:
    """
    Monitor Squid process via /proc filesystem.

    Args:
        process: Squid process to monitor

    Raises:
        SystemExit: If Squid dies unexpectedly
    """
    global shutdown_event

    while True:
        # Check if shutdown was requested
        if shutdown_event and shutdown_event.is_set():
            # Graceful shutdown in progress
            return

        # Check if process is still running via /proc
        if not check_process_running(process.pid):
            # Process died, check return code
            returncode = process.returncode
            logging.error(f"Squid process died with exit code {returncode}")
            sys.exit(1)

        # Check via wait_for with timeout (non-blocking check)
        try:
            await asyncio.wait_for(process.wait(), timeout=1.0)
            # If we get here, process exited
            logging.error(f"Squid process exited with code {process.returncode}")
            sys.exit(1)
        except asyncio.TimeoutError:
            # Process still running, continue monitoring
            pass


async def shutdown_handler(sig: signal.Signals) -> None:
    """
    Handle graceful shutdown on SIGTERM/SIGINT/SIGHUP.

    Asyncio Pattern: Uses asyncio.wait_for() with 30-second timeout to enforce
    graceful shutdown deadline. If Squid doesn't exit within timeout, force
    SIGKILL ensures container terminates cleanly.

    State Transition: RUNNING → SHUTTING_DOWN → EXITED

    Args:
        sig: Signal that triggered shutdown

    Exit Code:
        0 - Clean shutdown completed
    """
    global squid_process, health_process, shutdown_event

    logging.info(f"Received signal {sig.name}, initiating graceful shutdown...")

    # Set shutdown event to stop monitoring
    if shutdown_event:
        shutdown_event.set()

    # Send SIGTERM to Squid
    if squid_process and squid_process.returncode is None:
        logging.info(f"Sending SIGTERM to Squid (PID: {squid_process.pid})")
        squid_process.terminate()

        # Wait up to 30 seconds for graceful shutdown
        try:
            await asyncio.wait_for(squid_process.wait(), timeout=30.0)
            logging.info("Squid shutdown complete")
        except asyncio.TimeoutError:
            logging.warning("Graceful shutdown timeout (30s) exceeded, forcing kill")
            squid_process.kill()
            await asyncio.wait_for(squid_process.wait(), timeout=5.0)

    # Stop health server
    if health_process and health_process.returncode is None:
        health_process.terminate()
        try:
            await asyncio.wait_for(health_process.wait(), timeout=5.0)
        except asyncio.TimeoutError:
            health_process.kill()

    logging.info("Shutdown complete")


async def main() -> None:
    """
    Main entrypoint orchestrating all initialization and monitoring.

    State Flow:
        INITIALIZING → VALIDATING → STARTING_HEALTH → STARTING_SQUID →
        RUNNING → SHUTTING_DOWN → EXITED
    """
    global squid_process, health_process, shutdown_event

    # INITIALIZING State
    setup_logging(os.getenv('LOG_LEVEL', 'INFO'))

    uid = os.getuid()
    gid = os.getgid()
    logging.info(f"CephaloProxy entrypoint starting (UID: {uid}, GID: {gid})")

    # VALIDATING State
    await validate_configuration()  # Must run BEFORE init-squid (copies default config)
    await run_init_squid()
    await validate_runtime_directories()

    # STARTING_HEALTH State
    health_process = await start_health_server()

    # STARTING_SQUID State
    squid_process = await start_squid()

    # Register signal handlers (must be done in main thread)
    # Asyncio Pattern: loop.add_signal_handler() is the recommended approach for
    # Python 3.11+ signal handling in async context. Replaces signal.signal() to
    # avoid conflicts with asyncio event loop.
    shutdown_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        loop.add_signal_handler(
            sig,
            lambda s=sig: asyncio.create_task(shutdown_handler(s))
        )

    # RUNNING State
    logging.info("Container ready, entering monitoring loop")

    # Monitor Squid process
    try:
        await monitor_squid(squid_process)
        # If we get here, shutdown completed gracefully
        logging.info("Main loop exiting")
    except asyncio.CancelledError:
        # Shutdown initiated
        logging.info("Main loop cancelled")
        pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
        # Graceful shutdown completed
        sys.exit(0)
    except KeyboardInterrupt:
        logging.info("Interrupted by user")
        sys.exit(0)
    except Exception as e:
        logging.error(f"Fatal error: {str(e)}")
        sys.exit(1)
