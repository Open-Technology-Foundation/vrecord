#!/usr/bin/env bash
#shellcheck disable=SC2016,SC2034,SC2181
# assert.sh - Simple assertion library for bash testing
# Part of vrecord test suite
#
# ShellCheck disable notes:
# - SC2016: Default messages use single quotes intentionally (templates)
# - SC2034: CURRENT_TEST used by test framework for context
# - SC2181: $? anti-pattern is intentional for assertion functions

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Color output for test results
declare -- TEST_RED='' TEST_GREEN='' TEST_YELLOW='' TEST_NOCOLOR=''
[[ -t 1 ]] && declare -r TEST_RED=$'\033[0;31m' TEST_GREEN=$'\033[0;32m' TEST_YELLOW=$'\033[0;33m' TEST_NOCOLOR=$'\033[0m'

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# Test context
declare -- CURRENT_TEST=""

# start_test: Begin a new test
start_test() {
  local -- test_name="$1"
  CURRENT_TEST="$test_name"
  ((TESTS_RUN+=1))
  printf "  Testing: %s ... " "$test_name"
}

# pass: Mark current test as passed
pass() {
  ((TESTS_PASSED+=1))
  printf "%sPASS%s\n" "$TEST_GREEN" "$TEST_NOCOLOR"
}

# fail: Mark current test as failed with message
fail() {
  local -- message="${1:-Assertion failed}"
  ((TESTS_FAILED+=1))
  printf "%sFAIL%s\n" "$TEST_RED" "$TEST_NOCOLOR"
  printf "    Error: %s\n" "$message"
}

# assert_equals: Check if two values are equal
assert_equals() {
  local -- expected="$1"
  local -- actual="$2"
  local -- message="${3:-Expected '$expected' but got '$actual'}"
  
  if [[ "$expected" == "$actual" ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_not_equals: Check if two values are not equal
assert_not_equals() {
  local -- not_expected="$1"
  local -- actual="$2"
  local -- message="${3:-Expected value to not be '$not_expected'}"
  
  if [[ "$not_expected" != "$actual" ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_true: Check if condition is true (exit code 0)
assert_true() {
  local -- message="${1:-Condition should be true}"
  
  if [[ $? -eq 0 ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_false: Check if condition is false (exit code non-zero)
assert_false() {
  local -- message="${1:-Condition should be false}"
  
  if [[ $? -ne 0 ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_file_exists: Check if file exists
assert_file_exists() {
  local -- file="$1"
  local -- message="${2:-File '$file' should exist}"
  
  if [[ -f "$file" ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_file_not_exists: Check if file does not exist
assert_file_not_exists() {
  local -- file="$1"
  local -- message="${2:-File '$file' should not exist}"
  
  if [[ ! -f "$file" ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_directory_exists: Check if directory exists
assert_directory_exists() {
  local -- dir="$1"
  local -- message="${2:-Directory '$dir' should exist}"
  
  if [[ -d "$dir" ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_contains: Check if string contains substring
assert_contains() {
  local -- haystack="$1"
  local -- needle="$2"
  local -- message="${3:-String should contain '$needle'}"
  
  if [[ "$haystack" == *"$needle"* ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_not_contains: Check if string does not contain substring
assert_not_contains() {
  local -- haystack="$1"
  local -- needle="$2"
  local -- message="${3:-String should not contain '$needle'}"
  
  if [[ "$haystack" != *"$needle"* ]]; then
    pass
  else
    fail "$message"
  fi
}

# assert_process_running: Check if process with PID is running
assert_process_running() {
  local -- pid="$1"
  local -- message="${2:-Process $pid should be running}"
  
  if kill -0 "$pid" 2>/dev/null; then
    pass
  else
    fail "$message"
  fi
}

# assert_process_not_running: Check if process with PID is not running
assert_process_not_running() {
  local -- pid="$1"
  local -- message="${2:-Process $pid should not be running}"
  
  if ! kill -0 "$pid" 2>/dev/null; then
    pass
  else
    fail "$message"
  fi
}

# assert_exit_code: Check last command exit code
# NOTE: Must capture $? before any local declarations (local resets $?)
assert_exit_code() {
  local -i actual_code=$?
  local -i expected_code="$1"
  local -- message="${2:-Expected exit code $expected_code but got $actual_code}"

  if ((actual_code == expected_code)); then
    pass
  else
    fail "$message"
  fi
}

# print_test_summary: Display test results summary
print_test_summary() {
  echo
  echo "Test Summary:"
  echo "============="
  printf "Total tests: %d\n" "$TESTS_RUN"
  printf "%sPassed: %d%s\n" "$TEST_GREEN" "$TESTS_PASSED" "$TEST_NOCOLOR"
  if ((TESTS_FAILED > 0)); then
    printf "%sFailed: %d%s\n" "$TEST_RED" "$TESTS_FAILED" "$TEST_NOCOLOR"
  fi
  echo
  
  if ((TESTS_FAILED > 0)); then
    return 1
  else
    return 0
  fi
}

# run_test_suite: Execute a test suite function
run_test_suite() {
  local -- suite_name="$1"
  local -- suite_function="$2"
  
  printf "\n%sRunning test suite: %s%s\n" "$TEST_YELLOW" "$suite_name" "$TEST_NOCOLOR"
  printf "=====================================\n"
  
  # Run the test suite
  "$suite_function"
}

#fin