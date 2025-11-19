# Known Warnings and Their Meanings

This document explains expected warnings you may see in Squid logs when running CephaloProxy.

## Expected Warnings (Safe to Ignore)

### 1. `WARNING: no_suid: setuid(0): (1) Operation not permitted`

**Meaning**: Squid is attempting to switch to root user but cannot because the container is running as non-root (UID 1000).

**Why it happens**: Squid traditionally runs as root and drops privileges. In containers, we run as non-root from the start for security.

**Impact**: None. This is expected behavior and does not affect Squid's functionality.

**Solution**: This warning is harmless and can be ignored. It's part of running Squid in a secure, non-root container environment.

---

## Resolved Issues (Should Not Appear)

### ~~ERROR: cannot change current directory to /var/cache/squid~~

**Status**: Fixed in latest version

**Fix**: Added `/var/cache/squid` directory creation in Dockerfile with proper permissions

### ~~WARNING: log name now starts with a module name~~

**Status**: Fixed in latest version

**Fix**: Updated all configurations to use `stdio:/var/log/squid/access.log` format

### ~~FATAL: MIME Config Table /etc/squid/mime.conf: No such file or directory~~

**Status**: Fixed in latest version

**Fix**: Added COPY of `mime.conf` from builder stage

### ~~FATAL: failed to open /run/squid.pid: Permission denied~~

**Status**: Fixed in latest version

**Fix**: Created `/var/run/squid` directory and set `pid_filename /var/run/squid/squid.pid`

---

## How to Report New Issues

If you encounter warnings or errors not listed here:

1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Search existing issues: https://github.com/yourorg/cephaloproxy/issues
3. If it's a new issue, create a bug report with:
   - Full error message
   - Container logs: `docker logs <container-name>`
   - Squid version: `docker exec <container-name> squid -v`
   - Your configuration (sanitized)
