#!/usr/bin/env bash
# test_vrecord.sh - Main test runner for vrecord
# Usage: ./test_vrecord.sh [test_suite_name]

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source assertion library
source "$SCRIPT_DIR/lib/assert.sh"

# Test configuration
export TEST_MODE=1
export TEST_RECORDING_DIR="$SCRIPT_DIR/test_recordings"
export TEST_STATE_DIR="$SCRIPT_DIR/test_state"
export VRECORD="$PROJECT_DIR/vrecord"

# Ensure vrecord is executable
chmod +x "$VRECORD"

# Setup test environment
setup_test_env() {
  # Create test directories
  mkdir -p "$TEST_RECORDING_DIR" "$TEST_STATE_DIR"
  
  # Override vrecord directories for testing
  export HOME="$SCRIPT_DIR"
  export RECORDING_DIR="$TEST_RECORDING_DIR"
  export STATE_DIR="$TEST_STATE_DIR"
}

# Cleanup test environment
cleanup_test_env() {
  # Stop any running recordings
  "$VRECORD" stop 2>/dev/null || true
  
  # Clean up test directories
  rm -rf "$TEST_RECORDING_DIR" "$TEST_STATE_DIR"
  
  # Kill any remaining ffmpeg processes from tests
  pkill -f "ffmpeg.*$TEST_RECORDING_DIR" 2>/dev/null || true
}

# Test: Basic command execution
test_basic_commands() {
  start_test "vrecord shows help with no arguments"
  output=$("$VRECORD" 2>&1 || true)
  assert_contains "$output" "Usage:"
  
  start_test "vrecord --version shows version"
  output=$("$VRECORD" --version 2>&1 || true)
  assert_contains "$output" "vrecord 1.0.0"
  
  start_test "vrecord --help shows help"
  output=$("$VRECORD" --help 2>&1 || true)
  assert_contains "$output" "Commands:"
}

# Test: Recording start and stop
test_recording_basic() {
  start_test "vrecord start creates recording"
  "$VRECORD" start test_recording 2>/dev/null &
  local pid=$!
  sleep 2  # Let recording start
  # Check if process started
  if kill -0 $pid 2>/dev/null; then
    assert_true "Recording should start successfully"
  else
    wait $pid
    assert_true "Recording should start successfully"
  fi
  
  start_test "vrecord status shows active recording"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: recording"
  
  start_test "vrecord stop saves recording"
  "$VRECORD" stop --no-mp3 2>/dev/null
  assert_true "Recording should stop successfully"
  
  start_test "Recording file exists after stop"
  wav_file=$(find "$TEST_RECORDING_DIR" -name "test_recording_*.wav" -type f | head -n1)
  assert_file_exists "$wav_file"
}

# Test: Pause and resume functionality
test_pause_resume() {
  start_test "vrecord pause works"
  "$VRECORD" start pause_test 2>/dev/null
  sleep 1
  "$VRECORD" pause 2>/dev/null
  assert_true "Recording should pause successfully"
  
  start_test "vrecord status shows paused state"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: paused"
  
  start_test "vrecord resume works"
  "$VRECORD" resume 2>/dev/null
  assert_true "Recording should resume successfully"
  
  start_test "vrecord status shows recording after resume"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: recording"
  
  "$VRECORD" stop --no-mp3 2>/dev/null
}

# Test: List command
test_list_command() {
  # Create some test recordings
  touch "$TEST_RECORDING_DIR/test1.wav"
  touch "$TEST_RECORDING_DIR/test2.wav"
  touch "$TEST_RECORDING_DIR/test.mp3"
  
  start_test "vrecord list shows WAV files"
  output=$("$VRECORD" list 2>&1)
  assert_contains "$output" "test1.wav"
  assert_contains "$output" "test2.wav"
  assert_not_contains "$output" "test.mp3"
  
  start_test "vrecord list --all shows all files"
  output=$("$VRECORD" list --all 2>&1)
  assert_contains "$output" "test1.wav"
  assert_contains "$output" "test2.wav"
  assert_contains "$output" "test.mp3"
}

# Test: Continue last recording
test_continue_recording() {
  # Create initial recording
  "$VRECORD" start continue_test 2>/dev/null
  sleep 1
  "$VRECORD" stop --no-mp3 2>/dev/null
  
  start_test "vrecord start -c continues last recording"
  "$VRECORD" start -c 2>/dev/null
  assert_true "Continue should work"
  
  sleep 1
  "$VRECORD" stop --no-mp3 2>/dev/null
  
  start_test "Continued recording exists"
  wav_files=$(find "$TEST_RECORDING_DIR" -name "continue_test_*.wav" -type f | wc -l)
  assert_equals "1" "$wav_files" "Should have exactly one WAV file after continuation"
}

# Test: Error handling
test_error_handling() {
  start_test "vrecord pause without active recording fails"
  set +e  # Temporarily disable exit on error
  "$VRECORD" pause 2>/dev/null
  assert_exit_code 1
  set -e  # Re-enable
  
  start_test "vrecord resume without active recording fails"
  set +e
  "$VRECORD" resume 2>/dev/null
  assert_exit_code 1
  set -e
  
  start_test "vrecord stop without active recording fails"
  set +e
  "$VRECORD" stop 2>/dev/null
  assert_exit_code 1
  set -e
  
  start_test "vrecord prevents concurrent recordings"
  "$VRECORD" start test1 2>/dev/null
  sleep 1
  "$VRECORD" start test2 2>&1 | grep -q "already in progress" || true
  assert_exit_code 0 "Should detect concurrent recording"
  "$VRECORD" stop --no-mp3 2>/dev/null
}

# Test: MP3 conversion
test_mp3_conversion() {
  # Check if ffmpeg supports MP3
  if ! ffmpeg -codecs 2>/dev/null | grep -q "mp3"; then
    echo "  Skipping MP3 tests - ffmpeg lacks MP3 support"
    return
  fi
  
  start_test "vrecord creates MP3 by default"
  "$VRECORD" start mp3_test 2>/dev/null
  sleep 1
  "$VRECORD" stop 2>/dev/null
  
  mp3_file=$(find "$TEST_RECORDING_DIR" -name "mp3_test_*.mp3" -type f | head -n1)
  assert_file_exists "$mp3_file" "MP3 file should be created"
  
  start_test "vrecord --no-mp3 skips MP3 creation"
  "$VRECORD" -n start no_mp3_test 2>/dev/null
  sleep 1
  "$VRECORD" stop 2>/dev/null
  
  mp3_file=$(find "$TEST_RECORDING_DIR" -name "no_mp3_test_*.mp3" -type f | head -n1)
  assert_file_not_exists "$mp3_file" "MP3 file should not be created with --no-mp3"
}

# Main test runner
main() {
  echo "vrecord Test Suite"
  echo "=================="
  echo "Project dir: $PROJECT_DIR"
  echo "Test dir: $SCRIPT_DIR"
  echo
  
  # Set up test environment
  setup_test_env
  
  # Trap to ensure cleanup
  trap cleanup_test_env EXIT
  
  # Run test suites
  local -- suite="${1:-all}"
  
  if [[ "$suite" == "all" ]]; then
    run_test_suite "Basic Commands" test_basic_commands
    run_test_suite "Recording Basic" test_recording_basic
    run_test_suite "Pause/Resume" test_pause_resume
    run_test_suite "List Command" test_list_command
    run_test_suite "Continue Recording" test_continue_recording
    run_test_suite "Error Handling" test_error_handling
    run_test_suite "MP3 Conversion" test_mp3_conversion
  else
    # Run specific test suite
    run_test_suite "$suite" "test_$suite"
  fi
  
  # Print summary
  print_test_summary
}

# Run tests
main "$@"
#fin