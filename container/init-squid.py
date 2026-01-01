#!/usr/bin/env python3
"""
Squid initialization script for distroless container.
Handles cache directories, SSL database, and permissions validation.

Requirements:
- Parse squid.conf to detect cache_dir and SSL-bump configuration
- Validate required volumes are mounted and writable
- Use Python logging module (INFO level, plain text with timestamps)
- Fail immediately with clear error messages if required volumes missing
"""

import logging
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Tuple


# Configure logging (FR-007: INFO level, plain text, timestamps to stdout/stderr)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)


# Configuration constants
SQUID_CONF = Path("/etc/squid/squid.conf")
DEFAULT_CACHE_DIR = Path("/var/spool/squid")
DEFAULT_SSL_DB_DIR = Path("/var/lib/squid/ssl_db")
LOG_DIR = Path("/var/log/squid")
CURRENT_UID = os.getuid()


def parse_cache_dir_from_config() -> Optional[Path]:
    """
    Parse squid.conf to find cache_dir directive.

    Returns:
        Path to cache directory if cache_dir directive found, None otherwise.

    Format: cache_dir <type> <directory> <mbytes> <L1> <L2>
    Example: cache_dir ufs /var/spool/squid 1000 16 256
    """
    if not SQUID_CONF.exists():
        logger.warning(f"Squid configuration not found: {SQUID_CONF}")
        return None

    try:
        with open(SQUID_CONF, 'r') as f:
            for line in f:
                # Ignore comments and whitespace
                stripped = line.strip()
                if stripped.startswith('#') or not stripped:
                    continue

                # Match cache_dir directive
                match = re.match(r'^cache_dir\s+\S+\s+(\S+)', stripped)
                if match:
                    cache_path = Path(match.group(1))
                    logger.info(f"Found cache_dir directive: {cache_path}")
                    return cache_path
    except Exception as e:
        logger.error(f"Failed to parse {SQUID_CONF}: {e}")
        sys.exit(1)

    return None


def check_ssl_bump_enabled() -> bool:
    """
    Check if SSL-bump is enabled in squid.conf.

    Returns:
        True if sslcrtd_program or ssl_crtd directive found, False otherwise.
    """
    if not SQUID_CONF.exists():
        return False

    try:
        with open(SQUID_CONF, 'r') as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('#') or not stripped:
                    continue

                # Check for SSL-bump related directives
                if re.match(r'^(sslcrtd_program|ssl_crtd)', stripped):
                    logger.info("SSL-bump support detected in configuration")
                    return True
    except Exception as e:
        logger.error(f"Failed to parse {SQUID_CONF}: {e}")
        sys.exit(1)

    return False


def get_cache_size_from_config() -> Optional[int]:
    """
    Extract configured cache size (in MB) from squid.conf.

    Returns:
        Cache size in MB if found, None otherwise.
    """
    if not SQUID_CONF.exists():
        return None

    try:
        with open(SQUID_CONF, 'r') as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('#') or not stripped:
                    continue

                # Match cache_dir directive: cache_dir <type> <directory> <mbytes> <L1> <L2>
                match = re.match(r'^cache_dir\s+\S+\s+\S+\s+(\d+)', stripped)
                if match:
                    cache_mb = int(match.group(1))
                    logger.debug(f"Configured cache size: {cache_mb} MB")
                    return cache_mb
    except Exception as e:
        logger.error(f"Failed to parse cache size from {SQUID_CONF}: {e}")

    return None


def validate_volume_writable(path: Path, volume_name: str, required: bool = True) -> bool:
    """
    Validate that a volume path exists and is writable.

    Args:
        path: Path to validate
        volume_name: Human-readable name for error messages
        required: If True, fail immediately if not writable. If False, warn only.

    Returns:
        True if writable, False otherwise.

    Raises:
        SystemExit: If required=True and path is not writable (FR-005).
    """
    if not path.exists():
        message = f"Required volume not mounted: {path}"
        if required:
            logger.error(message)
            if volume_name == "Cache":
                logger.error(f"cache_dir directive found in squid.conf but volume not mounted")
                logger.error(f"Please mount a volume to {path} or remove cache_dir from config for pure proxy mode")
            else:
                logger.error(f"Please mount the {volume_name} volume to {path}")
            sys.exit(1)
        else:
            logger.warning(message)
            return False

    if not os.access(path, os.W_OK):
        message = f"{volume_name} directory not writable: {path} (UID {CURRENT_UID})"
        if required:
            logger.error(message)
            if volume_name == "Cache":
                logger.error(f"cache_dir directive found in squid.conf but volume not writable")
                logger.error(f"Fix volume permissions or remove cache_dir from config for pure proxy mode")
            else:
                logger.error(f"Permission denied for {volume_name} volume")
                logger.error(f"Check volume permissions and ensure GID 0 compatibility")
            sys.exit(1)
        else:
            logger.warning(message)
            return False

    logger.info(f"{volume_name} volume validated: {path}")
    return True


def initialize_cache_directory(cache_dir: Path) -> None:
    """
    Initialize Squid cache directory structure using 'squid -z'.

    Args:
        cache_dir: Path to cache directory

    Raises:
        SystemExit: If cache initialization fails.
    """
    # Check if cache already initialized (contains subdirectories 00-FF)
    if (cache_dir / "00").exists():
        logger.info("Cache already initialized")
        return

    logger.info("Initializing Squid cache directories...")

    try:
        # Run squid -z to create cache structure
        result = subprocess.run(
            ["squid", "-z", "-f", str(SQUID_CONF)],
            capture_output=True,
            text=True,
            check=False
        )

        # Filter out warnings (squid -z is verbose)
        if result.returncode != 0:
            logger.error(f"Cache initialization failed (exit code {result.returncode})")
            logger.error(f"stdout: {result.stdout}")
            logger.error(f"stderr: {result.stderr}")
            sys.exit(1)

        logger.info("Cache initialization complete")

    except FileNotFoundError:
        logger.error("squid binary not found - cannot initialize cache")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to initialize cache: {e}")
        sys.exit(1)


def initialize_ssl_database(ssl_db_dir: Path) -> None:
    """
    Initialize SSL certificate database for SSL-bump support.

    Uses security_file_certgen (Squid 6.x) to create certificate database.

    Args:
        ssl_db_dir: Path to SSL database directory

    Raises:
        SystemExit: If SSL database initialization fails.
    """
    # Check if SSL database already initialized
    certs_dir = ssl_db_dir / "certs"
    if certs_dir.exists():
        logger.info("SSL certificate database already exists")
        return

    logger.info("Creating SSL certificate database...")

    # Remove SSL_DB_DIR if it exists but is empty/broken
    if ssl_db_dir.exists():
        try:
            # Try to remove if empty
            ssl_db_dir.rmdir()
        except OSError:
            # Directory not empty - remove forcefully
            shutil.rmtree(ssl_db_dir)

    try:
        # Run security_file_certgen to create database
        # -c: create database
        # -s: database location
        # -M: memory cache size

        # Try both Gentoo/RHEL path (/usr/libexec/squid) and Debian path (/usr/lib/squid)
        certgen_candidates = [
            Path("/usr/lib/squid/security_file_certgen"),      # Debian/Ubuntu
            Path("/usr/libexec/squid/security_file_certgen"),  # Gentoo/RHEL/CentOS
        ]

        certgen_path = None
        for candidate in certgen_candidates:
            if candidate.exists():
                certgen_path = candidate
                logger.info(f"Found security_file_certgen at {certgen_path}")
                break

        if not certgen_path:
            logger.error(f"security_file_certgen not found in: {[str(c) for c in certgen_candidates]}")
            logger.error("SSL-bump support not available")
            sys.exit(1)

        result = subprocess.run(
            [
                str(certgen_path),
                "-c",
                "-s", str(ssl_db_dir),
                "-M", "4MB"
            ],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0:
            logger.error(f"SSL database initialization failed (exit code {result.returncode})")
            logger.error(f"stdout: {result.stdout}")
            logger.error(f"stderr: {result.stderr}")
            logger.error(f"Current UID: {CURRENT_UID}, /var/lib/squid permissions:")

            # Show permissions for debugging
            parent_dir = ssl_db_dir.parent
            if parent_dir.exists():
                stat_info = parent_dir.stat()
                logger.error(f"  {parent_dir}: mode={oct(stat_info.st_mode)}, uid={stat_info.st_uid}, gid={stat_info.st_gid}")

            sys.exit(1)

        # Set group-writable permissions for OpenShift arbitrary UID (GID 0)
        if ssl_db_dir.exists():
            try:
                for root, dirs, files in os.walk(ssl_db_dir):
                    for d in dirs:
                        dir_path = Path(root) / d
                        dir_path.chmod(dir_path.stat().st_mode | 0o070)  # Add group rwx
                    for f in files:
                        file_path = Path(root) / f
                        file_path.chmod(file_path.stat().st_mode | 0o060)  # Add group rw

                logger.info("Set group-writable permissions on SSL database")
            except Exception as e:
                logger.warning(f"Failed to set group permissions: {e}")

        logger.info("SSL certificate database created successfully")

    except FileNotFoundError:
        logger.error("security_file_certgen not found - cannot initialize SSL database")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to initialize SSL database: {e}")
        sys.exit(1)


def validate_cache_size(cache_dir: Path) -> None:
    """
    Validate that configured cache size fits within available disk space.

    Warns if:
    - Configured size > usable space (may fill disk)
    - Configured size < 60% of usable space (underutilization)

    Args:
        cache_dir: Path to cache directory
    """
    configured_mb = get_cache_size_from_config()
    if not configured_mb:
        logger.debug("No cache_dir size configured, skipping validation")
        return

    try:
        # Get filesystem stats
        stat = shutil.disk_usage(cache_dir)
        total_mb = stat.total // (1024 * 1024)

        # Calculate overhead: 10% of total (per Squid recommendations), cap at 5GB
        overhead_mb = min(total_mb * 10 // 100, 5120)
        usable_mb = total_mb - overhead_mb

        if configured_mb > usable_mb:
            logger.warning("Cache size mismatch detected:")
            logger.warning(f"  Configured cache size: {configured_mb} MB")
            logger.warning(f"  PVC size: {total_mb} MB total, {usable_mb} MB usable ({overhead_mb} MB overhead)")
            logger.warning(f"  Squid may fill the disk - consider increasing PVC or reducing cache_dir")
        elif configured_mb < (usable_mb * 60 // 100):
            logger.warning("Cache underutilization detected:")
            logger.warning(f"  Configured cache size: {configured_mb} MB")
            logger.warning(f"  PVC size: {total_mb} MB total, {usable_mb} MB usable ({overhead_mb} MB overhead)")
            logger.warning(f"  Consider increasing cache_dir to ~{usable_mb} MB for better cache hit rate")
        else:
            logger.info(f"Cache size validation: {configured_mb} MB configured, {usable_mb} MB usable ({overhead_mb} MB overhead)")

    except Exception as e:
        logger.warning(f"Failed to validate cache size: {e}")


def main() -> int:
    """
    Main initialization logic.

    Returns:
        0 on success, 1 on failure.
    """
    logger.info(f"Starting Squid initialization (UID {CURRENT_UID})")

    # ============================================================================
    # Cache Directory Setup (FR-005: Parse squid.conf to determine required volumes)
    # ============================================================================

    cache_dir = parse_cache_dir_from_config()

    if cache_dir:
        # cache_dir directive found - volume MUST be writable (FR-005: fail if missing)
        # User explicitly configured caching, so we must honor that intent
        validate_volume_writable(cache_dir, "Cache", required=True)
        logger.info(f"Using persistent cache: {cache_dir}")
        initialize_cache_directory(cache_dir)
        validate_cache_size(cache_dir)
    else:
        # No cache_dir directive - pure proxy mode, skip cache initialization entirely
        logger.info("No cache_dir directive found - running in pure proxy mode (no caching)")

    # ============================================================================
    # SSL Database Initialization (FR-005: Detect SSL-bump from config)
    # ============================================================================

    if check_ssl_bump_enabled():
        # Ensure parent directory exists and is writable
        ssl_db_parent = DEFAULT_SSL_DB_DIR.parent
        validate_volume_writable(ssl_db_parent, "SSL database parent", required=True)
        initialize_ssl_database(DEFAULT_SSL_DB_DIR)

    # ============================================================================
    # Log Directory Validation (FR-005: Permissions check)
    # ============================================================================

    validate_volume_writable(LOG_DIR, "Log", required=False)

    logger.info("Initialization complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
