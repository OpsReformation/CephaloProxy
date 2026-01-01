#!/bin/bash
# Multi-platform build script for CephaloProxy distroless container
# Supports both amd64 (x86_64) and arm64 (aarch64) architectures
#
# Usage:
#   ./build-multiplatform.sh [OPTIONS]
#
# Options:
#   --registry REGISTRY     Container registry URL (e.g., ghcr.io/org, quay.io/org)
#   --image IMAGE           Image name (default: cephaloproxy)
#   --platform PLATFORM     Build for specific platform (linux/amd64 or linux/arm64)
#   --push                  Push to registry after build (requires buildx CA trust)
#   --push-separately       Build each platform separately and push with docker (for custom CAs)
#   --tag TAG               Image tag (default: distroless)
#   --load                  Load image into local Docker (single platform only)
#
# Examples:
#   # Build for current platform and load locally
#   ./build-multiplatform.sh --load
#
#   # Build for both platforms and push to registry (public registry)
#   ./build-multiplatform.sh \
#       --registry ghcr.io/opsreformation \
#       --platform linux/amd64,linux/arm64 \
#       --tag latest \
#       --push
#
#   # Build for both platforms and push to registry with custom CA
#   ./build-multiplatform.sh \
#       --registry quay.apps.roshar.cosmere.lan/opsreformation \
#       --platform linux/amd64,linux/arm64 \
#       --tag distroless \
#       --push-separately
#
#   # Build for amd64 only with custom registry
#   ./build-multiplatform.sh \
#       --registry quay.io/myorg \
#       --image cephaloproxy \
#       --platform linux/amd64 \
#       --load

set -e

# Default values
PLATFORM="linux/amd64,linux/arm64"
TAG="distroless"
PUSH=""
PUSH_SEPARATELY=""
LOAD=""
REGISTRY=""
IMAGE_NAME="cephaloproxy"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --push)
            PUSH="--push"
            shift
            ;;
        --push-separately)
            PUSH_SEPARATELY="true"
            shift
            ;;
        --load)
            LOAD="--load"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--registry REGISTRY] [--image IMAGE] [--platform PLATFORM] [--tag TAG] [--push] [--push-separately] [--load]"
            exit 1
            ;;
    esac
done

# Validate options
if [[ -n "$PUSH" && -n "$LOAD" ]]; then
    echo "Error: Cannot use --push and --load together"
    exit 1
fi

if [[ -n "$PUSH" && -n "$PUSH_SEPARATELY" ]]; then
    echo "Error: Cannot use --push and --push-separately together"
    echo "Use --push-separately for registries with custom CAs"
    exit 1
fi

if [[ -n "$LOAD" && "$PLATFORM" == *","* ]]; then
    echo "Error: --load only works with a single platform"
    echo "Current platform: $PLATFORM"
    exit 1
fi

if [[ -n "$PUSH" && -z "$REGISTRY" ]]; then
    echo "Error: --push requires --registry to be specified"
    echo "Example: --registry ghcr.io/opsreformation"
    exit 1
fi

if [[ -n "$PUSH_SEPARATELY" && -z "$REGISTRY" ]]; then
    echo "Error: --push-separately requires --registry to be specified"
    echo "Example: --registry quay.apps.roshar.cosmere.lan/opsreformation"
    exit 1
fi

# Construct full image name
if [[ -n "$REGISTRY" ]]; then
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${TAG}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"
fi

# Create buildx builder if it doesn't exist
if ! docker buildx ls | grep -q cephaloproxy-builder; then
    echo "Creating buildx builder: cephaloproxy-builder"
    docker buildx create --name cephaloproxy-builder --use
fi

# Ensure builder is running
docker buildx inspect --bootstrap

# Handle --push-separately (for registries with custom CAs)
if [[ -n "$PUSH_SEPARATELY" ]]; then
    echo "Building and pushing platforms separately (for custom CA registries)..."
    echo "Registry: ${REGISTRY}"
    echo "Image: ${IMAGE_NAME}:${TAG}"
    echo ""

    # Parse platforms into array
    IFS=',' read -ra PLATFORMS <<< "$PLATFORM"

    # Build and push each platform
    for platform in "${PLATFORMS[@]}"; do
        platform_clean=$(echo "$platform" | sed 's|linux/||')
        platform_tag="${FULL_IMAGE_NAME}-${platform_clean}"

        echo "Building for $platform..."
        docker buildx build \
            --platform "$platform" \
            --file container/Dockerfile.distroless \
            --tag "$platform_tag" \
            --load \
            .

        echo "Pushing $platform_tag..."
        docker push "$platform_tag"
        echo ""
    done

    # Create and push manifest list
    echo "Creating multi-platform manifest..."
    manifest_images=()
    for platform in "${PLATFORMS[@]}"; do
        platform_clean=$(echo "$platform" | sed 's|linux/||')
        manifest_images+=("${FULL_IMAGE_NAME}-${platform_clean}")
    done

    # Remove existing manifest if present (ignore errors if doesn't exist)
    docker manifest rm "${FULL_IMAGE_NAME}" 2>/dev/null || true

    docker manifest create "${FULL_IMAGE_NAME}" "${manifest_images[@]}"

    echo "Pushing manifest ${FULL_IMAGE_NAME}..."
    docker manifest push "${FULL_IMAGE_NAME}"

    echo ""
    echo "Build and push complete!"
    echo "Multi-platform image: ${FULL_IMAGE_NAME}"
    echo "Architectures: ${PLATFORM}"
    echo ""
    echo "Pull with: docker pull ${FULL_IMAGE_NAME}"

    exit 0
fi

# Standard buildx build (original behavior)
BUILD_CMD="docker buildx build \
    --platform $PLATFORM \
    --file container/Dockerfile.distroless \
    --tag ${FULL_IMAGE_NAME} \
    $PUSH \
    $LOAD \
    ."

echo "Building CephaloProxy distroless container..."
echo "Platform(s): $PLATFORM"
echo "Image: ${FULL_IMAGE_NAME}"
echo ""

# Execute build
eval "$BUILD_CMD"

echo ""
echo "Build complete!"

if [[ -n "$LOAD" ]]; then
    echo "Image loaded into local Docker: ${FULL_IMAGE_NAME}"
    echo "Run with: docker run --rm ${FULL_IMAGE_NAME}"
elif [[ -n "$PUSH" ]]; then
    echo "Image pushed to registry: ${FULL_IMAGE_NAME}"
    echo "Pull with: docker pull ${FULL_IMAGE_NAME}"
else
    echo "Image built but not loaded or pushed"
    echo "Use --load to load into local Docker or --push --registry <REGISTRY> to push to registry"
fi
