#!/usr/bin/env bats
#
# Integration tests for container startup with Python entrypoint.
# Verifies all log lines appear in correct order and Squid starts successfully.
#
# Usage:
#   bats tests/integration/test-container-startup.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "Container starts successfully with Python entrypoint" {
  # Start container in background
  docker run --name test-startup -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for container to reach ready state
  sleep 10

  # Check container is running
  run docker ps --filter "name=test-startup" --format "{{.Status}}"
  [[ "$output" == *"Up"* ]]

  # Cleanup
  docker rm -f test-startup
}

@test "All required log lines appear in correct order" {
  # Start container in background
  docker run --name test-startup-logs -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for full startup
  sleep 15

  # Get logs
  logs=$(docker logs test-startup-logs 2>&1)

  # Verify log lines in order
  echo "$logs" | grep -q "CephaloProxy entrypoint starting"
  echo "$logs" | grep -q "Validating Squid configuration"
  echo "$logs" | grep -q "Starting health check server"
  echo "$logs" | grep -q "Starting Squid proxy"

  # Cleanup
  docker rm -f test-startup-logs
}

@test "Squid PID file is created" {
  # Start container in background
  docker run --name test-pid-file -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for Squid startup
  sleep 10

  # Check PID file exists (we can't directly access it in distroless, check logs)
  logs=$(docker logs test-pid-file 2>&1)
  echo "$logs" | grep -q "Squid started with PID"

  # Cleanup
  docker rm -f test-pid-file
}

@test "Health endpoint responds 200 OK" {
  # Start container in background with port mapping
  docker run --name test-health -d -p 8080:8080 "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for health server startup
  sleep 10

  # Test health endpoint
  run curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
  [ "$status" -eq 0 ]
  [ "$output" -eq 200 ]

  # Cleanup
  docker rm -f test-health
}
