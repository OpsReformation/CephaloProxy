# Deployment Guide: CephaloProxy

Complete deployment guide for Docker, Kubernetes, and OpenShift environments.

## Table of Contents

- [Docker Deployment](#docker-deployment)
- [Docker Compose Deployment](#docker-compose-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [OpenShift Deployment](#openshift-deployment)
- [Production Considerations](#production-considerations)

## Docker Deployment

### Basic Deployment

```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  cephaloproxy:latest
```

### With Persistent Cache

```bash
docker volume create squid-cache

docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:latest
```

### Docker with Custom Configuration

```bash
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v /path/to/squid.conf:/etc/squid/squid.conf:ro \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:latest
```

### With SSL-Bump

```bash
# TLS secret directory must contain tls.crt and tls.key
docker run -d \
  --name squid-proxy \
  -p 3128:3128 \
  -p 8080:8080 \
  -v /path/to/squid.conf:/etc/squid/squid.conf:ro \
  -v /path/to/tls-secret:/etc/squid/ssl_cert:ro \
  -v squid-cache:/var/spool/squid \
  cephaloproxy:latest
```

## Docker Compose Deployment

### Basic docker-compose.yml

```yaml
version: '3.8'

services:
  squid:
    image: cephaloproxy:latest
    container_name: squid-proxy
    ports:
      - "3128:3128"
      - "8080:8080"
    volumes:
      - squid-cache:/var/spool/squid
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  squid-cache:
```

### Docker Compose with Custom Configuration

```yaml
version: '3.8'

services:
  squid:
    image: cephaloproxy:latest
    container_name: squid-proxy
    ports:
      - "3128:3128"
      - "8080:8080"
    volumes:
      - ./squid.conf:/etc/squid/squid.conf:ro
      - ./acls:/etc/squid/conf.d:ro
      - squid-cache:/var/spool/squid
      - squid-logs:/var/log/squid
    environment:
      - LOG_LEVEL=1
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  squid-cache:
  squid-logs:
```

### Deploy

```bash
docker-compose up -d
docker-compose logs -f
docker-compose ps
```

## Kubernetes Deployment

### ConfigMap for Squid Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: squid-config
  namespace: default
data:
  squid.conf: |
    http_port 3128
    cache_dir ufs /var/spool/squid 1000 16 256
    cache_mem 128 MB
    maximum_object_size 10 MB

    acl SSL_ports port 443
    acl Safe_ports port 80 443 21 70 210 1025-65535
    acl CONNECT method CONNECT
    acl localnet src 10.0.0.0/8
    acl localnet src 172.16.0.0/12
    acl localnet src 192.168.0.0/16

    http_access deny !Safe_ports
    http_access deny CONNECT !SSL_ports
    http_access allow localhost manager
    http_access deny manager
    http_access allow localnet
    http_access allow localhost
    http_access deny all

    access_log /var/log/squid/access.log squid
    cache_log /var/log/squid/cache.log

    visible_hostname cephaloproxy
```

### PersistentVolumeClaim for Cache

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: squid-cache-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard  # Adjust based on your cluster
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
  namespace: default
  labels:
    app: squid-proxy
spec:
  replicas: 1
  strategy:
    type: Recreate
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
          protocol: TCP
        - containerPort: 8080
          name: healthcheck
          protocol: TCP
        env:
        - name: LOG_LEVEL
          value: "1"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2Gi
        volumeMounts:
        - name: config
          mountPath: /etc/squid/squid.conf
          subPath: squid.conf
          readOnly: true
        - name: cache
          mountPath: /var/spool/squid
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
      volumes:
      - name: config
        configMap:
          name: squid-config
      - name: cache
        persistentVolumeClaim:
          claimName: squid-cache-pvc
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy
  namespace: default
spec:
  selector:
    app: squid-proxy
  type: ClusterIP
  ports:
  - name: proxy
    port: 3128
    targetPort: 3128
    protocol: TCP
  - name: healthcheck
    port: 8080
    targetPort: 8080
    protocol: TCP
```

### Deploy to Kubernetes

```bash
kubectl apply -f configmap.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Verify deployment
kubectl get pods -l app=squid-proxy
kubectl logs -l app=squid-proxy -f

# Test proxy via port-forward
kubectl port-forward svc/squid-proxy 3128:3128
curl -x http://localhost:3128 -I http://example.com
```

### Kubernetes with SSL-Bump

To enable SSL-bump in Kubernetes, create and mount a TLS secret:

```bash
# Create TLS certificate
openssl genrsa -out tls.key 4096
openssl req -new -x509 -key tls.key -out tls.crt -days 3650 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=Squid CA"

# Create Kubernetes secret
kubectl create secret tls squid-ca-cert \
  --cert=tls.crt \
  --key=tls.key \
  -n default
```

Update your ConfigMap with SSL-bump configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: squid-config
  namespace: default
data:
  squid.conf: |
    # SSL-bump configuration (certificate merged by entrypoint)
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

    cache_dir ufs /var/spool/squid 1000 16 256
    cache_mem 128 MB

    acl localnet src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    http_access allow localnet
    http_access deny all

    access_log /var/log/squid/access.log squid
    visible_hostname cephaloproxy
```

Add the TLS secret volume mount to your Deployment:

```yaml
        volumeMounts:
        - name: config
          mountPath: /etc/squid/squid.conf
          subPath: squid.conf
          readOnly: true
        - name: tls-secret
          mountPath: /etc/squid/ssl_cert
          readOnly: true
        - name: cache
          mountPath: /var/spool/squid
      volumes:
      - name: config
        configMap:
          name: squid-config
      - name: tls-secret
        secret:
          secretName: squid-ca-cert
      - name: cache
        persistentVolumeClaim:
          claimName: squid-cache-pvc
```

## OpenShift Deployment

**CephaloProxy works out-of-the-box on OpenShift** using the standard Kubernetes deployment manifests above. No special configuration is required.

### Built-in OpenShift Compatibility

The container is designed to comply with OpenShift's strict Security Context Constraints (SCC):

- **Arbitrary UID Support**: Runs correctly with any UID assigned by OpenShift (typically 1000000000+)
- **GID 0 Compatibility**: All writable directories have group ownership set to GID 0 (root group) with group-writable permissions
- **Non-root User**: Runs as UID 1000 by default, but works with any arbitrary UID
- **Minimal Privileges**: Drops all capabilities, no privilege escalation

### Deployment Steps

Use the same [Kubernetes deployment manifests](#kubernetes-deployment) shown above. Simply replace `kubectl` commands with `oc`:

```bash
# Create project
oc new-project cephaloproxy

# Deploy using standard Kubernetes manifests
oc apply -f configmap.yaml
oc apply -f pvc.yaml
oc apply -f deployment.yaml
oc apply -f service.yaml

# Verify deployment
oc get pods -l app=squid-proxy
oc logs -l app=squid-proxy -f

# Test proxy
oc port-forward svc/squid-proxy 3128:3128
curl -x http://localhost:3128 -I http://example.com
```

### OpenShift Route (Optional)

If you need external access via OpenShift Route:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: squid-proxy
  namespace: cephaloproxy
spec:
  port:
    targetPort: proxy
  to:
    kind: Service
    name: squid-proxy
```

## Production Considerations

### Resource Limits

- **CPU**: 500m minimum, 2000m recommended for high traffic
- **Memory**: 512Mi minimum, 2Gi+ recommended (depends on cache size)
- **Storage**: 10Gi minimum for cache, adjust based on traffic patterns

### High Availability

For HA deployments, run multiple replicas with a load balancer:

```yaml
spec:
  replicas: 3  # Multiple replicas
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

**Note**: Squid cache is local to each pod. For shared cache, consider external
caching solutions or parent proxy hierarchy.

### Monitoring

- Monitor `/health` and `/ready` endpoints
- Collect logs from `/var/log/squid/`
- Track cache hit rates via access logs
- Monitor resource usage (CPU, memory, disk)

### Security

- Run with minimal privileges (UID 1000 or arbitrary UID in OpenShift)
- Use read-only volume mounts for configs
- Store SSL certificates in Kubernetes Secrets
- Enable network policies to restrict proxy access
- Regularly update the container image for security patches

### Backup and Recovery

- **Configuration**: Store configs in version control
- **Cache**: Ephemeral by design, no backup needed (rebuild on restart)
- **Logs**: Export to external log aggregation (ELK, Splunk, etc.)

### Scaling

- Horizontal scaling: Increase replicas
- Vertical scaling: Increase CPU/memory limits
- Cache sizing: Adjust `cache_dir` in squid.conf based on available storage

## Next Steps

- [Configuration Reference](configuration.md) - Detailed configuration options
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
