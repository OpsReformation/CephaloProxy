#!/usr/bin/env bats
#
# Integration tests for shell absence in distroless container.
# These tests verify that NO shell binaries are present in the runtime image.
#
# Usage:
#   bats tests/integration/test-shell-absence.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "Container does not include /bin/sh" {
  # Use Python to check if /bin/sh exists
  run docker run --rm --entrypoint /usr/bin/python3 "$IMAGE_NAME" -c "import os; os.stat('/bin/sh')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No such file"* ]] || [[ "$output" == *"FileNotFoundError"* ]]
}

@test "Container does not include /bin/bash" {
  # Use Python to check if /bin/bash exists
  run docker run --rm --entrypoint /usr/bin/python3 "$IMAGE_NAME" -c "import os; os.stat('/bin/bash')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No such file"* ]] || [[ "$output" == *"FileNotFoundError"* ]]
}

@test "docker exec /bin/sh fails with 'no such file or directory'" {
  # Start container in background
  docker run --name test-shell-sh -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for container to be ready
  sleep 5

  # Attempt to exec /bin/sh - should fail
  run docker exec test-shell-sh /bin/sh 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such file or directory"* ]] || [[ "$output" == *"executable file not found"* ]]

  # Cleanup
  docker rm -f test-shell-sh
}

@test "docker exec sh (without path) fails" {
  # Start container in background
  docker run --name test-shell-bare -d "$IMAGE_NAME" || skip "Container failed to start"

  # Wait for container to be ready
  sleep 5

  # Attempt to exec sh without path - should fail
  run docker exec test-shell-bare sh 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"no such file"* ]]

  # Cleanup
  docker rm -f test-shell-bare
}

@test "Image scan confirms zero shell binaries (sh, bash, dash, zsh)" {
  # Extract filesystem to temporary directory
  temp_dir=$(mktemp -d)
  container_id=$(docker create "$IMAGE_NAME")

  docker export "$container_id" | tar -C "$temp_dir" -xf - 2>/dev/null || true
  docker rm "$container_id"

  # Search for shell binaries
  shells_found=0
  for shell in sh bash dash zsh busybox; do
    if find "$temp_dir" -name "$shell" -type f 2>/dev/null | grep -q .; then
      shells_found=$((shells_found + 1))
      echo "Found shell binary: $shell"
    fi
  done

  # Cleanup
  rm -rf "$temp_dir"

  # Assert no shells found
  [ "$shells_found" -eq 0 ]
}
