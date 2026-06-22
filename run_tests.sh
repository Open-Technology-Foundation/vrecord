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

# vrecord's recording tests drive a real ffmpeg/PulseAudio capture, so a live
# audio server is required (there is no mock backend).
if ! command -v pactl >/dev/null 2>&1 || ! pactl info >/dev/null 2>&1; then
  echo "${RED}Error: no PulseAudio/PipeWire-Pulse server detected.${NOCOLOR}" >&2
  echo "The vrecord test suite needs a live audio server; aborting." >&2
  exit 18  # ERR_NODEP
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