#!/bin/bash
# BuildKit Validation Script
# Checks for BuildKit availability before running Docker builds
# Usage: ./scripts/validate-buildkit.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_error() {
    echo -e "${RED}Error: $1${NC}"
}

print_success() {
    echo -e "${GREEN}Success: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Check if BuildKit is disabled
if [ -n "$BUILDKIT_DISABLE" ]; then
    print_error "Docker BuildKit is disabled via BUILDKIT_DISABLE environment variable."
    echo "Set DOCKER_BUILDKIT=1 or create a buildx builder to enable BuildKit."
    echo ""
    echo "Solutions:"
    echo "  1. Enable BuildKit: export DOCKER_BUILDKIT=1"
    echo "  2. Create buildx builder: docker buildx create --name buildkit --use --driver=docker"
    exit 1
fi

# Check for docker buildx command
if ! command -v docker buildx &> /dev/null; then
    print_error "Docker buildx is not available."
    echo "BuildKit requires Docker buildx command. Please install Docker with BuildKit support."
    exit 1
fi

# Check buildx version
BUILDX_VERSION=$(docker buildx version | awk '{print $3}')
print_success "Docker buildx is available (version: ${BUILDX_VERSION})"

# Check if builder instance exists
if ! docker buildx ls | grep -q "default"; then
    print_warning "No default buildx builder found. Creating one..."
    docker buildx create --name default --use --driver=docker
    print_success "Default buildx builder created successfully"
else
    print_success "Default buildx builder exists"
fi

# Verify builder is active
if ! docker buildx inspect default &> /dev/null; then
    print_warning "No default buildx builder found. Creating one..."
    docker buildx create --name default --use --driver=docker
    print_success "Default buildx builder created successfully"
else
    print_success "Default buildx builder exists"
fi

print_success "All BuildKit validation checks passed!"

exit 0
