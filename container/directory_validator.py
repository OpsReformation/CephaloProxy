"""
Directory permission validation module.

Validates that required runtime directories exist and are writable
by the current user (supports OpenShift arbitrary UIDs).
"""

import logging
import os
from pathlib import Path
from typing import List, Tuple


REQUIRED_DIRECTORIES = [
    Path('/var/run/squid'),
    Path('/var/log/squid'),
    Path('/var/lib/squid'),
    Path('/var/spool/squid'),
    Path('/var/cache/squid'),
]


def check_directory_writable(directory: Path) -> bool:
    """
    Test if directory is writable without modifying it.

    Args:
        directory: Directory path to check

    Returns:
        True if writable, False otherwise
    """
    if not directory.exists():
        return False

    try:
        test_file = directory / '.write_test'
        test_file.touch()
        test_file.unlink()
        return True
    except (PermissionError, OSError):
        return False


def validate_directories() -> List[Tuple[Path, str]]:
    """
    Validate all required directories are writable.

    Returns:
        List of (path, error_message) tuples for failed validations.
        Empty list if all directories are writable.

    Example:
        errors = validate_directories()
        if errors:
            for path, error in errors:
                logging.error(f"Directory {path} is not writable: {error}")
            sys.exit(1)
    """
    errors = []
    uid = os.getuid()
    gid = os.getgid()

    for directory in REQUIRED_DIRECTORIES:
        if not directory.exists():
            errors.append((directory, f"Directory does not exist (UID: {uid}, GID: {gid})"))
            continue

        if not check_directory_writable(directory):
            errors.append((directory, f"Directory is not writable (UID: {uid}, GID: {gid})"))

    return errors
