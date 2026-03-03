# CephaloProxy Development Guidelines

## Project Path

This project is named `CephaloProxy` and lives inside a parent directory named
`OpsReformation`. Both names are correct as-is. `OpsReformation` contains a
single `o` at the start — do not modify either name.

## Active Technologies

- Python 3.11+ (runtime), Bash (build-time) + Docker BuildKit, Docker Bake (HCL
  config), Docker Compose (004-docker-bake-build)
- Stateless container; Squid cache/logs managed via external persistent volumes
  (004-docker-bake-build)

- **Runtime:** Python 3.11+ (3.12 preferred), Python standard library only
  (`os`, `sys`, `subprocess`, `signal`, `pathlib`, `logging`, `time`, `re`,
  `shutil`, `asyncio`) — NO external packages
- **Build-time:** Bash (Debian 12 slim builder stage only) + Docker BuildKit
- **Storage:** Stateless container; Squid cache/logs managed via external
  persistent volumes

## Project Structure

```text
src/
tests/
```

## Code Style

Follow standard Python conventions.

## Recent Changes

- **004-docker-bake-build**: Added Docker BuildKit, Docker Bake (HCL config),
  improved caching with GitHub Actions cache and local filesystem cache,
  multi-platform build support (amd64, arm64), single-platform targets for
  testing, build validation scripts.
- 004-docker-bake-build: Added Python 3.11+ (runtime), Bash (build-time) +
  Docker BuildKit, Docker Bake (HCL config), Docker Compose
- **003-distroless-completion:** Python entrypoint migration complete. Container
  now runs shell-free with asyncio-based initialization and graceful shutdown.
  Debian 12 distroless base image confirmed as optimal (Debian 13 not yet
  available). All runtime logic migrated from Bash to Python stdlib.
- **002-distroless-migration:** Added Python 3.11 initialization scripts; Bash
  restricted to build-time only.
- **001-squid-proxy-container:** Initial Squid proxy container setup.

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
