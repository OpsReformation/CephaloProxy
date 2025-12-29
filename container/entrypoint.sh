#!/bin/bash
# Entrypoint script for Squid Proxy Container
# Handles configuration validation, initialization, and graceful shutdown

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect current UID/GID (for OpenShift arbitrary UID support)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
log_info "Running as UID:${CURRENT_UID} GID:${CURRENT_GID}"

# Configuration paths
SQUID_CONF="/etc/squid/squid.conf"
DEFAULT_CONF="/etc/squid/squid.conf.default"
SSL_CERT_DIR="/etc/squid/ssl_cert"
CACHE_DIR="/var/spool/squid"

# Environment variables with defaults
SQUID_PORT=${SQUID_PORT:-3128}
HEALTH_PORT=${HEALTH_PORT:-8080}
CACHE_SIZE_MB=${CACHE_SIZE_MB:-250}
LOG_LEVEL=${LOG_LEVEL:-1}

# ============================================================================
# SSL-Bump Certificate Validation (if enabled)
# ============================================================================

# Check if SSL-bump is enabled in config
if grep -q "ssl-bump" "$ACTIVE_CONFIG" 2>/dev/null; then
    log_info "SSL-bump detected in configuration"

    # Kubernetes TLS secret file names
    TLS_CERT="$SSL_CERT_DIR/files/tls.crt"
    TLS_KEY="$SSL_CERT_DIR/files/tls.key"
    MERGED_CERT="$SSL_CERT_DIR/squid-ca.pem"

    # Verify TLS certificate exists
    if [ ! -f "$TLS_CERT" ]; then
        log_error "SSL-bump enabled but TLS certificate not found: $TLS_CERT"
        log_error "Please mount your Kubernetes TLS secret to $SSL_CERT_DIR/"
        exit 1
    fi

    # Verify TLS private key exists
    if [ ! -f "$TLS_KEY" ]; then
        log_error "SSL-bump enabled but TLS private key not found: $TLS_KEY"
        log_error "Please mount your Kubernetes TLS secret to $SSL_CERT_DIR/"
        exit 1
    fi

    # Merge certificate and key into squid-ca.pem
    log_info "Merging TLS certificate and key into $MERGED_CERT"
    {
        cat "$TLS_CERT"
        cat "$TLS_KEY"
    } > "$MERGED_CERT"

    # Set permissions to 600 (read/write for owner only)
    chmod 600 "$MERGED_CERT"
    log_info "Set permissions for $MERGED_CERT to 600"

    log_info "SSL certificates validated and merged"
fi

# ============================================================================
# Configuration Selection
# ============================================================================

log_info "Checking Squid configuration..."

# Use custom config if mounted, otherwise use default
if [ -f "$SQUID_CONF" ] && [ "$SQUID_CONF" != "$DEFAULT_CONF" ]; then
    log_info "Using custom configuration: $SQUID_CONF"
    ACTIVE_CONFIG="$SQUID_CONF"
else
    log_info "Using default configuration"
    cp "$DEFAULT_CONF" "$SQUID_CONF"
    ACTIVE_CONFIG="$SQUID_CONF"
fi

# ============================================================================
# Configuration Validation
# ============================================================================

log_info "Validating Squid configuration..."
if ! squid -f "$ACTIVE_CONFIG" -k parse 2>&1; then
    log_error "Configuration validation failed!"
    log_error "Please check your squid.conf syntax."
    exit 1
fi
log_info "Configuration validation passed"

# ============================================================================
# Cache Directory Initialization
# ============================================================================

log_info "Initializing Squid cache..."
/usr/local/bin/init-squid.sh

# ============================================================================
# Start Health Check Server
# ============================================================================

log_info "Starting health check server on port $HEALTH_PORT..."
/usr/local/bin/healthcheck.py &
HEALTHCHECK_PID=$!

# Give health check server time to start
sleep 2

if ! kill -0 $HEALTHCHECK_PID 2>/dev/null; then
    log_error "Health check server failed to start"
    exit 1
fi

log_info "Health check server started (PID: $HEALTHCHECK_PID)"

# ============================================================================
# Graceful Shutdown Handler
# ============================================================================

shutdown() {
    log_info "Received shutdown signal, initiating graceful shutdown..."

    # Shutdown Squid gracefully
    log_info "Shutting down Squid..."
    squid -k shutdown 2>/dev/null || true

    # Wait up to 30 seconds for Squid to finish
    for _ in {1..30}; do
        if ! pgrep -x squid >/dev/null; then
            log_info "Squid shutdown complete"
            break
        fi
        sleep 1
    done

    # Force kill if still running
    if pgrep -x squid >/dev/null; then
        log_warn "Squid did not shutdown gracefully, forcing..."
        pkill -9 squid || true
    fi

    # Shutdown health check server
    log_info "Shutting down health check server..."
    kill $HEALTHCHECK_PID 2>/dev/null || true

    log_info "Shutdown complete"
    exit 0
}

# Trap SIGTERM and SIGINT for graceful shutdown
trap shutdown SIGTERM SIGINT

# ============================================================================
# Start Squid
# ============================================================================

log_info "Starting Squid proxy..."
log_info "Proxy port: $SQUID_PORT"
log_info "Cache directory: $CACHE_DIR"
log_info "Log level: $LOG_LEVEL"

# Start Squid in foreground mode (-N) for container compatibility
exec squid -f "$ACTIVE_CONFIG" -N -d "$LOG_LEVEL"
