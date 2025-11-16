# Data Model: Squid Proxy Container

**Feature**: 001-squid-proxy-container **Date**: 2025-11-11 **Purpose**: Define
configuration file structures, volume mounts, and data entities

## Overview

This document describes the data structures, configuration files, and persistent
storage used by the Squid Proxy Container. Since this is a containerized proxy,
the "data model" consists primarily of configuration file formats and volume
mount specifications rather than traditional database entities.

## Configuration Entities

### 1. Squid Configuration File

**Location**: `/etc/squid/squid.conf` **Format**: Squid native configuration
(text-based directives) **Mutability**: Read at container startup, can be
mounted as volume **Owner**: UID 1000 / GID 0 (or arbitrary UID in OpenShift)

**Structure**:

```squid.conf
# Core proxy settings
http_port 3128
coredump_dir /var/cache/squid

# Cache configuration
cache_dir ufs /var/spool/squid 250 16 256
cache_mem 64 MB
maximum_object_size 4 MB

# Access control (example)
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
http_access allow localnet
http_access deny all

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# SSL-bump configuration (when enabled)
# http_port 3128 ssl-bump cert=/etc/squid/ssl_cert/ca.pem key=/etc/squid/ssl_cert/ca.key
# ssl_crtd_program /usr/lib64/squid/ssl_crtd -s /var/lib/squid/ssl_db -M 4MB
# acl step1 at_step SslBump1
# ssl_bump peek step1
# ssl_bump splice all
```

**Validation Rules**:

- Must pass `squid -k parse` validation before startup
- Port directives must not conflict with health check port (8080)
- Cache directories must be writable by container UID
- SSL-bump requires certificate files at `/etc/squid/ssl_cert/`

**State Transitions**: Static - read once at startup, requires container restart
to reload

### 2. ACL Configuration Files

**Location**: `/etc/squid/conf.d/*.acl` or inline in `squid.conf` **Format**:
Squid ACL syntax (one entry per line) **Mutability**: Read at container startup
**Owner**: UID 1000 / GID 0

**Structure**:

```text
# blocked-domains.acl
.facebook.com
.twitter.com
.instagram.com

# allowed-ips.acl
192.168.1.0/24
10.0.0.0/8
```

**Referenced in squid.conf**:

```squid.conf
acl blocked_domains dstdomain "/etc/squid/conf.d/blocked-domains.acl"
http_access deny blocked_domains
```

**Validation Rules**:

- Each line must be valid ACL entry (domain, IP range, or regex)
- Referenced files must exist or Squid fails to start
- Comments start with #

### 3. SSL Certificate Files

**Location**: `/etc/squid/ssl_cert/` **Format**: PEM-encoded X.509 certificates
and private keys **Mutability**: Read at container startup **Owner**: UID 1000 /
GID 0, mode 0640 for keys

**Required Files for SSL-Bump**:

- `ca.pem` - CA certificate for SSL interception
- `ca.key` - CA private key (must be readable only by Squid process)

**Structure**:

```text
/etc/squid/ssl_cert/
├── ca.pem          # CA certificate (public)
├── ca.key          # CA private key (sensitive)
└── dhparam.pem     # (optional) DH parameters for forward secrecy
```

**Validation Rules**:

- CA certificate must be valid X.509 PEM format
- Private key must match CA certificate
- Key file permissions must prevent world-readable (checked at startup)
- Missing cert/key when SSL-bump enabled → container fails to start

### 4. Cache Storage

**Location**: `/var/spool/squid/` (persistent) or `/tmp/squid-cache-UID/`
(ephemeral) **Format**: Squid UFS cache directory structure **Mutability**:
Read/write at runtime **Owner**: UID 1000 / GID 0 (or arbitrary UID),
group-writable

**Structure**:

```text
/var/spool/squid/
├── 00/
│   ├── 00/
│   ├── 01/
│   └── ...
├── 01/
├── swap.state      # Cache index
└── ...
```

**Initialization**: Created by `squid -z` on first startup if not present

**Lifecycle**:

- **Persistent mount**: Data survives container restarts
- **Ephemeral**: Created in `/tmp`, destroyed on container stop
- **Eviction**: Squid manages cache eviction based on size limits

**Validation Rules**:

- Must be writable by Squid process UID
- Size limits enforced by `cache_dir` directive (default 250MB ephemeral)
- Permissions: `chmod 750` (owner+group), `chgrp 0` for OpenShift

### 5. Log Files

**Location**: `/var/log/squid/` **Format**: Squid log formats (access.log,
cache.log) **Mutability**: Append-only at runtime **Owner**: UID 1000 / GID 0

**Files**:

- `access.log` - HTTP access logs (requests, responses, cache status)
- `cache.log` - Squid operational logs (startup, errors, warnings)

**Log Format (access.log - Squid native format)**:

```text
1699999999.999 123 192.168.1.100 TCP_HIT/200 1234 GET http://example.com/path - HIER_NONE/- text/html
```

**Fields**: timestamp, duration_ms, client_ip, result_code/status, bytes,
method, URL, ident, hierarchy_code, content_type

**Log Rotation**: Managed by container orchestrator or external log aggregation
(not handled by container internally)

## Volume Mount Specifications

### Required Mounts (Optional - defaults provided)

| Mount Path | Purpose | Default Behavior | Recommended Production |
|------------|---------|------------------|------------------------|
| `/var/spool/squid` | Persistent cache storage | 250MB ephemeral in `/tmp` | Mount host volume or PVC |
| `/etc/squid/squid.conf` | Custom configuration | Use embedded default config | Mount ConfigMap or host file |
| `/etc/squid/conf.d/` | ACL configuration files | Empty (no filtering) | Mount ConfigMap with ACLs |
| `/etc/squid/ssl_cert/` | SSL certificates for ssl-bump | Empty (ssl-bump disabled) | Mount Secret with CA cert/key |

### Mount Ownership Requirements

**Docker/Podman** (Fixed UID 1000):

```bash
chown -R 1000:1000 /host/cache/dir
chmod 750 /host/cache/dir
```

**OpenShift** (Arbitrary UID, GID 0):

```bash
chown -R 1000:0 /host/cache/dir
chmod 770 /host/cache/dir  # Group-writable for arbitrary UID
```

## Environment Variables

| Variable | Purpose | Default | Example |
|----------|---------|---------|---------|
| `SQUID_PORT` | Proxy listening port | 3128 | 8080 |
| `HEALTH_PORT` | Health check HTTP port | 8080 | 9090 |
| `CACHE_SIZE_MB` | Ephemeral cache size | 250 | 1024 |
| `LOG_LEVEL` | Squid debug level (0-9) | 1 | 2 |

## State Machine: Container Lifecycle

```text
[START]
   ↓
[Initialize]
   ├→ Check /etc/squid/squid.conf (use default if missing)
   ├→ Validate config: squid -k parse
   │   └→ [FAIL] → Log error, exit 1
   ├→ Check cache dir (/var/spool/squid or /tmp)
   ├→ Initialize cache if needed: squid -z
   ├→ Start health check server (port 8080)
   └→ [READY]
   ↓
[Running]
   ├→ Squid processes requests
   ├→ Health checks respond 200 OK
   ├→ Cache writes to disk
   └→ [Signal: SIGTERM]
       ↓
[Graceful Shutdown]
   ├→ Stop accepting new connections
   ├→ Wait for active connections (max 30s)
   └→ [EXIT]
```

## Data Validation Summary

| Entity | Validation Method | Timing | Failure Behavior |
|--------|-------------------|--------|------------------|
| squid.conf | `squid -k parse` | Startup | Exit 1, log error |
| ACL files | Squid config parser | Startup | Exit 1, missing file error |
| SSL certificates | OpenSSL PEM validation | Startup | Exit 1, invalid cert error |
| Cache directory | Writability test | Startup | Exit 1, permission error |
| Volume ownership | UID/GID check | Startup | Log warning, attempt fix |

## Example: Complete Volume Mount Setup

### Docker Compose

```yaml
version: '3.8'
services:
  squid-proxy:
    image: cephaloproxy:latest
    ports:
      - "3128:3128"
      - "8080:8080"
    volumes:
      - ./squid.conf:/etc/squid/squid.conf:ro
      - ./acls:/etc/squid/conf.d:ro
      - ./ssl-certs:/etc/squid/ssl_cert:ro
      - squid-cache:/var/spool/squid
    environment:
      - CACHE_SIZE_MB=500

volumes:
  squid-cache:
```

### Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: squid-proxy
spec:
  containers:
  - name: squid
    image: cephaloproxy:latest
    ports:
    - containerPort: 3128
    - containerPort: 8080
    volumeMounts:
    - name: config
      mountPath: /etc/squid/squid.conf
      subPath: squid.conf
    - name: cache
      mountPath: /var/spool/squid
  volumes:
  - name: config
    configMap:
      name: squid-config
  - name: cache
    persistentVolumeClaim:
      claimName: squid-cache-pvc
```

## Notes

- All file paths use standard Squid conventions to maintain compatibility with
  existing documentation and tools
- OpenShift arbitrary UID support requires group-writable permissions (GID 0)
- Cache directory structure created automatically by `squid -z` initialization
- Log files not rotated internally - rely on container orchestrator or external
  log aggregation
