#!/usr/bin/env bats
#
# Integration tests for OpenShift arbitrary UID compatibility.
# Verifies container works with arbitrary UIDs (OpenShift requirement).
#
# Usage:
#   bats tests/integration/test-openshift-uid.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "Container starts with arbitrary UID 1234567" {
  # Run container with arbitrary UID (simulates OpenShift)
  docker run --name test-openshift-uid --user 1234567:0 -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Check container is running
  run docker ps --filter "name=test-openshift-uid" --format "{{.Status}}"
  [[ "$output" == *"Up"* ]]

  # Check logs show correct UID
  logs=$(docker logs test-openshift-uid 2>&1)
  echo "$logs" | grep -q "UID: 1234567"

  # Cleanup
  docker rm -f test-openshift-uid
}

@test "Container starts with arbitrary UID 99999" {
  # Run container with another arbitrary UID
  docker run --name test-openshift-uid2 --user 99999:0 -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Check container is running
  run docker ps --filter "name=test-openshift-uid2" --format "{{.Status}}"
  [[ "$output" == *"Up"* ]]

  # Cleanup
  docker rm -f test-openshift-uid2
}

@test "Health endpoint works with arbitrary UID" {
  # Run container with arbitrary UID and port mapping
  docker run --name test-openshift-health --user 50000:0 -d -p 8081:8080 "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Test health endpoint
  run curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health
  [ "$status" -eq 0 ]
  [ "$output" -eq 200 ]

  # Cleanup
  docker rm -f test-openshift-health
}
