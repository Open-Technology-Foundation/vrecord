#!/usr/bin/env bash
# test_vrecord.sh - Main test runner for vrecord
# Usage: ./test_vrecord.sh [test_suite_name]

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source assertion library
declare -- lib
for lib in assert.sh stubs.sh; do
  [[ -f "$SCRIPT_DIR/lib/$lib" ]] || { >&2 echo "Missing test library: $SCRIPT_DIR/lib/$lib"; exit 3; }
done
# shellcheck source=tests/lib/assert.sh
source -- "$SCRIPT_DIR/lib/assert.sh"
# shellcheck source=tests/lib/stubs.sh
source -- "$SCRIPT_DIR/lib/stubs.sh"

# Test configuration
export TEST_MODE=1
export TEST_RECORDING_DIR="$SCRIPT_DIR/test_recordings"
export TEST_STATE_DIR="$SCRIPT_DIR/test_state"
export VRECORD="$PROJECT_DIR/vrecord"
declare -- TEST_TMP_DIR=''  # run-private temp dir, created by setup_test_env

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

  # Run-private temp dir: stub homes (make_stub_home) and other mktemp dirs
  # land here, so the EXIT trap removes them even when a test aborts
  TEST_TMP_DIR=$(mktemp -d -t vrecord-tests.XXXXXX)
  export TMPDIR="$TEST_TMP_DIR"
}

# Cleanup test environment
cleanup_test_env() {
  # Stop any running test recording -- only once setup has pointed vrecord at
  # the test dirs; before that, 'stop' would act on the user's real session
  if [[ "${STATE_DIR:-}" == "$TEST_STATE_DIR" ]]; then
    "$VRECORD" stop >/dev/null 2>&1 || true
  fi

  # Clean up test directories
  rm -rf "$TEST_RECORDING_DIR" "$TEST_STATE_DIR"

  # Kill any remaining ffmpeg processes from tests
  pkill -f "ffmpeg.*$TEST_RECORDING_DIR" 2>/dev/null || true

  # Stub recorders and temp dirs left by an aborted stub test
  if [[ -n "${TEST_TMP_DIR:-}" ]]; then
    pkill -f "$TEST_TMP_DIR/" 2>/dev/null || true
    rm -rf -- "$TEST_TMP_DIR"
  fi
}

# Test: Basic command execution
test_basic_commands() {
  start_test "vrecord shows help with no arguments"
  output=$("$VRECORD" 2>&1 || true)
  assert_contains "$output" "Usage:"
  
  start_test "vrecord --version shows version"
  output=$("$VRECORD" --version 2>&1 || true)
  assert_contains "$output" "vrecord 1.2.0"
  
  start_test "vrecord --help shows help"
  output=$("$VRECORD" --help 2>&1 || true)
  assert_contains "$output" "Commands:"
}

# Test: Recording start and stop
test_recording_basic() {
  start_test "vrecord start creates recording"
  assert_success "vrecord start should exit cleanly" "$VRECORD" start test_recording
  sleep 1  # let ffmpeg spin up before the status check below
  
  start_test "vrecord status shows active recording"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: recording"
  
  start_test "vrecord stop saves recording"
  assert_success "vrecord stop should exit cleanly" "$VRECORD" stop --no-mp3
  
  start_test "Recording file exists after stop"
  wav_file=$(find "$TEST_RECORDING_DIR" -name "test_recording_*.wav" -type f | head -n1)
  assert_file_exists "$wav_file"
}

# Test: Pause and resume functionality
test_pause_resume() {
  start_test "vrecord pause works"
  "$VRECORD" start pause_test 2>/dev/null
  sleep 1
  assert_success "vrecord pause should exit cleanly" "$VRECORD" pause
  
  start_test "vrecord status shows paused state"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: paused"
  
  start_test "vrecord resume works"
  assert_success "vrecord resume should exit cleanly" "$VRECORD" resume
  
  start_test "vrecord status shows recording after resume"
  output=$("$VRECORD" status 2>&1)
  assert_contains "$output" "Recording Status: recording"
  
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1
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
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1
  
  start_test "vrecord start -c continues last recording"
  assert_success "vrecord start -c should exit cleanly" "$VRECORD" start -c
  
  sleep 1
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1
  
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
  "$VRECORD" stop >/dev/null 2>&1
  assert_exit_code 1
  set -e
  
  start_test "vrecord prevents concurrent recordings"
  "$VRECORD" start test1 2>/dev/null
  sleep 1
  set +e
  output=$("$VRECORD" start test2 2>&1)
  set -e
  assert_contains "$output" "already in progress" \
    "A second concurrent start must be rejected with 'already in progress'"
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1
}

# Test: MP3 conversion
test_mp3_conversion() {
  # Check if ffmpeg has the MP3 encoder vrecord uses. Capture first: piping
  # into 'grep -q' kills ffmpeg with SIGPIPE, and pipefail turned that into
  # a false "lacks MP3 support" that silently skipped this suite.
  local -- encoders
  encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null) || encoders=''
  if [[ "$encoders" != *libmp3lame* ]]; then
    echo "  Skipping MP3 tests - ffmpeg lacks libmp3lame"
    return
  fi
  
  start_test "vrecord creates MP3 by default"
  "$VRECORD" start mp3_test 2>/dev/null
  sleep 1
  "$VRECORD" stop >/dev/null 2>&1
  
  mp3_file=$(find "$TEST_RECORDING_DIR" -name "mp3_test_*.mp3" -type f | head -n1)
  assert_file_exists "$mp3_file" "MP3 file should be created"
  
  start_test "vrecord --no-mp3 skips MP3 creation"
  "$VRECORD" -n start no_mp3_test 2>/dev/null
  sleep 1
  "$VRECORD" stop >/dev/null 2>&1
  
  mp3_file=$(find "$TEST_RECORDING_DIR" -name "no_mp3_test_*.mp3" -type f | head -n1)
  assert_file_not_exists "$mp3_file" "MP3 file should not be created with --no-mp3"
}

# Test: play command (resolution + invocation, via a mocked xdg-open)
test_play() {
  # vrecord locks PATH to "$HOME/.local/bin:..." so a mock placed there wins.
  local -- ph xdg_log
  ph=$(mktemp -d)
  mkdir -p "$ph/.local/bin"
  xdg_log="$ph/xdg.log"
  cat > "$ph/.local/bin/xdg-open" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$1" > "$xdg_log"
MOCK
  chmod +x "$ph/.local/bin/xdg-open"

  start_test "vrecord play <name> resolves to RECORDING_DIR and appends .wav"
  touch "$TEST_RECORDING_DIR/playtest.wav"
  HOME="$ph" "$VRECORD" play playtest 2>/dev/null
  assert_equals "$TEST_RECORDING_DIR/playtest.wav" "$(cat "$xdg_log" 2>/dev/null || true)" \
    "play should open the resolved .wav file"

  start_test "vrecord play with no argument plays the most recent recording"
  : > "$xdg_log"
  sleep 1
  touch "$TEST_RECORDING_DIR/playnewer.wav"
  HOME="$ph" "$VRECORD" play 2>/dev/null
  assert_equals "$TEST_RECORDING_DIR/playnewer.wav" "$(cat "$xdg_log" 2>/dev/null || true)" \
    "no-arg play should open the most recent WAV"

  start_test "vrecord play with a missing file fails"
  set +e
  HOME="$ph" "$VRECORD" play no_such_recording 2>/dev/null
  assert_exit_code 1
  set -e

  rm -rf "$ph"
}

# Test: a pause must not end up in the recording (real ffmpeg + live audio).
# A SIGSTOP-based pause let the audio server buffer the paused span (~24 s)
# and hand it over on resume, so short pauses were recorded in full.
test_pause_audio() {
  local -- wav dur

  start_test "stop after pause/resume succeeds"
  "$VRECORD" -b start pause_audio 2>/dev/null
  sleep 2
  "$VRECORD" pause 2>/dev/null
  sleep 6
  "$VRECORD" resume 2>/dev/null
  sleep 2
  assert_success "stop should exit cleanly" "$VRECORD" stop --no-mp3

  wav=$(find -- "$TEST_RECORDING_DIR" -name 'pause_audio_*.wav' -type f)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$wav" 2>/dev/null) || dur=0
  start_test "recording holds only unpaused time (got ${dur}s, want 3-7s)"
  assert_success "paused audio must not be recorded" \
    awk -v d="$dur" 'BEGIN { exit !(d >= 3 && d <= 7) }'

  start_test "resume then immediate pause, stop while paused: WAV and MP3 saved"
  "$VRECORD" -b start pause_quick 2>/dev/null
  sleep 1
  "$VRECORD" pause 2>/dev/null
  "$VRECORD" resume 2>/dev/null
  "$VRECORD" pause 2>/dev/null
  assert_success "stop while paused should exit cleanly" "$VRECORD" stop
  wav=$(find -- "$TEST_RECORDING_DIR" -name 'pause_quick_*.wav' -type f)
  assert_file_exists "${wav%.wav}.mp3" "stop while paused must still create the MP3"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$wav" 2>/dev/null) || dur=0
  assert_success "merged WAV must be readable with audio (got ${dur}s)" \
    awk -v d="$dur" 'BEGIN { exit !(d >= 1) }'
}

# Test: pause/resume bookkeeping, with stub tools (no audio device)
test_pause_segments() {
  local -- sh wav first second
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "pause/resume records a second segment and stop merges both"
  "$VRECORD" start seg >/dev/null 2>&1
  first=$(capture_pid)
  "$VRECORD" pause >/dev/null 2>&1
  "$VRECORD" resume >/dev/null 2>&1
  second=$(capture_pid)
  "$VRECORD" -n stop >/dev/null 2>&1
  wav=$(find -- "$RECORDING_DIR" -name 'seg_*.wav' -type f)
  assert_contains "$(cat -- "$wav")" ":$first" "audio before the pause must be kept"
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "audio after resume must be recorded as a new segment and merged"

  start_test "merging keeps the recording's permissions"
  "$VRECORD" start perm >/dev/null 2>&1
  "$VRECORD" pause >/dev/null 2>&1
  wav=$(find -- "$RECORDING_DIR" -name 'perm_*.wav' -type f)
  chmod 640 -- "$wav"
  "$VRECORD" resume >/dev/null 2>&1
  "$VRECORD" -n stop >/dev/null 2>&1
  assert_equals 640 "$(stat -c %a -- "$wav")" "merge must not change the file mode"

  start_test "start is refused while a recording is paused"
  "$VRECORD" start held >/dev/null 2>&1
  "$VRECORD" pause >/dev/null 2>&1
  assert_failure "start must not replace a paused session" "$VRECORD" start other
  start_test "status reports the paused session"
  assert_contains "$("$VRECORD" status 2>&1)" "Recording Status: paused"

  start_test "stop while paused converts to MP3 and transcribes"
  "$VRECORD" resume >/dev/null 2>&1
  "$VRECORD" pause >/dev/null 2>&1
  "$VRECORD" stop -t >/dev/null 2>&1
  wav=$(find -- "$RECORDING_DIR" -name 'held_*.wav' -type f)
  assert_file_exists "${wav%.wav}.mp3" "MP3 must be created when stopping a paused session"
  assert_file_exists "${wav%.wav}.txt" "transcript must be created when stopping a paused session"

  start_test "a failed resume leaves the session paused and intact"
  "$VRECORD" start fr >/dev/null 2>&1
  first=$(capture_pid)
  "$VRECORD" pause >/dev/null 2>&1
  assert_failure "resume must report the failure" env STUB_FAIL=capture "$VRECORD" resume
  assert_contains "$("$VRECORD" status 2>&1)" "Recording Status: paused"
  "$VRECORD" resume >/dev/null 2>&1
  second=$(capture_pid)
  "$VRECORD" -n stop >/dev/null 2>&1
  wav=$(find -- "$RECORDING_DIR" -name 'fr_*.wav' -type f)
  assert_contains "$(cat -- "$wav")" ":$first" "audio before the pause must be kept"
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "the next successful resume must record segment 1 and be merged"

  drop_stub_home "$sh"
}

# Test: an interrupted session (ffmpeg crashed mid-recording) keeps its audio
# until 'stop' merges it, whatever is run in between (stub tools)
test_session_recovery() {
  local -- sh base crashed how out seg_dir
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  "$VRECORD" start base >/dev/null 2>&1
  "$VRECORD" -n stop >/dev/null 2>&1
  base=$(find -- "$RECORDING_DIR" -name 'base_*.wav' -type f)

  start_test "status leaves an interrupted continuation's audio intact"
  "$VRECORD" start -c >/dev/null 2>&1
  crashed=$(capture_pid)
  crash_capture
  "$VRECORD" status >/dev/null 2>&1 || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "stop after status must merge the continuation recorded before the crash"

  start_test "status reports an interrupted session and how to save it"
  "$VRECORD" start -c >/dev/null 2>&1
  crashed=$(capture_pid)
  crash_capture
  assert_contains "$("$VRECORD" status 2>&1)" "stop"

  start_test "start refuses to replace an interrupted session"
  assert_failure "a new start must not discard the interrupted session" "$VRECORD" start other
  assert_failure "start -c must not reuse the interrupted session" "$VRECORD" start -c
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "the interrupted continuation must still be merged by stop"

  start_test "stop never deletes segments it could not merge (paused, then interrupted)"
  for how in pause crash; do
    "$VRECORD" start -c >/dev/null 2>&1
    if [[ $how == pause ]]; then "$VRECORD" pause >/dev/null 2>&1; else crash_capture; fi
    : > "$STATE_DIR"/session/main_file   # simulate a damaged session record
    out=$("$VRECORD" -n stop 2>&1) || true
    seg_dir=$(sed -n 's/.*Segments preserved in: //p' <<<"$out")
    assert_file_exists "$seg_dir/segment_1.wav" \
      "$how: unmerged segments must be preserved (reported: '$seg_dir')"
  done

  start_test "a failed start leaves no session behind"
  assert_failure "start must report the failure" env STUB_FAIL=capture "$VRECORD" start broken
  assert_contains "$("$VRECORD" status 2>&1)" "No active recording"
  assert_success "the next start must work" "$VRECORD" start fine
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  drop_stub_home "$sh"
}

# Test: 'stop' reports the saved recording on stdout, and vrecord-loop shows
# and forwards only that recording's transcript (stub tools; real scripts)
test_loop() {
  local -- sh bin wd out wav tmpl
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  # vrecord-loop finds vrecord on PATH: make it this checkout, not an installed copy
  bin=$sh/bin
  wd=$sh/cwd
  mkdir -p -- "$bin" "$wd"
  ln -s -- "$VRECORD" "$bin"/vrecord
  local -x PATH="$bin:$PATH"

  start_test "stop prints only the saved WAV path on stdout"
  "$VRECORD" start -t out >/dev/null 2>&1
  out=$("$VRECORD" -q stop 2>/dev/null)
  wav=$(find -- "$RECORDING_DIR" -name 'out_*.wav' -type f)
  assert_equals "$wav" "$out"

  start_test "loop shows this recording's transcript and pipes it to CALL_APP"
  out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C "tee $sh/received" 2>&1)
  assert_contains "$out" "TRANSCRIPT of voice_"
  assert_contains "$(cat -- "$sh"/received 2>/dev/null || true)" "TRANSCRIPT of voice_"

  start_test "loop does not show an older transcript when transcription fails"
  rm -f -- "$RECORDING_DIR"/*.txt
  echo 'OLD TRANSCRIPT' > "$RECORDING_DIR"/voice_20200101_000000.txt
  out=$(cd -- "$wd" && printf q | STUB_TRANSCRIBE_FAIL=1 "$PROJECT_DIR"/vrecord-loop 2>&1)
  assert_not_contains "$out" "OLD TRANSCRIPT"

  start_test "loop does not show unrelated files from the current directory"
  rm -f -- "$RECORDING_DIR"/*.txt
  echo 'UNRELATED FILE' > "$wd"/notes.txt
  out=$(cd -- "$wd" && printf q | STUB_TRANSCRIBE_FAIL=1 "$PROJECT_DIR"/vrecord-loop 2>&1)
  assert_not_contains "$out" "UNRELATED FILE"

  start_test "CALL_APP {{FILE}} receives the path as data, never as shell code"
  RECORDING_DIR="$sh/rec \$(touch PWNED)"
  for tmpl in 'wc -c {{FILE}}' 'wc -c "{{FILE}}"'; do
    out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C "$tmpl" 2>&1)
    assert_file_not_exists "$wd"/PWNED "the path must not be executed ($tmpl)"
    assert_not_contains "$out" "CALL_APP command failed" "CALL_APP must get a usable path ($tmpl)"
    rm -f -- "$wd"/PWNED
  done

  drop_stub_home "$sh"
}

# Test: the newest recording is found in a large directory. Under pipefail,
# 'find | sort | head -n1' died with SIGPIPE (exit 141) once the listing
# outgrew a pipe write, so play and start -c exited silently (stub tools).
# Stub tools: -n given at start must survive until stop. Stubs also keep the
# -t check away from the real transcribe (an API call) if the fix regresses.
test_no_mp3() {
  local -- sh out
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "-n given at start is honoured by a plain stop (paused session)"
  "$VRECORD" -n start wavonly >/dev/null 2>&1
  "$VRECORD" pause >/dev/null 2>&1
  "$VRECORD" stop >/dev/null 2>&1
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'wavonly_*.wav' -type f)" \
    "the WAV must be saved"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name 'wavonly_*.mp3' -type f)" \
    "no MP3 may be made when start had -n"

  start_test "-n with -t warns that the transcript is skipped"
  "$VRECORD" -n start -t wavtx >/dev/null 2>&1
  out=$("$VRECORD" stop 2>&1) || true
  assert_contains "$out" 'Transcription skipped' "stop must say why there is no transcript"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name 'wavtx_*.mp3' -type f)" \
    "no MP3 may be made when start had -n"

  drop_stub_home "$sh"
}

test_many_recordings() {
  local -- sh newest base_pid
  local -i i rc
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  mkdir -p -- "$RECORDING_DIR"
  for ((i = 0; i < 500; i+=1)); do
    : > "$RECORDING_DIR/voice_recording_20260101_$(printf '%06d' "$i").wav"
  done
  touch -d '2026-01-01 00:00' -- "$RECORDING_DIR"/*.wav
  newest="$RECORDING_DIR"/voice_recording_20991231_235959.wav
  : > "$newest"

  start_test "play opens the newest of 501 recordings (5 runs)"
  for ((i = 1; i <= 5; i+=1)); do
    : > "$HOME"/xdg-open.log
    rc=0
    "$VRECORD" play >/dev/null 2>&1 || rc=$?
    assert_equals "0:$newest" "$rc:$(cat -- "$HOME"/xdg-open.log)" \
      "run $i: play must succeed and open the newest recording"
  done

  start_test "start -c continues the newest of 501 recordings"
  rc=0
  "$VRECORD" start -c >/dev/null 2>&1 || rc=$?
  assert_equals 0 "$rc" "start -c must succeed"
  base_pid=$(capture_pid 2>/dev/null || true)
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$newest")" "AUDIO:segment_1.wav:$base_pid" \
    "the continuation must be merged into the newest recording"

  drop_stub_home "$sh"
}

# Test: session data is durable. It must survive the boot-time /tmp wipe, and
# segments kept after a failed merge must never be reaped (stub tools)
test_session_durability() {
  local -- sh base crashed d seg_dir out second wav
  local -i stop_pid i rc
  sh=$(make_stub_home)
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  "$VRECORD" start base >/dev/null 2>&1
  "$VRECORD" -n stop >/dev/null 2>&1
  base=$(find -- "$RECORDING_DIR" -name 'base_*.wav' -type f)

  start_test "an interrupted continuation survives a /tmp wipe (reboot)"
  "$VRECORD" start -c >/dev/null 2>&1
  crashed=$(capture_pid)
  crash_capture
  # Simulate the boot-time clean-up of /tmp, touching only this test's session
  for d in /tmp/vrecord.*/; do
    if [[ $(cat -- "$d"main_file 2>/dev/null) == "$base" ]]; then rm -rf -- "$d"; fi
  done
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "the continuation must survive the wipe and be merged by stop"

  start_test "segments kept after a failed merge outlive the 7-day reaper"
  "$VRECORD" start -c >/dev/null 2>&1
  out=$(STUB_FAIL=merge "$VRECORD" -n stop 2>&1) || true
  seg_dir=$(sed -n 's/.*Segments preserved in: //p' <<<"$out")
  [[ -z "$seg_dir" ]] || touch -d '10 days ago' -- "${seg_dir%/segments}" "$seg_dir"
  "$VRECORD" list >/dev/null 2>&1
  assert_file_exists "$seg_dir/segment_1.wav" \
    "preserved segments must not be deleted (reported: '$seg_dir')"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name '.*' -type f)" \
    "a failed merge must not leave a temporary file beside the recordings"
  assert_success "a new recording must start after a failed merge" "$VRECORD" start next
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "a stop killed mid-merge leaves no temp file, and a retry merges"
  "$VRECORD" start intr >/dev/null 2>&1
  "$VRECORD" pause >/dev/null 2>&1
  "$VRECORD" resume >/dev/null 2>&1
  second=$(capture_pid)
  rm -f -- "$HOME"/stub-merging
  STUB_MERGE_DELAY=2 "$VRECORD" -n stop >/dev/null 2>&1 &
  stop_pid=$!
  for ((i = 0; i < 50; i+=1)); do [[ ! -f "$HOME"/stub-merging ]] || break; sleep 0.1; done
  # The kill must land mid-merge, or the assertions below prove nothing
  assert_file_exists "$HOME"/stub-merging "the merge must be under way when stop is killed"
  kill -TERM "$stop_pid" 2>/dev/null || true
  # The exit status is not asserted: the handler exits 0 here (June #7)
  rc=0
  wait "$stop_pid" || rc=$?
  wav=$(find -- "$RECORDING_DIR" -name 'intr_*.wav' -type f)
  assert_not_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav" \
    "the kill must have stopped the merge before the rename (exit $rc)"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name '.vrecord-merge.*' -type f)" \
    "an interrupted merge must remove its temporary file"
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "a retried stop must merge the audio recorded after the pause"

  drop_stub_home "$sh"
}

# Main test runner
main() {
  echo "vrecord Test Suite"
  echo "=================="
  echo "Project dir: $PROJECT_DIR"
  echo "Test dir: $SCRIPT_DIR"
  echo
  
  # Trap to ensure cleanup, armed before anything is created
  trap cleanup_test_env EXIT

  # Set up test environment
  setup_test_env
  
  # Run test suites
  local -- suite="${1:-all}"
  
  if [[ "$suite" == "all" ]]; then
    run_test_suite "Basic Commands" test_basic_commands
    run_test_suite "Recording Basic" test_recording_basic
    run_test_suite "Pause/Resume" test_pause_resume
    run_test_suite "List Command" test_list_command
    run_test_suite "Play" test_play
    run_test_suite "Continue Recording" test_continue_recording
    run_test_suite "Error Handling" test_error_handling
    run_test_suite "MP3 Conversion" test_mp3_conversion
    run_test_suite "Pause Audio" test_pause_audio
    run_test_suite "Pause Segments" test_pause_segments
    run_test_suite "Session Recovery" test_session_recovery
    run_test_suite "Loop" test_loop
    run_test_suite "No MP3" test_no_mp3
    run_test_suite "Many Recordings" test_many_recordings
    run_test_suite "Session Durability" test_session_durability
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