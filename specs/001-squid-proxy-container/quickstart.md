# Quick Start: CephaloProxy - Squid Proxy Container

**Goal**: Get a working Squid proxy container running in under 15 minutes

**Prerequisites**:
- Docker or Podman installed
- Basic understanding of HTTP proxies
- (Optional) Kubernetes/OpenShift cluster for orchestrated deployment

---

## Quick Start Options

Choose your deployment scenario:

1. [**Basic HTTP Proxy (5 minutes)**](#1-basic-http-proxy) - Default configuration, no volumes
2. [**Traffic Filtering with ACLs (10 minutes)**](#2-traffic-filtering-with-acls) - Block specific domains
3. [**SSL-Bump HTTPS Caching (15 minutes)**](#3-ssl-bump-https-caching) - Decrypt and cache HTTPS
4. [**Kubernetes Deployment (10 minutes)**](#4-kubernetes-deployment) - Deploy to K8s cluster
5. [**OpenShift Deployment (10 minutes)**](#5-openshift-deployment) - Deploy to OpenShift with SCC

---

## 1. Basic HTTP Proxy

**Use Case**: Simple HTTP proxy for testing or development

### Step 1: Run the Container

```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  cephaloproxy:latest
```

### Step 2: Test the Proxy

```bash
# Set proxy environment variable
export http_proxy=http://localhost:3128
export https_proxy=http://localhost:3128

# Test HTTP request through proxy
curl -I http://example.com

# Check health endpoints
curl http://localhost:8080/health  # Should return "OK"
curl http://localhost:8080/ready   # Should return "READY"
```

### Step 3: View Logs

```bash
docker logs squid-proxy
```

**Expected behavior**:
- Container starts in < 10 seconds
- HTTP requests proxied successfully
- Health checks return 200 OK
- Logs show "Accepting HTTP socket connections"

---

## 2. Traffic Filtering with ACLs

**Use Case**: Block specific domains (e.g., social media) for corporate network

### Step 1: Create ACL Configuration

```bash
# Create config directory
mkdir -p ./squid-config/conf.d

# Create blocked domains list
cat > ./squid-config/conf.d/blocked-domains.acl <<EOF
.facebook.com
.twitter.com
.instagram.com
.tiktok.com
EOF

# Create custom Squid configuration
cat > ./squid-config/squid.conf <<EOF
# Proxy port
http_port 3128

# Cache settings
cache_dir ufs /var/spool/squid 250 16 256

# ACL: Blocked domains
acl blocked_domains dstdomain "/etc/squid/conf.d/blocked-domains.acl"

# ACL: Local networks (adjust to your network)
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16

# Access rules
http_access deny blocked_domains
http_access allow localnet
http_access deny all

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF
```

### Step 2: Run Container with Configuration

```bash
docker run -d \
  --name squid-proxy-filtered \
  -p 3128:3128 \
  -p 8080:8080 \
  -v $(pwd)/squid-config/squid.conf:/etc/squid/squid.conf:ro \
  -v $(pwd)/squid-config/conf.d:/etc/squid/conf.d:ro \
  cephaloproxy:latest
```

### Step 3: Test Filtering

```bash
# This should succeed
curl -x http://localhost:3128 -I http://example.com

# This should be blocked
curl -x http://localhost:3128 -I http://facebook.com
# Expected: "403 Forbidden" or "Access Denied"
```

**Expected behavior**:
- Allowed domains return 200 OK
- Blocked domains return 403 Forbidden
- Logs show "TCP_DENIED" for blocked requests

---

## 3. SSL-Bump HTTPS Caching

**Use Case**: Cache HTTPS traffic to reduce bandwidth (requires client trust of CA)

⚠️ **Security Warning**: SSL-bump decrypts HTTPS traffic. Only use in controlled environments where you control client trust stores.

### Step 1: Generate CA Certificate

```bash
# Create SSL cert directory
mkdir -p ./squid-ssl-certs

# Generate CA private key
openssl genrsa -out ./squid-ssl-certs/ca.key 2048

# Generate CA certificate (valid 10 years)
openssl req -new -x509 -key ./squid-ssl-certs/ca.key \
  -out ./squid-ssl-certs/ca.pem -days 3650 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=Squid Proxy CA"

# Set permissions
chmod 640 ./squid-ssl-certs/ca.key
chmod 644 ./squid-ssl-certs/ca.pem
```

### Step 2: Create SSL-Bump Configuration

```bash
cat > ./squid-config/squid-sslbump.conf <<EOF
# SSL-bump proxy port
http_port 3128 ssl-bump \
  cert=/etc/squid/ssl_cert/ca.pem \
  key=/etc/squid/ssl_cert/ca.key \
  generate-host-certificates=on \
  dynamic_cert_mem_cache_size=4MB

# SSL certificate database
sslcrtd_program /usr/lib64/squid/ssl_crtd -s /var/lib/squid/ssl_db -M 4MB
sslcrtd_children 5

# SSL bumping rules
acl step1 at_step SslBump1
acl step2 at_step SslBump2
acl step3 at_step SslBump3

ssl_bump peek step1
ssl_bump stare step2
ssl_bump bump step3

# Cache HTTPS content
cache_dir ufs /var/spool/squid 500 16 256

# Access control
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
http_access allow localnet
http_access deny all

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF
```

### Step 3: Run Container with SSL-Bump

```bash
docker run -d \
  --name squid-proxy-sslbump \
  -p 3128:3128 \
  -p 8080:8080 \
  -v $(pwd)/squid-config/squid-sslbump.conf:/etc/squid/squid.conf:ro \
  -v $(pwd)/squid-ssl-certs:/etc/squid/ssl_cert:ro \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:latest
```

### Step 4: Trust CA Certificate (Client Side)

```bash
# Linux (Ubuntu/Debian)
sudo cp ./squid-ssl-certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./squid-ssl-certs/ca.pem

# Windows (run as Administrator in PowerShell)
# Import-Certificate -FilePath ./squid-ssl-certs/ca.pem -CertStoreLocation Cert:\LocalMachine\Root
```

### Step 5: Test HTTPS Caching

```bash
# First request (cache miss)
time curl -x http://localhost:3128 https://example.com

# Second request (cache hit)
time curl -x http://localhost:3128 https://example.com
# Should be faster due to caching
```

**Expected behavior**:
- HTTPS requests succeed
- Second request faster (cache hit)
- Logs show "TCP_HIT" for cached content
- Cache hit rate > 40% for repeated requests

---

## 4. Kubernetes Deployment

**Use Case**: Deploy to Kubernetes cluster with persistent cache

### Step 1: Create ConfigMap for Squid Configuration

```bash
kubectl create configmap squid-config \
  --from-file=squid.conf=./squid-config/squid.conf
```

### Step 2: Create PersistentVolumeClaim for Cache

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: squid-cache-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

### Step 3: Deploy Squid Proxy

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: squid-proxy
  template:
    metadata:
      labels:
        app: squid-proxy
    spec:
      containers:
      - name: squid
        image: cephaloproxy:latest
        ports:
        - containerPort: 3128
          name: proxy
        - containerPort: 8080
          name: healthcheck
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
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
---
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy
spec:
  selector:
    app: squid-proxy
  ports:
  - name: proxy
    port: 3128
    targetPort: 3128
  - name: healthcheck
    port: 8080
    targetPort: 8080
EOF
```

### Step 4: Test Deployment

```bash
# Check pod status
kubectl get pods -l app=squid-proxy

# Check service
kubectl get svc squid-proxy

# Port-forward to test locally
kubectl port-forward svc/squid-proxy 3128:3128 8080:8080

# Test proxy (in another terminal)
curl -x http://localhost:3128 -I http://example.com
```

---

## 5. OpenShift Deployment

**Use Case**: Deploy to OpenShift with Security Context Constraints (arbitrary UID/GID)

### Step 1: Create Project

```bash
oc new-project cephaloproxy
```

### Step 2: Create ConfigMap and PVC

```bash
# Create ConfigMap
oc create configmap squid-config \
  --from-file=squid.conf=./squid-config/squid.conf

# Create PVC
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: squid-cache-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

### Step 3: Deploy with OpenShift-Compatible Permissions

```bash
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: squid-proxy
  template:
    metadata:
      labels:
        app: squid-proxy
    spec:
      securityContext:
        # OpenShift assigns arbitrary UID, GID is always 0
        fsGroup: 0
      containers:
      - name: squid
        image: cephaloproxy:latest
        ports:
        - containerPort: 3128
          name: proxy
        - containerPort: 8080
          name: healthcheck
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
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
---
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy
spec:
  selector:
    app: squid-proxy
  ports:
  - name: proxy
    port: 3128
    targetPort: 3128
  - name: healthcheck
    port: 8080
    targetPort: 8080
EOF
```

### Step 4: Expose Route (Optional)

```bash
# Create route for external access
oc expose svc/squid-proxy --port=3128
oc get route
```

### Step 5: Verify OpenShift Deployment

```bash
# Check pod UID/GID (should be arbitrary, not 1000)
oc rsh deployment/squid-proxy id

# Expected output: uid=1000720000(1000720000) gid=0(root) groups=0(root)

# Check logs
oc logs deployment/squid-proxy

# Test proxy via port-forward
oc port-forward svc/squid-proxy 3128:3128
curl -x http://localhost:3128 -I http://example.com
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs squid-proxy

# Common issues:
# 1. Configuration syntax error
docker exec squid-proxy squid -k parse

# 2. Permission issues on volumes
docker exec squid-proxy ls -la /var/spool/squid
# Should be writable by UID 1000 or GID 0

# 3. Port conflict
docker ps | grep 3128
# Ensure no other service using port 3128 or 8080
```

### Health Checks Failing

```bash
# Check health endpoint directly
curl -v http://localhost:8080/health

# Check Squid process
docker exec squid-proxy pgrep squid

# Check cache directory
docker exec squid-proxy ls -la /var/spool/squid
```

### SSL-Bump Not Working

```bash
# Verify SSL certificate mounted correctly
docker exec squid-proxy ls -la /etc/squid/ssl_cert

# Check SSL database initialized
docker exec squid-proxy ls -la /var/lib/squid/ssl_db

# Test HTTPS without proxy (should work)
curl https://example.com

# Test HTTPS with proxy (should fail if CA not trusted)
curl -x http://localhost:3128 https://example.com
```

### Cache Not Persisting

```bash
# Check volume mount
docker inspect squid-proxy | grep Mounts -A 10

# Verify cache directory
docker exec squid-proxy df -h /var/spool/squid

# Check cache stats
docker exec squid-proxy squid -f /etc/squid/squid.conf -k check
```

---

## Next Steps

- **Production Deployment**: Review `docs/deployment.md` for best practices
- **Configuration Reference**: See `docs/configuration.md` for all Squid directives
- **Monitoring**: Set up Prometheus metrics collection (future feature)
- **Security Hardening**: Review SSL/TLS settings, ACL rules, and audit logging

---

## Quick Reference

| Component | Port | Purpose |
|-----------|------|---------|
| Squid Proxy | 3128 | HTTP/HTTPS proxy traffic |
| Health Checks | 8080 | /health (liveness), /ready (readiness) |

| Volume Mount | Purpose | Required |
|--------------|---------|----------|
| /etc/squid/squid.conf | Custom configuration | Optional (defaults provided) |
| /etc/squid/conf.d/ | ACL files | Optional |
| /etc/squid/ssl_cert/ | SSL certificates | Required for SSL-bump |
| /var/spool/squid | Persistent cache | Optional (ephemeral default) |

| Environment Variable | Default | Purpose |
|---------------------|---------|---------|
| SQUID_PORT | 3128 | Proxy port |
| HEALTH_PORT | 8080 | Health check port |
| CACHE_SIZE_MB | 250 | Ephemeral cache size |
