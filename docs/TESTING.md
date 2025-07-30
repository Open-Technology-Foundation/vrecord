# Testing Guide for vrecord

This document describes how to run and write tests for vrecord.

## Running Tests

### Quick Start

```bash
# Run all tests
./run_tests.sh

# Run specific test suite
./run_tests.sh recording_basic
```

### Direct Test Execution

```bash
# Run tests directly
cd tests
./test_vrecord.sh

# Run specific test suite
./test_vrecord.sh pause_resume
```

### Test Suites Available

- `basic_commands` - Tests help, version, and basic command parsing
- `recording_basic` - Tests start/stop functionality
- `pause_resume` - Tests pause and resume features
- `list_command` - Tests listing recordings
- `continue_recording` - Tests continuation of existing recordings
- `error_handling` - Tests error conditions and validation
- `mp3_conversion` - Tests MP3 conversion functionality

## Test Environment

Tests run in an isolated environment:
- Custom `HOME` directory under `tests/`
- Separate recording and state directories
- Mock audio support for CI environments
- Automatic cleanup after tests

### Mock Audio

If PulseAudio is not available, tests will use mock audio functions to simulate recording. This allows tests to run in CI/CD environments without audio hardware.

## Writing Tests

### Test Structure

```bash
test_my_feature() {
  start_test "Description of what we're testing"
  
  # Run command
  "$VRECORD" some-command
  
  # Make assertion
  assert_true "Command should succeed"
  
  # More complex assertion
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "expected text"
}
```

### Available Assertions

The test framework provides these assertion functions:

- `assert_equals expected actual [message]` - Check equality
- `assert_not_equals not_expected actual [message]` - Check inequality
- `assert_true [message]` - Check last command succeeded (exit 0)
- `assert_false [message]` - Check last command failed (exit non-zero)
- `assert_file_exists file [message]` - Check file exists
- `assert_file_not_exists file [message]` - Check file doesn't exist
- `assert_directory_exists dir [message]` - Check directory exists
- `assert_contains haystack needle [message]` - Check string contains substring
- `assert_not_contains haystack needle [message]` - Check string doesn't contain substring
- `assert_process_running pid [message]` - Check process is running
- `assert_process_not_running pid [message]` - Check process is not running
- `assert_exit_code expected [message]` - Check specific exit code

### Adding New Test Suites

1. Add a new function in `test_vrecord.sh`:
   ```bash
   test_my_new_feature() {
     start_test "First test case"
     # test code here
     assert_true "Should work"
     
     start_test "Second test case"
     # more test code
     assert_equals "expected" "$actual"
   }
   ```

2. Add to the main test runner:
   ```bash
   if [[ "$suite" == "all" ]]; then
     # ... existing suites ...
     run_test_suite "My New Feature" test_my_new_feature
   ```

### Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Always stop recordings in tests
3. **Descriptive names**: Use clear test descriptions
4. **Fast execution**: Keep tests quick (use short delays)
5. **Error paths**: Test both success and failure cases

## Continuous Integration

The test suite is designed to work in CI environments:

```yaml
# Example GitHub Actions workflow
- name: Run tests
  run: |
    sudo apt-get update
    sudo apt-get install -y ffmpeg
    ./run_tests.sh
```

## Debugging Failed Tests

1. **Check logs**: Test output shows which assertion failed
2. **Run individually**: Isolate failing test suite
3. **Add debug output**: Use `echo` statements in tests
4. **Check test environment**: Verify directories exist
5. **Manual testing**: Run vrecord commands manually

## Coverage Goals

Current test coverage includes:
- ✓ Basic command execution
- ✓ Recording lifecycle (start/stop)
- ✓ Pause/resume functionality
- ✓ File listing
- ✓ Recording continuation
- ✓ Error handling
- ✓ MP3 conversion

Future coverage goals:
- [ ] Configuration file loading
- [ ] Log rotation
- [ ] Signal handling
- [ ] Concurrent recording prevention
- [ ] Disk space checks