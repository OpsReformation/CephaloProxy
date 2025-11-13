#!/bin/bash
# Squid initialization script
# Sets up cache directories, permissions, and SSL database

set -e

# Configuration
CACHE_DIR="/var/spool/squid"
CACHE_SIZE_MB=${CACHE_SIZE_MB:-250}
SSL_DB_DIR="/var/lib/squid/ssl_db"
CURRENT_UID=$(id -u)

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# ============================================================================
# Cache Directory Setup
# ============================================================================

# Check if cache directory is writable
if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
    log_info "Using persistent cache: $CACHE_DIR"
    USING_PERSISTENT=true
else
    # Fallback to ephemeral cache in /tmp
    log_warn "Cache directory $CACHE_DIR is not writable, using ephemeral cache"
    CACHE_DIR="/tmp/squid-cache-${CURRENT_UID}"
    mkdir -p "$CACHE_DIR"
    chmod 750 "$CACHE_DIR"
    log_info "Created ephemeral cache: $CACHE_DIR (${CACHE_SIZE_MB}MB)"
    USING_PERSISTENT=false
fi

# Initialize cache if not already initialized
if [ ! -d "$CACHE_DIR/00" ]; then
    log_info "Initializing Squid cache directories..."

    # Create cache structure
    squid -z -f /etc/squid/squid.conf 2>&1 | grep -v "WARNING" || true

    log_info "Cache initialization complete"
else
    log_info "Cache already initialized"
fi

# ============================================================================
# SSL Database Initialization (for SSL-bump)
# ============================================================================

# Check if SSL-bump is enabled by looking for ssl_crtd configuration
if [ -f /etc/squid/squid.conf ] && grep -q "ssl_crtd" /etc/squid/squid.conf; then
    log_info "SSL-bump support detected, initializing SSL certificate database..."

    # Create SSL DB directory if it doesn't exist
    mkdir -p "$SSL_DB_DIR"
    chmod 750 "$SSL_DB_DIR"

    # Initialize SSL database if not already done
    if [ ! -d "$SSL_DB_DIR/certs" ]; then
        log_info "Creating SSL certificate database..."
        /usr/lib64/squid/ssl_crtd -c -s "$SSL_DB_DIR" 2>&1 || {
            log_error "Failed to initialize SSL certificate database"
            exit 1
        }
        log_info "SSL certificate database created"
    else
        log_info "SSL certificate database already exists"
    fi
fi

# ============================================================================
# Permissions Check
# ============================================================================

# Verify cache directory is writable
if [ ! -w "$CACHE_DIR" ]; then
    log_error "Cache directory $CACHE_DIR is not writable by UID $CURRENT_UID"
    exit 1
fi

# Verify log directory is writable
if [ ! -w "/var/log/squid" ]; then
    log_warn "Log directory /var/log/squid is not writable, logs may fail"
fi

log_info "Initialization complete"
exit 0
