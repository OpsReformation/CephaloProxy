# Configuration Reference: CephaloProxy

Complete reference for all configuration options, environment variables, and Squid directives.

## Table of Contents

- [Environment Variables](#environment-variables)
- [Volume Mounts](#volume-mounts)
- [Squid Configuration Directives](#squid-configuration-directives)
- [SSL-Bump Configuration](#ssl-bump-configuration)
- [ACL Configuration](#acl-configuration)
- [Advanced Features](#advanced-features)

---

## Environment Variables

Configure container behavior via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SQUID_PORT` | `3128` | Proxy listening port |
| `HEALTH_PORT` | `8080` | Health check HTTP server port |
| `CACHE_SIZE_MB` | `250` | Ephemeral cache size in MB (used when no persistent cache mounted) |
| `LOG_LEVEL` | `1` | Squid debug level (0=critical, 1=important, 2=verbose, 9=all) |

### Example

```bash
docker run -d \
  -e SQUID_PORT=3128 \
  -e HEALTH_PORT=8080 \
  -e CACHE_SIZE_MB=500 \
  -e LOG_LEVEL=2 \
  cephaloproxy:latest
```

---

## Volume Mounts

### Required Mounts (Optional - defaults provided)

| Path | Purpose | Default Behavior | Recommended for Production |
|------|---------|------------------|---------------------------|
| `/etc/squid/squid.conf` | Main Squid configuration | Use embedded default | Mount custom config |
| `/etc/squid/conf.d/` | ACL files directory | Empty (no filtering) | Mount ACL files |
| `/etc/squid/ssl_cert/` | TLS secret (tls.crt, tls.key) | Empty (ssl-bump disabled) | Mount TLS secret for SSL-bump |
| `/var/spool/squid` | Persistent cache storage | 250MB ephemeral in `/tmp` | Mount volume for persistence |
| `/var/log/squid` | Squid logs | Ephemeral logs | Mount volume for log persistence |

### Mount Permissions

**Docker/Podman** (Fixed UID 1000):
```bash
chown -R 1000:1000 /host/mount/path
chmod 750 /host/mount/path
```

**OpenShift** (Arbitrary UID, GID 0):
```bash
chown -R 1000:0 /host/mount/path
chmod 770 /host/mount/path  # Group-writable
```

---

## Squid Configuration Directives

### Essential Directives

#### Network Configuration

```squid.conf
# Proxy port
http_port 3128

# Alternative: HTTPS port with SSL-bump
http_port 3128 ssl-bump \
  cert=/etc/squid/ssl_cert/ca.pem \
  key=/etc/squid/ssl_cert/ca.key
```

#### Cache Configuration

```squid.conf
# Cache directory: size (MB), L1 dirs, L2 dirs
cache_dir ufs /var/spool/squid 1000 16 256

# Memory cache
cache_mem 128 MB

# Object size limits
maximum_object_size 10 MB
minimum_object_size 0 KB

# Cache replacement policy
cache_replacement_policy heap LFUDA
memory_replacement_policy heap GDSF
```

#### Access Control

```squid.conf
# Define ACLs
acl localnet src 10.0.0.0/8
acl SSL_ports port 443
acl Safe_ports port 80 443

# Access rules (order matters!)
http_access deny !Safe_ports
http_access allow localnet
http_access deny all
```

#### Logging

```squid.conf
# Access log (HTTP requests)
access_log /var/log/squid/access.log squid

# Cache log (operational messages)
cache_log /var/log/squid/cache.log

# Debug level
debug_options ALL,1
```

### Cache Performance Tuning

#### Refresh Patterns

Control how long content is cached:

```squid.conf
# Pattern                Min    Percent  Max
refresh_pattern ^ftp:    1440   20%      10080   # FTP: 1-7 days
refresh_pattern -i \.(jpg|jpeg|png|gif)$ 1440 90% 43200  # Images: 1-30 days
refresh_pattern -i \.(css|js)$ 1440 50% 10080  # CSS/JS: 1-7 days
refresh_pattern .        0      20%      4320   # Default: 0-3 days
```

#### Memory and File Descriptor Limits

```squid.conf
# Maximum file descriptors
max_filedescriptors 4096

# Connection limits
http_port_max_connections 1000
```

---

## SSL-Bump Configuration

### Prerequisites

1. Generate CA certificate and key:
```bash
openssl genrsa -out tls.key 4096
openssl req -new -x509 -key tls.key -out tls.crt -days 3650 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=Squid CA"
```

2. Create Kubernetes TLS secret:
```bash
kubectl create secret tls squid-ca-cert \
  --cert=tls.crt \
  --key=tls.key
```

3. Distribute CA certificate (`tls.crt`) to clients and add to trust store

### How SSL-Bump Works in CephaloProxy

When SSL-bump is enabled:
1. Mount TLS secret containing `tls.crt` and `tls.key` to `/etc/squid/ssl_cert/`
2. The entrypoint script merges them into `/var/lib/squid/squid-ca.pem`
3. Squid uses the merged certificate to intercept and decrypt HTTPS traffic

### Basic SSL-Bump Configuration

```squid.conf
# SSL-bump port (certificate will be merged by entrypoint script)
http_port 3128 ssl-bump \
  cert=/var/lib/squid/squid-ca.pem \
  generate-host-certificates=on \
  dynamic_cert_mem_cache_size=16MB

# SSL certificate helper
sslcrtd_program /usr/libexec/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 16MB
sslcrtd_children 10 startup=1 idle=1

# SSL bump steps
acl step1 at_step SslBump1
acl step2 at_step SslBump2
acl step3 at_step SslBump3

ssl_bump peek step1
ssl_bump stare step2
ssl_bump bump step3
```

### Selective SSL-Bump

Only intercept specific domains:

```squid.conf
# Define domains to bump
acl bump_domains dstdomain .example.com .company.local

# Define domains to never bump (sensitive sites)
acl nobump_domains dstdomain .bank.com .healthcare.gov

# SSL bump rules
ssl_bump peek step1
ssl_bump splice nobump_domains
ssl_bump stare step2
ssl_bump bump bump_domains
ssl_bump splice all  # Don't bump other domains
```

---

## ACL Configuration

### ACL Types

#### Source IP/Network

```squid.conf
acl localnet src 10.0.0.0/8
acl office_network src 192.168.1.0/24
acl specific_host src 192.168.1.100
```

#### Destination Domain

```squid.conf
# External file
acl blocked_domains dstdomain "/etc/squid/conf.d/blocked.acl"

# Inline
acl social_media dstdomain .facebook.com .twitter.com

# Regex
acl streaming dstregex youtube\.com|netflix\.com
```

#### Time-Based

```squid.conf
# Monday-Friday 9am-5pm
acl work_hours time MTWHF 09:00-17:00

# Weekend
acl weekend time SA 00:00-23:59
```

#### URL Patterns

```squid.conf
# File extensions
acl downloads urlpath_regex -i \.(exe|zip|tar|gz)$

# Query strings
acl dynamic_content urlpath_regex cgi-bin \?
```

#### Content Type

```squid.conf
acl video rep_mime_type video/.*
acl images rep_mime_type image/.*
```

#### File Size

```squid.conf
# Files larger than 100MB
acl large_files rep_header Content-Length -gt 104857600
```

### Access Rules Examples

#### Block Social Media

```squid.conf
acl social_media dstdomain .facebook.com .twitter.com .instagram.com
http_access deny social_media
```

#### Time-Based Restrictions

```squid.conf
acl streaming dstdomain .youtube.com .netflix.com
acl work_hours time MTWHF 09:00-17:00

# Block streaming during work hours
http_access deny streaming work_hours
```

#### Bandwidth Management

```squid.conf
acl large_downloads rep_header Content-Length -gt 10485760  # 10MB

delay_pools 1
delay_class 1 1
delay_parameters 1 1024000/1024000  # 1 Mbps
delay_access 1 allow large_downloads
delay_access 1 deny all
```

---

## Advanced Features

### Authentication

#### Basic Authentication (NCSA)

```squid.conf
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 5
auth_param basic realm Squid Proxy
auth_param basic credentialsttl 2 hours

acl authenticated proxy_auth REQUIRED
http_access allow authenticated
```

Create password file:
```bash
htpasswd -c /etc/squid/passwords username
```

### Parent Proxy / Cache Hierarchy

#### Upstream Proxy

```squid.conf
# Forward all requests to parent proxy
cache_peer parent.example.com parent 8080 0 no-query default
never_direct allow all
```

#### Sibling Peer (Cache Sharing)

```squid.conf
cache_peer sibling.example.com sibling 3128 3130 proxy-only
```

### Header Manipulation

#### Anonymize Requests

```squid.conf
request_header_access Referer deny all
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
```

#### Add Custom Headers

```squid.conf
request_header_add X-Forwarded-Proto https all
request_header_add X-Custom-Header "value" all
```

### Custom Error Pages

```squid.conf
error_directory /etc/squid/errors/en
```

---

## Configuration Validation

Always validate configuration before deploying:

```bash
# Inside container
squid -k parse -f /etc/squid/squid.conf

# Via docker exec
docker exec squid-proxy squid -k parse -f /etc/squid/squid.conf
```

---

## Configuration Examples

### Example 1: Basic HTTP Proxy

```squid.conf
http_port 3128
cache_dir ufs /var/spool/squid 500 16 256
cache_mem 128 MB

acl localnet src 10.0.0.0/8
http_access allow localnet
http_access deny all

access_log /var/log/squid/access.log squid
```

### Example 2: Filtering Proxy

```squid.conf
http_port 3128
cache_dir ufs /var/spool/squid 500 16 256

acl blocked dstdomain "/etc/squid/conf.d/blocked.acl"
acl localnet src 10.0.0.0/8

http_access deny blocked
http_access allow localnet
http_access deny all
```

### Example 3: SSL-Bump with Filtering

```squid.conf
# TLS secret must be mounted to /etc/squid/ssl_cert/ with tls.crt and tls.key
# Entrypoint merges them into /var/lib/squid/squid-ca.pem
http_port 3128 ssl-bump \
  cert=/var/lib/squid/squid-ca.pem \
  generate-host-certificates=on \
  dynamic_cert_mem_cache_size=16MB

sslcrtd_program /usr/libexec/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 16MB
sslcrtd_children 10 startup=1 idle=1

acl step1 at_step SslBump1
acl step2 at_step SslBump2
acl step3 at_step SslBump3

ssl_bump peek step1
ssl_bump stare step2
ssl_bump bump step3

cache_dir ufs /var/spool/squid 2000 16 256

acl blocked dstdomain "/etc/squid/conf.d/blocked.acl"
acl localnet src 10.0.0.0/8

http_access deny blocked
http_access allow localnet
http_access deny all
```

---

## Next Steps

- [Deployment Guide](deployment.md) - Deploy to Docker, Kubernetes, OpenShift
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [Squid Official Documentation](http://www.squid-cache.org/Doc/config/) - Complete Squid reference
