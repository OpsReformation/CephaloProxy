#!/usr/bin/env python3
"""
Health Check HTTP Server for Squid Proxy Container
Provides /health (liveness) and /ready (readiness) endpoints for orchestrators
"""

import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import sys

# Configuration
HEALTH_PORT = int(os.getenv('HEALTH_PORT', '8080'))
CACHE_DIR = os.getenv('CACHE_DIR', '/var/spool/squid')
CONFIG_FILE = '/etc/squid/squid.conf'
PID_FILE = Path('/var/run/squid/squid.pid')


def is_squid_running() -> bool:
    """
    Check if Squid is running by checking PID file and /proc filesystem.

    Returns:
        True if Squid process is running, False otherwise
    """
    try:
        # Check if PID file exists
        if not PID_FILE.exists():
            return False

        # Read PID from file
        pid = int(PID_FILE.read_text().strip())

        # Check if process exists in /proc
        proc_dir = Path(f'/proc/{pid}')
        if not proc_dir.exists():
            return False

        # Verify it's actually squid by checking cmdline
        cmdline_file = proc_dir / 'cmdline'
        if cmdline_file.exists():
            cmdline = cmdline_file.read_text()
            # cmdline has null-separated arguments
            if 'squid' in cmdline:
                return True

        return False

    except (ValueError, FileNotFoundError, PermissionError):
        return False


class HealthCheckHandler(BaseHTTPRequestHandler):
    """HTTP request handler for health check endpoints"""

    # Suppress default logging to reduce noise
    def log_message(self, format, *args):
        """Override to reduce logging verbosity"""
        pass

    def do_GET(self):
        """Handle GET requests for /health and /ready endpoints"""

        if self.path == '/health':
            self.handle_health()
        elif self.path == '/ready':
            self.handle_ready()
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'404 Not Found\n')
            self.wfile.write(b'Available endpoints: /health, /ready\n')

    def handle_health(self):
        """
        Liveness probe: Is Squid process running?
        Returns 200 OK if Squid is alive, 503 Service Unavailable otherwise
        """
        try:
            # Check if Squid process is running via /proc filesystem
            if is_squid_running():
                # Squid is running
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK\n')
            else:
                # Squid is not running
                self.send_response(503)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Service Unavailable: Squid not running\n')

        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(f'Internal Server Error: {str(e)}\n'.encode())

    def handle_ready(self):
        """
        Readiness probe: Is Squid ready to accept traffic?
        Checks:
        - Squid process is running
        - Cache directory is writable
        - Configuration file is readable
        Returns 200 OK if ready, 503 Service Unavailable otherwise
        """
        errors = []

        try:
            # Check 1: Squid process running via /proc filesystem
            if not is_squid_running():
                errors.append('Squid process not running')

            # Check 2: Cache directory writable
            # Check both persistent and ephemeral cache locations
            cache_dirs = [CACHE_DIR]
            current_uid = os.getuid()
            ephemeral_cache = f'/tmp/squid-cache-{current_uid}'
            if os.path.exists(ephemeral_cache):
                cache_dirs.append(ephemeral_cache)

            cache_ok = False
            for cache_dir in cache_dirs:
                if os.path.isdir(cache_dir) and os.access(cache_dir, os.W_OK):
                    cache_ok = True
                    break

            if not cache_ok:
                errors.append('Cache directory not writable')

            # Check 3: Configuration file readable
            if not os.path.isfile(CONFIG_FILE):
                errors.append('Configuration file not found')
            elif not os.access(CONFIG_FILE, os.R_OK):
                errors.append('Configuration file not readable')

            # Return status based on checks
            if not errors:
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'READY\n')
            else:
                self.send_response(503)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Service Unavailable:\n')
                for error in errors:
                    self.wfile.write(f'  - {error}\n'.encode())

        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(f'Internal Server Error: {str(e)}\n'.encode())


def main():
    """Start the health check HTTP server"""
    try:
        server = HTTPServer(('', HEALTH_PORT), HealthCheckHandler)
        print(f'Health check server listening on port {HEALTH_PORT}', flush=True)
        print(f'Endpoints: /health (liveness), /ready (readiness)', flush=True)
        server.serve_forever()
    except KeyboardInterrupt:
        print('Health check server shutting down', flush=True)
        sys.exit(0)
    except Exception as e:
        print(f'ERROR: Failed to start health check server: {e}', file=sys.stderr, flush=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
