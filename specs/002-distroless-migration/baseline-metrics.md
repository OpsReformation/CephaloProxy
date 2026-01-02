# Baseline Metrics: Current Gentoo-Based Container

**Purpose**: Document current container metrics for comparison with distroless migration
**Date**: 2025-12-31
**Container**: Gentoo-based multi-stage build (current production)

---

## Overview

This document establishes baseline metrics for the current Gentoo-based CephaloProxy container. These metrics will be used to validate success criteria (SC-001 through SC-008) after the distroless migration.

**Baseline Container**:
- Base Image: `gentoo/stage3:20251229`
- Build Strategy: Multi-stage with Portage compilation
- Squid Version: 6.x (compiled with SSL-bump support)
- Runtime: Gentoo Stage3 with Squid + Python binaries

---

## SC-001: Image Size Baseline

**Current Image Size**: To be measured

```bash
# Measure current image size
docker images cephaloproxy:current --format "{{.Repository}}:{{.Tag}} {{.Size}}"

# Expected: ~500MB+ based on Gentoo Stage3 base
```

**Target After Migration**: ≤300MB (40%+ reduction)

**Measurement Method**:
```bash
docker images | grep cephaloproxy
```

---

## SC-002: Package Count Baseline

**Current Package Count**: To be measured

```bash
# Count installed packages in Gentoo container
docker run --rm gentoo/stage3:20251229 sh -c 'qlist -I | wc -l'

# Expected: Hundreds of packages (Gentoo Stage3 includes full system)
```

**Estimated Breakdown**:
- Gentoo Stage3 base: ~400-500 packages
- Squid dependencies: ~50-100 packages
- Python + dependencies: ~50-100 packages
- **Total**: ~500-700 packages

**Target After Migration**: <50 components (80%+ reduction)

**Note**: Distroless images don't have a package manager, so "component count" will measure binaries and libraries only.

---

## SC-003: CVE Count Baseline

**Current CVE Count**: To be measured

```bash
# Scan current container with Trivy
trivy image --severity HIGH,CRITICAL cephaloproxy:current --format json > baseline-cve.json

# Count HIGH and CRITICAL CVEs
trivy image --severity HIGH,CRITICAL cephaloproxy:current | grep "Total:"
```

**Expected Vulnerability Profile**:
- HIGH severity: To be measured
- CRITICAL severity: To be measured
- **Total**: Baseline for 60% reduction target

**Target After Migration**: ≥60% reduction in total CVE count

**Factors**:
- Gentoo Stage3 includes many system packages (bash, coreutils, util-linux, etc.)
- Each package contributes potential CVEs
- Distroless eliminates shell, package manager, and hundreds of unnecessary binaries

---

## SC-004: Integration Test Pass Rate

**Current Pass Rate**: 100% (all tests passing)

```bash
# Run existing integration tests
export IMAGE_NAME=cephaloproxy:current
bats tests/integration/test-basic-proxy.bats
bats tests/integration/test-health-checks.bats
bats tests/integration/test-acl-filtering.bats
```

**Test Coverage**:
- Basic HTTP proxy functionality
- Health check endpoints (/health, /ready)
- ACL filtering and access control
- SSL-bump certificate handling
- Graceful shutdown behavior

**Target After Migration**: 100% pass rate (no test modifications allowed)

---

## SC-005: Container Startup Time Baseline

**Current Startup Time**: To be measured

```bash
# Measure time from container start to health check ready
time docker run --rm -d --name test-startup cephaloproxy:current

# Poll health endpoint
START_TIME=$(date +%s)
until curl -sf http://localhost:8080/ready; do
  sleep 0.1
done
END_TIME=$(date +%s)
STARTUP_SECONDS=$((END_TIME - START_TIME))

docker stop test-startup
echo "Startup time: ${STARTUP_SECONDS}s"
```

**Expected Startup Time**: 5-10 seconds

**Components**:
1. Container initialization: ~1-2s
2. Python health check server start: ~1-2s
3. Squid configuration validation: ~1s
4. Cache initialization (if first run): ~2-4s
5. Squid daemon start: ~1-2s

**Target After Migration**: ≤110% of baseline (max 10% slower)

**Acceptable Range**: If baseline is 8s, distroless must be ≤8.8s

---

## SC-006: Operational Regression Testing

**Current Functionality**: All features operational

**Verified Behaviors**:
- ✅ HTTP proxy (port 3128)
- ✅ HTTPS proxy with CONNECT method
- ✅ SSL-bump with custom CA certificate
- ✅ ACL-based filtering
- ✅ Cache directory persistence
- ✅ Health check server (port 8080)
- ✅ Graceful shutdown (SIGTERM handling)
- ✅ OpenShift arbitrary UID compatibility
- ✅ Volume mounts (/etc/squid/squid.conf, /var/spool/squid, etc.)
- ✅ Environment variable configuration (SQUID_PORT, HEALTH_PORT, LOG_LEVEL)

**Target After Migration**: Zero regressions (100% functional parity)

---

## SC-007: Script Complexity Baseline

**Current Initialization Script**: `container/init-squid.sh`

```bash
# Measure current script complexity
wc -l container/init-squid.sh
# Expected: ~146 lines (bash)

# Cyclomatic complexity (using shellcheck or similar)
shellcheck --severity=info container/init-squid.sh | grep "complexity"
```

**Complexity Metrics**:
- Lines of Code (LOC): 146 lines
- Functions: ~6-8 functions
- Conditional branches: Multiple if/then/else blocks
- External dependencies: Uses bash, grep, awk, sed, find, chmod, chown
- Error handling: Basic exit codes

**Target After Migration**: ≥30% complexity reduction

**Expected Python Script**:
- Lines of Code: ~100-120 lines (Python)
- Cyclomatic complexity: Lower (Python stdlib functions vs bash commands)
- Maintainability: Higher (Python's readability, testing framework)

---

## SC-008: Build Time Baseline

**Current Build Time**: To be measured

```bash
# Measure full build time from clean state
docker system prune -a --volumes -f
time docker build -t cephaloproxy:current -f container/Dockerfile .
```

**Expected Build Time**: 20-30 minutes

**Build Phases**:
1. **Portage Stage** (~2-3 min):
   - Download Portage snapshot
   - Copy to builder stage
2. **Squid Compilation** (~15-20 min):
   - emerge --sync (if needed)
   - emerge dev-libs/openssl (~5-8 min)
   - emerge net-proxy/squid (~10-12 min with SSL flags)
   - Verify SSL-bump support
3. **Python Installation** (~3-5 min):
   - emerge dev-lang/python:3.11
4. **Runtime Stage** (~1-2 min):
   - Copy binaries from builder
   - Set permissions
   - Configure directories

**Bottleneck**: Gentoo's `emerge` compiles from source, including all dependencies

**Target After Migration**: ≥70% reduction (6-9 minutes)

**Expected Distroless Build**:
1. **Debian Builder Stage** (~4-6 min):
   - apt-get update + install build tools (~1 min)
   - Download + compile Squid from source (~3-5 min)
2. **Runtime Stage** (~1-2 min):
   - Copy binaries to distroless base
   - Set permissions

**Speedup Factors**:
- Debian apt uses pre-compiled binaries for dependencies
- Only Squid needs source compilation (for SSL-bump flags)
- Distroless runtime stage is minimal (just file copies)

---

## Measurement Checklist

Before starting distroless migration, measure these baseline values:

- [ ] **Image Size**: `docker images cephaloproxy:current`
  - Record size in MB
  - Document date and build
- [ ] **Package Count**: `docker run --rm gentoo/stage3:20251229 sh -c 'qlist -I | wc -l'`
  - Record total package count
  - Optional: Export full package list for analysis
- [ ] **CVE Count**: `trivy image --severity HIGH,CRITICAL cephaloproxy:current`
  - Record HIGH count
  - Record CRITICAL count
  - Save full JSON report
- [ ] **Startup Time**: Measure with health check polling script
  - Run 5 times, take average
  - Record min/max/avg
- [ ] **Build Time**: Measure clean build with `time docker build`
  - Clear Docker build cache first
  - Record total build time
  - Document build host specs (CPU, RAM)

---

## Comparison Template

After distroless migration, use this template to compare results:

| Metric | Baseline (Gentoo) | Distroless | Change | Success Criteria | Status |
|--------|-------------------|------------|--------|------------------|--------|
| Image Size | ___ MB | ___ MB | ___% | ≥40% reduction | ⬜ |
| Package Count | ___ pkgs | ___ components | ___% | ≥80% reduction | ⬜ |
| HIGH CVEs | ___ | ___ | ___% | ≥60% reduction | ⬜ |
| CRITICAL CVEs | ___ | ___ | ___% | ≥60% reduction | ⬜ |
| Integration Tests | 100% pass | ___% pass | ___ | 100% pass | ⬜ |
| Startup Time | ___ s | ___ s | ___% | ≤110% baseline | ⬜ |
| Build Time | ___ min | ___ min | ___% | ≥70% reduction | ⬜ |
| Script LOC | 146 lines | ___ lines | ___% | ≥30% reduction | ⬜ |

---

## Notes

**Baseline Not Yet Measured**: This document provides the measurement methodology. Actual baseline values should be collected before beginning Phase 3 (container implementation) to ensure accurate comparison.

**Build Host Variability**: Build times will vary based on:
- CPU cores and speed
- Available RAM
- Docker build cache state
- Network bandwidth (for package downloads)
- Disk I/O performance

For consistent measurements:
- Use same build host for baseline and distroless builds
- Clear Docker build cache before measurements: `docker builder prune -a -f`
- Document host specifications

**CI/CD Measurements**: Once baseline is established, CI/CD pipeline should track these metrics on every build to detect regressions.

---

## References

- **Success Criteria**: [plan.md - Success Criteria Mapping](plan.md#success-criteria-mapping)
- **Acceptance Tests**: [spec.md - User Scenarios & Testing](spec.md#user-scenarios--testing-mandatory)
- **Current Dockerfile**: [container/Dockerfile](../../container/Dockerfile)
