#!/usr/bin/env bash
# run_tests.sh - Convenience script to run vrecord tests

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NOCOLOR=$'\033[0m'

echo "${YELLOW}Running vrecord test suite...${NOCOLOR}"
echo

# Check if we have audio hardware available
if ! command -v pactl >/dev/null 2>&1 || ! pactl info >/dev/null 2>&1; then
  echo "${YELLOW}Warning: No PulseAudio detected, using mock audio${NOCOLOR}"
  export USE_MOCK_AUDIO=1
fi

# Run the tests
cd "$SCRIPT_DIR"
if ./tests/test_vrecord.sh "$@"; then
  echo
  echo "${GREEN}All tests passed!${NOCOLOR}"
  exit 0
else
  echo
  echo "${RED}Some tests failed!${NOCOLOR}"
  exit 1
fi
#fin