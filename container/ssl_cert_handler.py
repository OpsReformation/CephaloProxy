"""
SSL certificate detection and merging module.

Handles SSL-bump certificate setup by merging tls.crt and tls.key
into squid-ca.pem with correct permissions.
"""

import logging
import os
from pathlib import Path
from typing import Tuple


SSL_CERT_DIR = Path('/etc/squid/ssl_cert')
TLS_CERT_FILE = SSL_CERT_DIR / 'tls.crt'
TLS_KEY_FILE = SSL_CERT_DIR / 'tls.key'
MERGED_CERT_FILE = Path('/var/lib/squid/squid-ca.pem')


def check_ssl_certificates_exist() -> Tuple[bool, str]:
    """
    Check if SSL certificate files exist.

    Returns:
        Tuple of (success: bool, error_message: str)
    """
    if not TLS_CERT_FILE.exists():
        return False, f"TLS certificate not found: {TLS_CERT_FILE}"

    if not TLS_KEY_FILE.exists():
        return False, f"TLS private key not found: {TLS_KEY_FILE}"

    return True, ""


async def merge_ssl_certificates() -> Tuple[bool, str]:
    """
    Merge tls.crt and tls.key into squid-ca.pem.

    Returns:
        Tuple of (success: bool, error_message: str)

    Example:
        success, error = await merge_ssl_certificates()
        if not success:
            logging.error(f"SSL certificate merge failed: {error}")
            sys.exit(1)
    """
    # Check if certificates exist
    exists, error = check_ssl_certificates_exist()
    if not exists:
        return False, error

    try:
        # Read certificate and key
        with open(TLS_CERT_FILE, 'r') as cert_file:
            cert_content = cert_file.read()

        with open(TLS_KEY_FILE, 'r') as key_file:
            key_content = key_file.read()

        # Write merged file (cert + key)
        with open(MERGED_CERT_FILE, 'w') as merged_file:
            merged_file.write(cert_content)
            if not cert_content.endswith('\n'):
                merged_file.write('\n')
            merged_file.write(key_content)

        # Set permissions to 600 (owner read/write only)
        os.chmod(MERGED_CERT_FILE, 0o600)

        logging.info(f"SSL certificates merged successfully: {MERGED_CERT_FILE}")
        return True, ""

    except (IOError, PermissionError) as e:
        return False, f"Failed to merge certificates: {str(e)}"
