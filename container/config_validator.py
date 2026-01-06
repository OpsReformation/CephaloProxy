"""
Squid configuration validation module.

Validates Squid configuration files by executing 'squid -k parse'
and capturing output/errors.
"""

import asyncio
import logging
from pathlib import Path
from typing import Tuple


async def validate_squid_config(config_file: Path = Path("/etc/squid/squid.conf")) -> Tuple[bool, str]:
    """
    Validate Squid configuration using 'squid -k parse'.

    Args:
        config_file: Path to squid.conf file

    Returns:
        Tuple of (success: bool, error_message: str)

    Example:
        success, error = await validate_squid_config()
        if not success:
            logging.error(f"Configuration validation failed: {error}")
            sys.exit(1)
    """
    if not config_file.exists():
        return False, f"Configuration file not found: {config_file}"

    try:
        process = await asyncio.create_subprocess_exec(
            '/usr/sbin/squid',
            '-k', 'parse',
            '-f', str(config_file),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await process.communicate()

        if process.returncode == 0:
            return True, ""
        else:
            # Combine stdout and stderr for error message
            error_output = stderr.decode('utf-8').strip()
            if not error_output:
                error_output = stdout.decode('utf-8').strip()
            return False, error_output

    except FileNotFoundError:
        return False, "squid binary not found at /usr/sbin/squid"
    except Exception as e:
        return False, f"Unexpected error during validation: {str(e)}"


def detect_ssl_bump(config_file: Path = Path("/etc/squid/squid.conf")) -> bool:
    """
    Detect if ssl-bump is enabled in Squid configuration.

    Args:
        config_file: Path to squid.conf file

    Returns:
        True if ssl-bump directive found, False otherwise
    """
    if not config_file.exists():
        return False

    try:
        with open(config_file, 'r') as f:
            for line in f:
                # Strip comments and whitespace
                line = line.split('#')[0].strip()
                if 'ssl-bump' in line or 'ssl_bump' in line:
                    return True
    except (IOError, PermissionError):
        logging.warning(f"Could not read {config_file} to detect ssl-bump")

    return False
