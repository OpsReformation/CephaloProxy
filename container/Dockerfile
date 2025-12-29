# check=skip=InvalidBaseImagePlatform
# Multi-stage Dockerfile for Squid Proxy with SSL-bump support
# Base: Gentoo Linux (required for compiling Squid with ssl_crtd)

# =============================================================================
# Stage 0: Portage
# =============================================================================
FROM gentoo/portage:latest AS portage

# =============================================================================
# Stage 1: Builder - Compile Squid with SSL-bump support and Python
# =============================================================================
FROM gentoo/stage3:20251229 AS builder

# Set shell options for safer scripting
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy Portage repository
COPY --from=portage /var/db/repos/gentoo /var/db/repos/gentoo

# Configure Portage for Squid with SSL-bump support
RUN mkdir -p /etc/portage/package.use && \
    echo "net-proxy/squid ssl ssl-crtd" > /etc/portage/package.use/squid && \
    echo "dev-libs/openssl" >> /etc/portage/package.use/squid

# Pin Squid to version 6.x for stability
RUN mkdir -p /etc/portage/package.accept_keywords && \
    echo "=net-proxy/squid-6* ~amd64" > /etc/portage/package.accept_keywords/squid

# Update Portage and install dependencies
RUN emerge --oneshot --quiet-build dev-libs/openssl

# Install Squid with SSL-bump support
RUN emerge --quiet-build net-proxy/squid && \
    # Verify SSL-bump support compiled
    squid -v | grep -i ssl

# Install Python for health check server and cleanup in same layer
RUN emerge --oneshot --quiet-build dev-lang/python:3.11 && \
    rm -rf /var/db/repos/gentoo /var/cache/distfiles/* /var/cache/binpkgs/* /tmp/* /var/tmp/*

# =============================================================================
# Stage 2: Runtime - Minimal runtime image
# =============================================================================
FROM gentoo/stage3:20251229

# Copy Squid binaries and libraries from builder
COPY --from=builder /usr/sbin/squid /usr/sbin/squid
COPY --from=builder /usr/libexec/squid /usr/libexec/squid
COPY --from=builder /usr/share/squid /usr/share/squid

# Copy Squid configuration files (mime.conf, etc.)
COPY --from=builder /etc/squid/mime.conf /etc/squid/mime.conf.system
COPY --from=builder /etc/squid/errorpage.css /etc/squid/errorpage.css

# Copy Python from builder
COPY --from=builder /usr/bin/python3.11 /usr/bin/python3.11
COPY --from=builder /usr/lib/python3.11 /usr/lib/python3.11

# Create python3 symlink
RUN ln -sf /usr/bin/python3.11 /usr/bin/python3

# Copy required shared libraries (OpenSSL, Python, and dependencies)
COPY --from=builder /usr/lib64/libssl.so* /usr/lib64/
COPY --from=builder /usr/lib64/libcrypto.so* /usr/lib64/
COPY --from=builder /usr/lib64/libltdl.so* /usr/lib64/
COPY --from=builder /usr/lib64/libpython3.11.so* /usr/lib64/

# Note: /usr/lib64/squid and /usr/lib64/python3.11 directories are not needed
# - Squid helpers are in /usr/libexec/squid
# - Python standard library is in /usr/lib/python3.11
# - Python shared library (libpython3.11.so) is copied above

# Create Squid directories with correct ownership
# UID 1000 for Docker/Podman, GID 0 for OpenShift arbitrary UID support
# Note: /var/lib/squid/ssl_db is created by security_file_certgen, not pre-created here
RUN mkdir -p \
    /var/spool/squid \
    /var/log/squid \
    /var/lib/squid \
    /var/run/squid \
    /var/cache/squid \
    /etc/squid/conf.d \
    /etc/squid/ssl_cert/files \
    /tmp && \
    # Create squid user and group
    groupadd -g 1000 squid || true && \
    useradd -u 1000 -g 1000 -s /bin/bash -m squid || true && \
    # Link system mime.conf to expected location
    ln -sf /etc/squid/mime.conf.system /etc/squid/mime.conf && \
    # Set ownership and permissions for OpenShift compatibility
    chown -R 1000:0 \
        /var/spool/squid \
        /var/log/squid \
        /var/lib/squid \
        /var/run/squid \
        /var/cache/squid \
        /etc/squid \
        /tmp && \
    # Group-writable for OpenShift arbitrary UID
    chmod -R g=u \
        /var/spool/squid \
        /var/log/squid \
        /var/lib/squid \
        /var/run/squid \
        /var/cache/squid \
        /etc/squid \
        /tmp && \
    chmod 770 /var/spool/squid /var/log/squid /var/lib/squid /var/run/squid /var/cache/squid

# Copy container scripts
COPY container/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY container/init-squid.sh /usr/local/bin/init-squid.sh
COPY container/healthcheck.py /usr/local/bin/healthcheck.py
COPY container/squid.conf.default /etc/squid/squid.conf.default

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/init-squid.sh \
             /usr/local/bin/healthcheck.py

# Set user to UID 1000 (overridden by OpenShift with arbitrary UID)
USER 1000

# Expose ports
EXPOSE 3128 8080

# Health check using healthcheck.py
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
