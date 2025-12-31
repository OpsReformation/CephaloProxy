# Troubleshooting Guide: CephaloProxy

Common issues, solutions, and debugging techniques for CephaloProxy.

## Table of Contents

- [Container Won't Start](#container-wont-start)
- [Health Checks Failing](#health-checks-failing)
- [Proxy Not Working](#proxy-not-working)
- [SSL-Bump Issues](#ssl-bump-issues)
- [Performance Problems](#performance-problems)
- [Logging and Debugging](#logging-and-debugging)
- [OpenShift-Specific Issues](#openshift-specific-issues)



## Container Won't Start

### Symptom: Container exits immediately after starting

#### Check 1: View container logs

```bash
docker logs <container-name>
# or
kubectl logs <pod-name>
# or
oc logs <pod-name>
```

#### Check 2: Configuration syntax error

**Cause**: Invalid squid.conf syntax

**Solution**:

```bash
# Validate config manually
docker run --rm \
  -v /path/to/squid.conf:/tmp/squid.conf:ro \
  cephaloproxy:latest \
  squid -k parse -f /tmp/squid.conf

# Common syntax errors:
# - Missing values: "http_port" (should be "http_port 3128")
# - Unknown directives
# - Referenced ACL files don't exist
```

#### Check 3: Permission issues on mounted volumes

**Cause**: Container UID (1000) cannot write to cache directory

**Solution**:

```bash
# Docker/Podman
sudo chown -R 1000:1000 /path/to/cache
sudo chmod 750 /path/to/cache

# OpenShift (GID 0)
sudo chown -R 1000:0 /path/to/cache
sudo chmod 770 /path/to/cache  # Group-writable
```

**Verify inside container**:

```bash
docker exec <container-name> ls -la /var/spool/squid
docker exec <container-name> id
```

#### Check 4: Port conflict

**Cause**: Port 3128 or 8080 already in use

**Solution**:

```bash
# Check what's using the port
sudo lsof -i :3128
sudo lsof -i :8080

# Use different ports
docker run -d -p 3129:3128 -p 8081:8080 cephaloproxy:latest
```

#### Check 5: SSL certificate missing (SSL-bump mode)

**Cause**: SSL-bump configured but certificates not mounted

**Error in logs**:
```
ERROR: SSL-bump enabled but CA certificate not found: /etc/squid/ssl_cert/ca.pem
```

**Solution**:

```bash
# Verify certificates exist
docker exec <container-name> ls -la /etc/squid/ssl_cert/

# Mount certificates correctly
docker run -d \
  -v /path/to/certs:/etc/squid/ssl_cert:ro \
  cephaloproxy:latest
```

## Health Checks Failing

### Symptom: Health check endpoint returns 503 or timeout

#### Check 1: Health check server not running

```bash
# Check if health check server is running
docker exec <container-name> pgrep -f healthcheck.py

# Check if port 8080 is listening
docker exec <container-name> netstat -ln | grep 8080
```

#### Check 2: Squid process not running

```bash
# Check Squid process
docker exec <container-name> pgrep squid

# Check Squid status
docker exec <container-name> ps aux | grep squid
```

**If Squid is not running, check logs**:

```bash
docker logs <container-name>
```

#### Check 3: Cache directory not writable

```bash
# Test writability
docker exec <container-name> touch /var/spool/squid/test
docker exec <container-name> rm /var/spool/squid/test
```

#### Check 4: Firewall blocking health check port

**Kubernetes/OpenShift**:

```bash
# Test health check directly from inside pod
kubectl exec <pod-name> -- curl http://localhost:8080/health

# If this works but external check fails, check network policies
kubectl get networkpolicies
```

## Proxy Not Working

### Symptom: Cannot proxy HTTP/HTTPS requests

#### Check 1: Squid is running and listening

```bash
# Check Squid process
docker exec <container-name> pgrep squid

# Check listening ports
docker exec <container-name> netstat -ln | grep 3128
```

#### Check 2: Test proxy connection

```bash
# Basic connectivity test
curl -x http://localhost:3128 -I http://example.com

# Verbose output for debugging
curl -x http://localhost:3128 -v http://example.com
```

#### Check 3: ACL blocking request

**Error**: `HTTP 403 Forbidden` or `Access Denied`

**Check access logs**:

```bash
docker exec <container-name> tail -f /var/log/squid/access.log
```

**Look for**: `TCP_DENIED`

**Solution**: Adjust ACLs in squid.conf

```squid.conf
# Add your client IP to allowed network
acl mynetwork src 192.168.1.0/24
http_access allow mynetwork
```

#### Check 4: DNS resolution issues

```bash
# Test DNS inside container
docker exec <container-name> nslookup example.com

# Check Squid DNS settings
docker exec <container-name> grep dns /etc/squid/squid.conf
```

#### Check 5: Firewall blocking proxy port

```bash
# Test from inside container (should work)
docker exec <container-name> curl http://localhost:3128

# Test from outside (may be blocked)
curl http://<container-ip>:3128
```

## SSL-Bump Issues

### Symptom: HTTPS requests fail with SSL errors

#### Check 1: CA certificate not trusted by client

**Error**: `SSL certificate problem: unable to get local issuer certificate`

**Solution**: Install CA certificate on client machine

```bash
# Linux (Ubuntu/Debian)
sudo cp ca.pem /usr/local/share/ca-certificates/squid-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ca.pem

# Test with curl (bypass cert check for testing)
curl -x http://localhost:3128 -k https://example.com
```

#### Check 2: SSL certificate permissions

**Error in logs**: `WARNING: CA private key is world-readable`

**Solution**:

```bash
chmod 640 /path/to/ca.key
chmod 644 /path/to/ca.pem
chown 1000:1000 /path/to/ca.*
```

#### Check 3: SSL database not initialized

```bash
# Check SSL database
docker exec <container-name> ls -la /var/lib/squid/ssl_db

# Should contain 'certs' directory
```

**If missing, check logs for initialization errors**

#### Check 4: ssl_crtd helper not found

**Error**: `ssl_crtd: No such file or directory`

**Check**:

```bash
docker exec <container-name> ls -la /usr/lib64/squid/ssl_crtd
```

**This should not happen if using official image**

## Performance Problems

### Symptom: Slow proxy response times

#### Check 1: Cache hit rate

```bash
# Monitor access log for cache status
docker exec <container-name> tail -f /var/log/squid/access.log | grep -E 'TCP_HIT|TCP_MISS'

# Count cache hits vs misses
docker exec <container-name> bash -c \
  "grep TCP_HIT /var/log/squid/access.log | wc -l"
docker exec <container-name> bash -c \
  "grep TCP_MISS /var/log/squid/access.log | wc -l"
```

**Low cache hit rate (<40%)**:
- Increase cache size in squid.conf
- Adjust refresh_pattern directives
- Check if content is cacheable

#### Check 2: Resource limits

```bash
# Check CPU/Memory usage
docker stats <container-name>

# Kubernetes
kubectl top pod <pod-name>
```

**High CPU/Memory**:

- Increase resource limits
- Reduce cache size if memory-constrained
- Check for excessive logging (debug_options ALL,9)

#### Check 3: Disk I/O bottleneck

```bash
# Check disk usage
docker exec <container-name> df -h /var/spool/squid

# Check I/O wait
docker exec <container-name> iostat -x 1
```

**Solution**:

- Use faster storage (SSD)
- Reduce cache size
- Use memory cache (cache_mem) more aggressively

#### Check 4: Network latency

```bash
# Test upstream connection speed
docker exec <container-name> curl -w "@-" -o /dev/null -s http://example.com <<'EOF'
    time_namelookup:  %{time_namelookup}\n
       time_connect:  %{time_connect}\n
    time_appconnect:  %{time_appconnect}\n
      time_redirect:  %{time_redirect}\n
 time_starttransfer:  %{time_starttransfer}\n
         time_total:  %{time_total}\n
EOF
```

#### Check 5: Too many concurrent connections

```squid.conf
# Increase file descriptor limit
max_filedescriptors 8192

# Increase connection limits
http_port_max_connections 2000
```

## Logging and Debugging

### Enable Verbose Logging

**Temporary (runtime)**:

```bash
docker exec <container-name> squid -k debug
```

**Permanent (squid.conf)**:

```squid.conf
# Increase debug level
debug_options ALL,2

# SSL-bump debugging
debug_options 83,5

# ACL debugging
debug_options 28,3
```

### Access Logs

**View access log**:

```bash
docker exec <container-name> tail -f /var/log/squid/access.log
```

**Access log format**:

```
timestamp duration client_ip result_code/status bytes method URL - hierarchy content_type
```

**Common result codes**:

- `TCP_HIT`: Cache hit
- `TCP_MISS`: Cache miss, fetched from origin
- `TCP_DENIED`: Access denied by ACL
- `TCP_REFRESH_HIT`: Revalidated cached content
- `TCP_CLIENT_REFRESH_MISS`: Client forced refresh

### Cache Logs

**View cache log**:

```bash
docker exec <container-name> tail -f /var/log/squid/cache.log
```

**Look for**:

- Startup messages
- Configuration errors
- Warning messages
- Cache directory initialization

### Export Logs to Host

```bash
# Mount log directory
docker run -d \
  -v /path/to/logs:/var/log/squid \
  cephaloproxy:latest

# Or copy logs from running container
docker cp <container-name>:/var/log/squid/access.log ./access.log
```

### Analyze Logs with Tools

```bash
# Install squid-analyzer (optional)
sudo apt-get install squid-analyzer

# Analyze logs
squid-analyzer /path/to/access.log
```

## OpenShift-Specific Issues

### Symptom: Container fails with permission errors on OpenShift

#### Check 1: Verify arbitrary UID support

```bash
# Check actual UID assigned by OpenShift
oc rsh deployment/squid-proxy id

# Expected: uid=1000720000 (arbitrary) gid=0 (root)
```

#### Check 2: Directory permissions

**Directories must be group-writable (GID 0)**:

```bash
# Inside container
oc rsh deployment/squid-proxy ls -la /var/spool/squid
oc rsh deployment/squid-proxy ls -la /var/log/squid

# Should show: drwxrwx--- (770) with GID 0
```

#### Check 3: Security Context Constraints (SCC)

```bash
# Check SCC for deployment
oc describe pod <pod-name> | grep -A 5 securityContext

# Should show:
# allowPrivilegeEscalation: false
# runAsNonRoot: true
```

#### Check 4: fsGroup setting

**Deployment must set fsGroup to 0**:

```yaml
spec:
  securityContext:
    fsGroup: 0
```

## Getting Help

If you've tried the above troubleshooting steps and still have issues:

1. **Collect diagnostic information**:

```bash
# Container logs
docker logs <container-name> > logs.txt

# Container inspect
docker inspect <container-name> > inspect.json

# Squid configuration
docker exec <container-name> cat /etc/squid/squid.conf > squid.conf

# Test output
curl -x http://localhost:3128 -v http://example.com > test-output.txt 2>&1
```

2. **Check for known issues**:

   - GitHub Issues: https://github.com/yourorg/cephaloproxy/issues
   - Squid FAQ: http://wiki.squid-cache.org/SquidFaq

3. **Report a bug**:
   - Include all diagnostic information
   - Describe expected vs actual behavior
   - Include steps to reproduce

## Quick Reference

### Health Check Commands

```bash
# Liveness
curl http://localhost:8080/health

# Readiness
curl http://localhost:8080/ready
```

### Configuration Validation

```bash
docker exec <container-name> squid -k parse -f /etc/squid/squid.conf
```

### Reload Configuration (without restart)

```bash
docker exec <container-name> squid -k reconfigure
```

### View Squid Version

```bash
docker exec <container-name> squid -v
```

### Test Proxy

```bash
# HTTP
curl -x http://localhost:3128 -I http://example.com

# HTTPS (with SSL-bump)
curl -x http://localhost:3128 -k -I https://example.com
```
