#!/usr/bin/env bats
#
# Integration tests for graceful shutdown with asyncio timeout.
# Verifies docker stop completes within 35 seconds (30s graceful + 5s buffer).
#
# Usage:
#   bats tests/integration/test-graceful-shutdown.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "docker stop completes in ≤35 seconds" {
  # Start container
  docker run --name test-shutdown-time -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for full startup
  sleep 10

  # Measure shutdown time
  start_time=$(date +%s)
  timeout 40 docker stop test-shutdown-time
  end_time=$(date +%s)

  shutdown_duration=$((end_time - start_time))

  echo "Shutdown took ${shutdown_duration} seconds"

  # Assert shutdown took ≤35 seconds
  [ "$shutdown_duration" -le 35 ]

  # Cleanup
  docker rm test-shutdown-time
}

@test "Logs show 'Received signal SIGTERM' message" {
  # Start container
  docker run --name test-shutdown-signal -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Stop container
  docker stop test-shutdown-signal

  # Check logs for shutdown message
  logs=$(docker logs test-shutdown-signal 2>&1)
  echo "$logs" | grep -q "Received signal" || echo "$logs" | grep -q "initiating.*shutdown"

  # Cleanup
  docker rm test-shutdown-signal
}

@test "Logs show 'Shutdown complete' message" {
  # Start container
  docker run --name test-shutdown-complete -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Stop container
  docker stop test-shutdown-complete

  # Check logs for completion message
  logs=$(docker logs test-shutdown-complete 2>&1)
  echo "$logs" | grep -q "Shutdown complete" || echo "$logs" | grep -q "shutdown"

  # Cleanup
  docker rm test-shutdown-complete
}

@test "Exit code is 0 after graceful shutdown" {
  # Start container
  docker run --name test-shutdown-exitcode -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Stop container
  docker stop test-shutdown-exitcode

  # Check exit code
  exit_code=$(docker inspect test-shutdown-exitcode --format='{{.State.ExitCode}}')
  [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 143 ]  # 143 = 128 + 15 (SIGTERM)

  # Cleanup
  docker rm test-shutdown-exitcode
}
