# Deploy CephaloProxy v1.0-mvp

**Quick deployment guide for production MVP release**

---

## ✅ What's Ready for Production

- ✅ **Basic HTTP Proxy** (User Story 1) - 100% tested
- ✅ **Traffic Filtering with ACLs** (User Story 2) - 83% tested, fully functional
- ✅ **Custom Configuration** (User Story 4) - 100% tested

**Image**: `cephaloproxy:v1.0-mvp` (1.14GB)
**Base**: Gentoo Linux + Squid 6.x
**Status**: Production Ready

---

## Quick Start (5 minutes)

### Option 1: Docker (Simplest)

```bash
# Pull/verify image
docker images | grep cephaloproxy

# Deploy
docker run -d \
  --name cephaloproxy \
  -p 3128:3128 \
  -p 8080:8080 \
  --restart unless-stopped \
  cephaloproxy:v1.0-mvp

# Verify
curl http://localhost:8080/health      # Should return: OK
curl http://localhost:8080/ready       # Should return: READY
curl -x http://localhost:3128 -I http://example.com  # Should work

# View logs
docker logs -f cephaloproxy
```

### Option 2: Docker Compose (Recommended)

```bash
# Use production compose file
docker-compose -f deploy/docker-compose.production.yml up -d

# Verify
docker-compose -f deploy/docker-compose.production.yml ps
docker-compose -f deploy/docker-compose.production.yml logs -f
```

### Option 3: Kubernetes (Production)

```bash
# Deploy to cluster
kubectl apply -f deploy/kubernetes-mvp.yaml

# Verify deployment
kubectl get pods -n cephaloproxy
kubectl get svc -n cephaloproxy

# Check health
kubectl port-forward -n cephaloproxy svc/squid-proxy 8080:8080
curl http://localhost:8080/health
```

---

## Deployment Scenarios

### Scenario 1: Basic HTTP Proxy (No Config)

**Use Case**: Quick proxy deployment for testing/development

```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  cephaloproxy:v1.0-mvp
```

**Features**:
- Zero configuration required
- Ephemeral cache (250MB in /tmp)
- Default ACLs (allow local networks)
- Health endpoints enabled

---

### Scenario 2: HTTP Proxy with ACL Filtering

**Use Case**: Corporate proxy with domain blocking

**Step 1**: Create blocked domains list
```bash
cat > blocked-domains.acl <<EOF
.facebook.com
.twitter.com
.instagram.com
.tiktok.com
.youtube.com
EOF
```

**Step 2**: Create squid.conf (or use example)
```bash
cp config-examples/filtering/squid.conf ./squid.conf
```

**Step 3**: Deploy with filtering
```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v $(pwd)/squid.conf:/etc/squid/squid.conf:ro \
  -v $(pwd)/blocked-domains.acl:/etc/squid/conf.d/blocked-domains.acl:ro \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:v1.0-mvp
```

**Step 4**: Test filtering
```bash
# Should succeed
curl -x http://localhost:3128 -I http://example.com

# Should be blocked (403)
curl -x http://localhost:3128 -I http://facebook.com
```

---

### Scenario 3: Custom Configuration

**Use Case**: Advanced proxy with authentication, custom cache, etc.

**Step 1**: Create custom squid.conf
```bash
cp config-examples/advanced/squid.conf ./my-squid.conf
# Edit as needed
```

**Step 2**: Deploy
```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v $(pwd)/my-squid.conf:/etc/squid/squid.conf:ro \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:v1.0-mvp
```

---

## Production Deployment Checklist

### Pre-Deployment

- [ ] Review `RELEASE-NOTES-v1.0-mvp.md`
- [ ] Test locally with `docker run`
- [ ] Verify health endpoints respond
- [ ] Test proxy functionality
- [ ] Review configuration (if custom)
- [ ] Prepare monitoring/alerting

### Deployment

#### Docker Deployment
- [ ] Tag image appropriately
- [ ] Mount persistent volumes for cache/logs
- [ ] Configure resource limits
- [ ] Set up log rotation (if not using orchestrator)
- [ ] Configure restart policy

#### Kubernetes Deployment
- [ ] Update image tag in manifest
- [ ] Configure PersistentVolumeClaim size
- [ ] Set resource requests/limits
- [ ] Configure HPA (optional)
- [ ] Set up monitoring/alerting
- [ ] Configure network policies

#### Post-Deployment
- [ ] Verify pods/containers are running
- [ ] Check health endpoints
- [ ] Test proxy functionality
- [ ] Monitor logs for errors
- [ ] Set up client configuration
- [ ] Test from client machines
- [ ] Monitor performance metrics

---

## Configuration Guide

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE_SIZE_MB` | 250 | Ephemeral cache size (MB) |
| `LOG_LEVEL` | 1 | Squid debug level (0-9) |
| `SQUID_PORT` | 3128 | Proxy listening port |
| `HEALTH_PORT` | 8080 | Health check port |

### Volume Mounts

| Path | Purpose | Required |
|------|---------|----------|
| `/var/spool/squid` | Persistent cache | Optional |
| `/var/log/squid` | Log files | Optional |
| `/etc/squid/squid.conf` | Custom config | Optional |
| `/etc/squid/conf.d/` | ACL files | Optional |

### Resource Requirements

**Minimum**:
- CPU: 500m
- Memory: 512Mi
- Storage: 1Gi (for cache)

**Recommended**:
- CPU: 1-2 cores
- Memory: 1-2Gi
- Storage: 10-50Gi (for cache)

---

## Client Configuration

### Linux/macOS

**Shell**:
```bash
export http_proxy=http://proxy-host:3128
export https_proxy=http://proxy-host:3128
export no_proxy=localhost,127.0.0.1
```

**System-wide** (Ubuntu/Debian):
```bash
sudo nano /etc/environment
# Add:
http_proxy="http://proxy-host:3128"
https_proxy="http://proxy-host:3128"
no_proxy="localhost,127.0.0.1"
```

### Windows

**PowerShell**:
```powershell
$env:http_proxy = "http://proxy-host:3128"
$env:https_proxy = "http://proxy-host:3128"
```

**System Settings**:
- Settings → Network & Internet → Proxy
- Enable "Use a proxy server"
- Address: `proxy-host`
- Port: `3128`

### Docker

Add to `/etc/docker/daemon.json`:
```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy-host:3128",
      "httpsProxy": "http://proxy-host:3128",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

---

## Monitoring

### Health Checks

```bash
# Liveness (is container alive?)
curl http://proxy-host:8080/health

# Readiness (is it ready to serve traffic?)
curl http://proxy-host:8080/ready
```

### Logs

```bash
# Docker
docker logs -f cephaloproxy

# Kubernetes
kubectl logs -f -n cephaloproxy deployment/squid-proxy

# Direct access (if volume mounted)
tail -f /var/log/squid/access.log
tail -f /var/log/squid/cache.log
```

### Metrics

**Access Log Format**:
```
timestamp duration client_ip result_code/status bytes method URL hierarchy content_type
```

**Key Metrics to Monitor**:
- Request rate (req/s)
- Cache hit rate (TCP_HIT / total requests)
- Response time (P50, P95, P99)
- Error rate (4xx, 5xx responses)
- Memory usage
- CPU usage

---

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs cephaloproxy

# Common issues:
# 1. Port already in use
# 2. Volume permission issues
# 3. Configuration syntax error
```

### Health checks failing
```bash
# Test directly
curl http://localhost:8080/health

# Check Squid process
docker exec cephaloproxy pgrep squid

# Check permissions
docker exec cephaloproxy ls -la /var/spool/squid
```

### Proxy not working
```bash
# Test connectivity
curl -x http://localhost:3128 -v http://example.com

# Check logs
docker logs cephaloproxy | grep -i denied

# Verify ACLs
docker exec cephaloproxy cat /etc/squid/squid.conf
```

**See**: `docs/troubleshooting.md` for complete guide

---

## Rollback

If issues occur:

### Docker
```bash
docker stop cephaloproxy
docker rm cephaloproxy
# Deploy previous version or rollback config
```

### Kubernetes
```bash
kubectl rollout undo deployment/squid-proxy -n cephaloproxy
kubectl rollout status deployment/squid-proxy -n cephaloproxy
```

---

## Next Steps

### After Successful Deployment

1. **Monitor Performance**
   - Watch logs for errors
   - Monitor resource usage
   - Track cache hit rates

2. **Optimize Configuration**
   - Adjust cache size based on usage
   - Fine-tune ACLs if needed
   - Configure log rotation

3. **Scale if Needed**
   - Increase replicas (Kubernetes)
   - Add load balancing
   - Adjust resource limits

4. **Plan for v1.1**
   - SSL-bump production readiness
   - Additional features
   - Performance improvements

---

## Support

- **Documentation**: See `docs/` directory
- **Release Notes**: `RELEASE-NOTES-v1.0-mvp.md`
- **Test Results**: `TEST-RESULTS.md`
- **Troubleshooting**: `docs/troubleshooting.md`
- **Known Warnings**: `docs/KNOWN_WARNINGS.md`

---

## Success Criteria

Your deployment is successful when:

- ✅ Health endpoints return 200 OK
- ✅ Proxy forwards HTTP requests
- ✅ ACL filtering works (if configured)
- ✅ Container restarts successfully
- ✅ Logs show no errors
- ✅ Clients can use proxy

---

**Ready to deploy? Choose your scenario above and follow the steps!**

🚀 Happy deploying!
