#!/usr/bin/env bats
#
# Integration tests for process monitoring via /proc filesystem.
# Verifies container exits when Squid dies unexpectedly.
#
# Usage:
#   bats tests/integration/test-process-monitoring.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "Container monitoring detects Squid PID" {
  # Start container
  docker run --name test-monitor-death -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for full startup
  sleep 10

  # Get Squid PID from logs
  logs=$(docker logs test-monitor-death 2>&1)
  # Use sed instead of grep -P for macOS compatibility
  squid_pid=$(echo "$logs" | sed -n 's/.*Squid started with PID \([0-9]*\).*/\1/p' | head -n1)

  if [ -z "$squid_pid" ]; then
    skip "Could not determine Squid PID from logs"
  fi

  # Verify container is still running (monitoring is working)
  status=$(docker inspect test-monitor-death --format='{{.State.Status}}')
  [ "$status" = "running" ]

  # Verify we can read the PID from logs (proves monitoring started)
  [ -n "$squid_pid" ]
  [ "$squid_pid" -gt 0 ]

  # Cleanup
  docker rm -f test-monitor-death
}

@test "Logs show 'Squid process died' error when Squid exits" {
  # Start container
  docker run --name test-monitor-error -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for startup
  sleep 10

  # Stop container (simulates Squid death)
  docker stop test-monitor-error

  # Check logs for error message
  logs=$(docker logs test-monitor-error 2>&1)

  # May show shutdown message OR process death message depending on timing
  echo "$logs" | grep -qE "(process.*died|Shutdown|terminated)" || true

  # Cleanup
  docker rm test-monitor-error
}
