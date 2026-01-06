"""
/proc filesystem parsing utilities for process monitoring.

This module provides functions to check process existence and parse process
information from the /proc filesystem without external dependencies (no psutil).
"""

from pathlib import Path
from typing import Optional, Dict


def check_process_running(pid: int) -> bool:
    """
    Check if a process is running by verifying /proc/[pid] exists.

    Args:
        pid: Process ID to check

    Returns:
        True if process exists, False otherwise
    """
    return Path(f"/proc/{pid}").exists()


def parse_proc_status(pid: int) -> Optional[Dict[str, str]]:
    """
    Parse /proc/[pid]/status into a key-value dictionary.

    Args:
        pid: Process ID to parse

    Returns:
        Dictionary of status fields, or None if process doesn't exist

    Example:
        {'Name': 'squid', 'State': 'S (sleeping)', 'Pid': '123', ...}
    """
    status_file = Path(f"/proc/{pid}/status")

    if not status_file.exists():
        return None

    info = {}
    try:
        with open(status_file, 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    info[key.strip()] = value.strip()
    except (IOError, ValueError, PermissionError):
        return None

    return info
