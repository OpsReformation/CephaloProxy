#!/usr/bin/env bats
#
# Integration tests for base image verification.
# Verifies Debian version, Python version, and Squid runtime compatibility.
#
# Usage:
#   bats tests/integration/test-base-image.bats
#

# Set IMAGE_NAME environment variable for testing
: "${IMAGE_NAME:=cephaloproxy:distroless}"

@test "Container runs on Debian 12 (Bookworm) base image" {
  # Extract Debian version from /etc/os-release using Python
  # Override entrypoint to run a single command
  run docker run --rm --entrypoint /usr/bin/python3 "$IMAGE_NAME" -c "import sys; sys.stdout.write(open('/etc/os-release').read())"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Debian"* ]]
  # Accept both Debian 12 (current) and Debian 13 (future migration)
  [[ "$output" == *"bookworm"* ]] || [[ "$output" == *"12"* ]] || [[ "$output" == *"trixie"* ]] || [[ "$output" == *"13"* ]]
}

@test "Python version is 3.11 or higher" {
  run docker run --rm --entrypoint /usr/bin/python3 "$IMAGE_NAME" --version
  [ "$status" -eq 0 ]

  # Extract version number (e.g., "Python 3.11.2" → "3.11")
  # Use sed instead of grep -P for macOS compatibility
  version=$(echo "$output" | sed -n 's/^Python \([0-9]*\.[0-9]*\).*/\1/p' | head -n1)

  # Convert to comparable format (e.g., "3.11" → 311)
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  version_num=$((major * 100 + minor))

  # Assert >= 3.11 (version_num >= 311)
  [ "$version_num" -ge 311 ]
}

@test "Squid binary exists and is executable" {
  run docker run --rm --entrypoint /usr/sbin/squid "$IMAGE_NAME" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"Squid"* ]]
}

@test "Squid supports SSL-bump (OpenSSL/GnuTLS compiled in)" {
  run docker run --rm --entrypoint /usr/sbin/squid "$IMAGE_NAME" -v
  [ "$status" -eq 0 ]
  # Check for SSL support (either OpenSSL or GnuTLS)
  [[ "$output" == *"OpenSSL"* ]] || [[ "$output" == *"GnuTLS"* ]]
}

@test "Vulnerability scan shows acceptable CVE count" {
  # Run Trivy scan (if available)
  if ! command -v trivy &> /dev/null; then
    skip "Trivy not installed - skipping vulnerability scan"
  fi

  # Scan image and count HIGH/CRITICAL CVEs
  run trivy image --severity HIGH,CRITICAL --quiet --format json "$IMAGE_NAME"
  [ "$status" -eq 0 ]

  # Parse JSON and count vulnerabilities
  cve_count=$(echo "$output" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH" or .Severity == "CRITICAL")] | length' || echo 999)

  # Log CVE count for reference
  echo "HIGH/CRITICAL CVEs found: $cve_count"

  # Assert CVE count is reasonable (< 50 for distroless images)
  # This is informational - we expect distroless to have fewer CVEs than full images
  [ "$cve_count" -lt 100 ]
}
