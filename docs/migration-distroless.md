# Migration Guide: Gentoo to Distroless

**Target Audience**: Existing CephaloProxy users upgrading from Gentoo-based
image to distroless architecture **Migration Type**: Drop-in replacement (100%
functional parity) **Breaking Changes**: Base image only - all configuration,
volumes, and functionality unchanged



## Executive Summary

### What Changed

**Container Architecture**:

- **Before**: Gentoo Linux base image with emerge package manager
- **After**: Multi-stage build (Debian 13 → gcr.io/distroless/python3-debian13)
- **Impact**: Reduced attack surface, faster builds, smaller image size

**Initialization Scripts**:

- **Before**: Bash scripts (`init-squid.sh`)
- **After**: Python 3.11 scripts (`init-squid.py`)
- **Impact**: Better error handling, improved maintainability

### What Stayed the Same

✅ **100% Functional Parity** - All features work identically:

- Volume mounts (`/var/spool/squid`, `/var/log/squid`, `/etc/squid`)
- Ports (3128 proxy, 8080 health checks)
- Configuration files (`squid.conf`)
- Health check endpoints (`/health`, `/ready`)
- SSL-bump support
- OpenShift arbitrary UID compatibility
- Graceful shutdown behavior
- ACL filtering
- Custom configuration mounting

### Security & Performance Improvements

| Metric | Gentoo Baseline | Distroless Result | Improvement |
| ------ | --------------- | ----------------- | ----------- |
| **Image Size** | ~500MB | 163MB | 67% reduction |
| **Package Count** | 500-700 packages | 34 packages | 95% reduction |
| **CVE Count** | 50-100 (estimated) | 8 HIGH/CRITICAL | 84-92% reduction |
| **Build Time** | 20-30 minutes | 6-9 minutes | 70%+ reduction |
| **Startup Time** | 10 seconds | 3 seconds | 70% faster |



## Migration Steps

### Step 1: Backup Current Configuration

Before migrating, document your current setup:

```bash
# Export current container configuration
docker inspect cephaloproxy > cephaloproxy-config-backup.json

# Backup volume data (if needed)
docker run --rm -v squid-cache:/source -v $(pwd):/backup \
  alpine tar czf /backup/squid-cache-backup.tar.gz -C /source .

# Save current squid.conf
docker cp cephaloproxy:/etc/squid/squid.conf ./squid.conf.backup
```

### Step 2: Pull New Distroless Image

```bash
# Pull the new distroless image
docker pull cephaloproxy:distroless

# Or build from source
docker build -t cephaloproxy:distroless -f container/Dockerfile.distroless .
```

### Step 3: Stop Current Container

```bash
# Graceful shutdown (allows active connections to complete)
docker stop --time=30 cephaloproxy

# Backup container (optional - keeps it for rollback)
docker commit cephaloproxy cephaloproxy:gentoo-backup
```

### Step 4: Start Distroless Container

**Use the exact same docker run command as before** - no changes needed:

```bash
# Example: Basic deployment
docker run -d \
  --name cephaloproxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:distroless

# Example: With custom configuration
docker run -d \
  --name cephaloproxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v /path/to/squid.conf:/etc/squid/squid.conf:ro \
  -v /path/to/tls-secret:/etc/squid/ssl_cert:ro \
  -v squid-cache:/var/spool/squid \
  -v squid-logs:/var/log/squid \
  cephaloproxy:distroless
```

### Step 5: Verify Migration

```bash
# Check container is running
docker ps | grep cephaloproxy

# Verify health endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Test proxy functionality
curl -x http://localhost:3128 -I http://example.com

# Check logs for any errors
docker logs cephaloproxy

# Verify cache initialization
docker logs cephaloproxy | grep "Cache directory"
```

### Step 6: Monitor for 24-48 Hours

- Monitor application logs for any unexpected errors
- Verify cache hit rates are similar to previous deployment
- Check resource usage (CPU, memory) - should be slightly lower
- Validate SSL-bump functionality (if enabled)



## Kubernetes/OpenShift Migration

### Update Image Tag

Minimal changes needed - just update the image reference:

```yaml
# Before
spec:
  containers:
  - name: squid
    image: cephaloproxy:latest  # Gentoo-based

# After
spec:
  containers:
  - name: squid
    image: cephaloproxy:distroless  # Distroless-based
```

### Rolling Update Strategy

```bash
# Update deployment with new image
kubectl set image deployment/squid-proxy squid=cephaloproxy:distroless

# Watch rollout status
kubectl rollout status deployment/squid-proxy

# Verify pods are running
kubectl get pods -l app=squid-proxy

# Check logs
kubectl logs -l app=squid-proxy --tail=50
```

### Rollback if Needed

```bash
# Rollback to previous version
kubectl rollout undo deployment/squid-proxy

# Check rollback status
kubectl rollout status deployment/squid-proxy
```



## Configuration Changes

### No Changes Required

All existing configurations work without modification:

- ✅ `squid.conf` - No syntax changes
- ✅ Volume mounts - Same paths
- ✅ Environment variables - Same variables accepted
- ✅ Health check endpoints - Same paths and behavior
- ✅ Ports - Same port numbers
- ✅ SSL certificates - Same mount paths

### Optional: Leverage New Features

**Enhanced Error Messages**:

The distroless image provides clearer error messages with Python logging:

```bash
# Example error output (old bash):
ERROR: Cache directory not writable

# Example error output (new Python):
[ERROR] Cache directory not writable: /var/spool/squid (UID 1000)
[ERROR] cache_dir directive found in squid.conf but volume not writable
[ERROR] Fix volume permissions or remove cache_dir from config for pure proxy mode
```

**No Action Required** - these improvements are automatic.



## Troubleshooting

### Issue: Container Fails to Start

**Symptom**: Container exits immediately after start

**Diagnosis**:
```bash
docker logs cephaloproxy
```

**Common Causes**:

1. **Missing cache volume** (if `cache_dir` configured in squid.conf)

   ```
   [ERROR] cache_dir directive found in squid.conf but volume not writable
   ```

   **Solution**: Mount volume: `-v squid-cache:/var/spool/squid`

2. **Invalid squid.conf**

   ```
   [ERROR] Configuration validation failed
   ```

   **Solution**: Validate config syntax, check for Gentoo-specific settings

3. **Missing SSL certificate** (if SSL-bump configured)

   ```
   [ERROR] TLS certificate not found: /etc/squid/ssl_cert/tls.crt
   ```

   **Solution**: Mount TLS secret: `-v /path/to/tls:/etc/squid/ssl_cert:ro`

### Issue: Cannot Debug with `docker exec`

**Symptom**: `docker exec -it cephaloproxy /bin/bash` fails

**Explanation**: Distroless images have NO shell by design (security feature)

**Solution**: Use debug container pattern

```bash
# Attach ephemeral debug container
docker run -it --rm \
  --pid=container:cephaloproxy \
  --network=container:cephaloproxy \
  debian:13-slim \
  /bin/bash

# Inside debug container, you can now:
ps aux | grep squid
netstat -tlnp
ls -la /proc/*/fd
```

**Alternative**: Use distroless debug variant (development only)

```dockerfile
FROM gcr.io/distroless/python3-debian13:debug AS runtime
```

### Issue: Custom CA Certificates Not Working

**Symptom**: TLS connections to internal services fail with certificate errors

**Explanation**: Distroless images don't include `update-ca-certificates`

**Solution**: Extend image with multi-stage build (see
[deployment.md](deployment.md#custom-ca-certificates-enterprise-extension))

```dockerfile
FROM debian:13-slim AS ca-builder
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    update-ca-certificates

FROM cephaloproxy:distroless
COPY --from=ca-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
```

### Issue: Logs Look Different

**Symptom**: Initialization logs have new format

**Explanation**: Python logging provides structured output with timestamps

**Expected Format**:

```
[INFO] Running as UID:1000 GID:0
[INFO] Checking Squid configuration...
[INFO] Validating Squid configuration...
[INFO] Cache directory validated: /var/spool/squid
```

**Action**: No action needed - this is expected behavior and provides better
diagnostics

### Issue: Performance Regression

**Symptom**: Slower response times or higher resource usage

**Diagnosis**:

```bash
# Check resource usage
docker stats cephaloproxy

# Compare startup times
time docker run --rm cephaloproxy:distroless python3 /usr/local/bin/init-squid.py
```

**Expected**: Distroless should be FASTER (70% faster startup, lower memory
footprint)

**If slower**: Check for misconfiguration, compare `squid.conf` settings



## Rollback Procedure

If issues occur, rollback to Gentoo-based image:

### Docker Rollback

```bash
# Stop distroless container
docker stop cephaloproxy
docker rm cephaloproxy

# Start from backup
docker run -d \
  --name cephaloproxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:gentoo-backup  # Or use previous image tag
```

### Kubernetes Rollback

```bash
# Automatic rollback to previous deployment
kubectl rollout undo deployment/squid-proxy

# Or specify revision
kubectl rollout history deployment/squid-proxy
kubectl rollout undo deployment/squid-proxy --to-revision=2
```

### Restore Configuration

```bash
# Restore squid.conf from backup
docker cp ./squid.conf.backup cephaloproxy:/etc/squid/squid.conf

# Restart container to apply config
docker restart cephaloproxy
```



## Testing Checklist

Use this checklist to validate migration success:

### Functional Testing

- [ ] Container starts successfully
- [ ] Health endpoints return 200 OK (`/health`, `/ready`)
- [ ] Proxy functionality works
  (`curl -x http://localhost:3128 http://example.com`)
- [ ] Cache directory initialized (if configured)
- [ ] SSL-bump works (if configured)
- [ ] ACL rules enforced correctly
- [ ] Logs written to `/var/log/squid/`
- [ ] Graceful shutdown works (`docker stop --time=30`)

### Security Validation

- [ ] Container runs as non-root (UID 1000 or arbitrary UID in OpenShift)
- [ ] No shell access (`docker exec -it cephaloproxy /bin/bash` should fail)
- [ ] Vulnerability scan shows reduced CVE count
- [ ] Image size reduced compared to Gentoo baseline

### Performance Testing

- [ ] Startup time ≤ previous deployment
- [ ] Proxy latency unchanged
- [ ] Cache hit rates similar to baseline
- [ ] Memory usage ≤ previous deployment

### OpenShift Specific

- [ ] Pod runs with arbitrary UID assigned by OpenShift
- [ ] All volumes writable with GID 0 permissions
- [ ] Security Context Constraints (SCC) satisfied
- [ ] Route/Ingress works correctly



## FAQ

### Q: Will my existing squid.conf work?

**A**: Yes, 100% compatible. No changes needed.

### Q: Do I need to recreate volumes?

**A**: No. Existing cache and log volumes work as-is.

### Q: Is there downtime during migration?

**A**: Yes, brief downtime while stopping old container and starting new one.
For zero-downtime, use Kubernetes rolling updates.

### Q: Can I test distroless before migrating?

**A**: Yes. Run distroless in parallel:

```bash
docker run -d --name cephaloproxy-test -p 13128:3128 -p 18080:8080 cephaloproxy:distroless
curl -x http://localhost:13128 http://example.com
```

### Q: What if I need custom packages?

**A**: Extend the image using multi-stage builds. See
[deployment.md](deployment.md#custom-ca-certificates-enterprise-extension) for
examples.

### Q: Are there any Gentoo-specific features that won't work?

**A**: No. All features have been ported. If you used Gentoo-specific tools
(e.g., `emerge`), those are not available in distroless by design.

### Q: How do I get shell access for debugging?

**A**: Use the debug container pattern (see
[Troubleshooting](#issue-cannot-debug-with-docker-exec) above) or use the
`:debug` image variant for development.



## Additional Resources

- **Quickstart Guide**:
  [specs/002-distroless-migration/quickstart.md](../specs/002-distroless-migration/quickstart.md)
- **Deployment Documentation**: [deployment.md](deployment.md)
- **Vulnerability Baseline**:
  [specs/002-distroless-migration/vulnerability-baseline.md](../specs/002-distroless-migration/vulnerability-baseline.md)
- **Implementation Plan**:
  [specs/002-distroless-migration/plan.md](../specs/002-distroless-migration/plan.md)
- **CHANGELOG**: [CHANGELOG.md](../CHANGELOG.md)



## Support

For issues or questions:

1. Check [troubleshooting section](#troubleshooting) above
2. Review container logs: `docker logs cephaloproxy`
3. Compare configuration against [deployment examples](deployment.md)
4. Report issues on GitHub with logs and configuration



**Migration Status**: Ready for Production **Recommended Approach**: Test in
staging environment first, then rolling update in production **Rollback Time**:
< 5 minutes using backup image
