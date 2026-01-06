"""
Python logging configuration for entrypoint script.

Provides structured logging with timestamps and log levels matching
the format used by the bash entrypoint.
"""

import logging
import sys


def setup_logging(level: str = "INFO") -> None:
    """
    Configure Python logging for entrypoint.

    Args:
        level: Log level (DEBUG, INFO, WARN, ERROR)

    Log Format:
        YYYY-MM-DD HH:MM:SS [LEVEL] Message
    """
    log_level = getattr(logging, level.upper(), logging.INFO)

    logging.basicConfig(
        level=log_level,
        format='%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        stream=sys.stdout
    )
