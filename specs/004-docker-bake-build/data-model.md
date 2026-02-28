# Data Model: Docker Bake Configuration

## Overview

This document describes the data entities and relationships for the Docker Bake configuration system. The focus is on build configuration rather than runtime data.

## Entities

### Build Target

**Description**: A Docker Bake target defines a build configuration for the CephaloProxy container.

**Fields**:
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| name | string | Target name (e.g., "base", "cephaloproxy", "amd64-only") | Yes |
| context | string | Build context path (relative to repo root) | Yes |
| dockerfile | string | Path to Dockerfile (relative to context) | Yes |
| platforms | array[string] | Target platforms (e.g., ["linux/amd64", "linux/arm64"]) | No (defaults to empty) |
| tags | array[string] | Output image tags | Yes |
| inherits | array[string] | Base targets to inherit from | No |
| args | object | Build arguments (ARGs) | No |
| labels | object | Container labels | No |
| cache-from | array[string] | Cache sources | No |
| cache-to | array[string] | Cache destinations | No |
| output | string | Output type (e.g., "docker", "image") | No |
| load | boolean | Load image to docker daemon | No |
| push | boolean | Push image to registry | No |

**Relationships**:
- `inherits`: References other target names
- `args`: Key-value pairs passed to Dockerfile

**Validation Rules**:
- `name` must be unique across all targets
- `dockerfile` must be a valid path relative to `context`
- `tags` must be unique per target
- `args` keys must match valid Dockerfile ARG names

### Build Variable

**Description**: Bake variables provide configuration values that can be overridden at build time.

**Fields**:
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| name | string | Variable name (e.g., "REGISTRY", "VERSION") | Yes |
| type | string | Variable type (e.g., "string", "number", "bool") | No (defaults to string) |
| default | string | Default value | No |

**Relationships**:
- Used by targets via `args` and `labels`

**Validation Rules**:
- `name` must match variable naming conventions (uppercase, hyphen-separated)

### Build Group

**Description**: Groups define collections of targets for convenient build commands.

**Fields**:
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| name | string | Group name (e.g., "default", "dev") | Yes |
| targets | array[string] | Target names in this group | Yes |

**Relationships**:
- Groups are referenced by target names, not vice versa

**Validation Rules**:
- `name` must be unique across all groups
- All referenced target names must exist

### Build Configuration

**Description**: The complete Docker Bake configuration file structure.

**Fields**:
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| variable | array[object] | Variable definitions | No |
| target | array[object] | Target definitions | Yes |
| group | array[object] | Group definitions | No |

**Relationships**:
- All entities are part of the same configuration file
- Targets reference variables and inherit from other targets

**Validation Rules**:
- Must contain at least one target definition
- Target names must be unique
- Group names must be unique
- Circular inheritance is not allowed

## State Transitions

### Build Target Lifecycle

```
[Not Created] → [Defined] → [Built] → [Cached]
    ↓             ↓           ↓         ↓
    └─────────────┴───────────┴─────────┘
```

**States**:
- **Not Created**: Target not yet defined in configuration
- **Defined**: Target defined in docker-bake.hcl
- **Built**: Build process completed successfully
- **Cached**: Build cache available for reuse

### Configuration Change Lifecycle

```
[Original] → [Modified] → [Validated] → [Applied]
    ↓             ↓           ↓           ↓
    └─────────────┴───────────┴───────────┘
```

**States**:
- **Original**: Initial configuration state
- **Modified**: Changes made to configuration
- **Validated**: Configuration syntax validated
- **Applied**: Changes applied to build system

## Data Volume / Scale Assumptions

### Target Count
- Base target: 1
- Multi-platform target: 1
- Single platform targets: 2 (amd64-only, arm64-only)
- Development target: 1
- Total: 5 targets (static, not scaling)

### Variable Count
- Registry: 1
- Version: 1
- Platform detection: 4
- Base image config: 2
- Build flags: 1
- Total: 9 variables (static, not scaling)

### Cache Size
- Per build: ~500MB (distroless image layers)
- Build cache: ~2GB (multi-platform with compression)
- Not expected to grow beyond 5GB

## Configuration File Structure

```hcl
# docker-bake.hcl
variable {
  name = "REGISTRY"
  type = "string"
  default = "cephaloproxy"
}

target "base" {
  context = "./container"
  dockerfile = "Dockerfile.distroless"
  args = { ... }
  cache-from = [ ... ]
}

target "cephaloproxy" {
  inherits = ["base"]
  platforms = ["linux/amd64", "linux/arm64"]
  tags = [ ... ]
  cache-to = [ ... ]
}

group "default" {
  targets = ["cephaloproxy"]
}
```

## Validation Rules Summary

1. **Syntax**: HCL syntax must be valid
2. **Uniqueness**: Target and variable names must be unique
3. **References**: All inherited targets must exist
4. **Paths**: All file paths must be valid and accessible
5. **Platforms**: Platform strings must match Docker format (e.g., "linux/amd64")
6. **Tags**: Tags must be unique per target
7. **Cache**: Cache sources and destinations must be valid

## Integration with Dockerfile

The Docker Bake configuration maps directly to Dockerfile ARGs:

```dockerfile
# Dockerfile.distroless
ARG DISTROLESS_BASE
ARG DISTROLESS_BASE_SHA
ARG DEBIAN_VERSION
ARG BUILDPLATFORM
ARG TARGETPLATFORM
```

Bake passes these via:
```hcl
target "base" {
  args = {
    DISTROLESS_BASE = "${DISTROLESS_BASE}"
    DISTROLESS_BASE_SHA = "${DISTROLESS_BASE_SHA}"
    DEBIAN_VERSION = "${DEBIAN_VERSION}"
    BUILDPLATFORM = "${BUILDPLATFORM}"
    TARGETPLATFORM = "${TARGETPLATFORM}"
  }
}
```

## Error Scenarios

### Build Failure
- **Trigger**: Invalid ARG values, missing files, network errors
- **Response**: Fail fast with clear error message (FR-005)
- **Recovery**: Fix configuration, retry build

### Cache Failure
- **Trigger**: Registry unavailable, cache corruption
- **Response**: Build without cache, use fallback
- **Recovery**: Clear cache, rebuild from scratch

### BuildKit Unavailable
- **Trigger**: BuildKit disabled, no buildx builder
- **Response**: Fail with error message (FR-006)
- **Recovery**: Enable BuildKit, create buildx builder
