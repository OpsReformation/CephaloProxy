# CephaloProxy Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-11-11

## Active Technologies
- Python 3.11+ (3.12 preferred), Bash (build-time only in Debian 13 slim builder stage) + Python standard library only (os, sys, subprocess, signal, pathlib, logging, time, re, shutil, asyncio) - NO external packages (003-distroless-completion)
- N/A (stateless container, persistent volumes for Squid cache/logs managed externally) (003-distroless-completion)

- Python 3.11 (initialization scripts), Bash (build-time only)
  (002-distroless-migration)
- (001-squid-proxy-container)

## Project Structure

```text
src/
tests/
```

## Commands

### Add commands for

#### Code Style

: Follow standard conventions

#### Recent Changes

- 001-squid-proxy-container: Added

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

## Recent Changes
- 003-distroless-completion: Python entrypoint migration complete - container now runs shell-free with asyncio-based initialization and graceful shutdown. Debian 12 distroless base image confirmed as optimal (Debian 13 not yet available). All runtime logic migrated from bash to Python stdlib.

- 002-distroless-migration: Added Python 3.11 (initialization scripts), Bash (build-time only)
