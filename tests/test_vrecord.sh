#!/usr/bin/env bash
# test_vrecord.sh - Main test runner for vrecord
# Usage: ./test_vrecord.sh [test_suite_name]

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Standard tool locations. Not read-only: test_loop prepends a directory.
declare -x PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Get script directory
declare -- SCRIPT_DIR PROJECT_DIR
SCRIPT_DIR=$(realpath -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=${SCRIPT_DIR%/*}
PROJECT_DIR=${SCRIPT_DIR%/*}

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
export VRECORD="$PROJECT_DIR/vrecord"
# The run-private temp dir and the recording/state dirs inside it (setup_test_env)
declare -x TEST_TMP_DIR='' TEST_RECORDING_DIR='' TEST_STATE_DIR=''

# Ensure vrecord is executable
chmod -- +x "$VRECORD" || { >&2 echo "Cannot make ${VRECORD@Q} executable"; exit 1; }

# Setup test environment
setup_test_env() {
  # Everything a test creates lands in one run-private temp dir -- stub homes
  # (make_stub_home, via TMPDIR), recordings, state -- so the EXIT trap removes
  # it all, even when a test aborts, and nothing is written into the source tree
  TEST_TMP_DIR=$(mktemp -d -t vrecord-tests.XXXXXX) \
    || { >&2 echo 'Cannot create a temporary directory'; exit 1; }
  export TMPDIR="$TEST_TMP_DIR"
  TEST_RECORDING_DIR="$TEST_TMP_DIR"/recordings
  TEST_STATE_DIR="$TEST_TMP_DIR"/state

  # Override vrecord directories for testing. HOME is run-private too: the
  # PulseAudio client writes ~/.config/pulse/cookie there.
  export HOME="$TEST_TMP_DIR"/home
  mkdir -p -- "$TEST_RECORDING_DIR" "$TEST_STATE_DIR" "$HOME" \
    || { >&2 echo "Cannot create the test directories in ${TEST_TMP_DIR@Q}"; exit 1; }
  export RECORDING_DIR="$TEST_RECORDING_DIR"
  export STATE_DIR="$TEST_STATE_DIR"
}

# vstatus: "<stdout word>:<exit code>" of 'vrecord status'
vstatus() {
  local -- word
  local -i rc=0
  word=$("$VRECORD" -q status 2>/dev/null) || rc=$?
  printf '%s:%d' "$word" "$rc"
}

# setup_failed: a step a test depends on failed (not an assertion): name it
# and end the run. The EXIT trap still cleans up.
setup_failed() {
  >&2 printf '  SETUP FAILED in %s: %s\n' "${FUNCNAME[1]}" "$*"
  exit 1
}

# Cleanup test environment
cleanup_test_env() {
  # Stop any running test recording -- only once setup has pointed vrecord at
  # the test dirs; before that, 'stop' would act on the user's real session
  if [[ -n "$TEST_STATE_DIR" && "${STATE_DIR:-}" == "$TEST_STATE_DIR" ]]; then
    "$VRECORD" -n stop >/dev/null 2>&1 || true
  fi

  # Recorders (real or stub) left by an aborted test all write below
  # TEST_TMP_DIR; then remove it. Nothing here may abort the trap.
  if [[ -n "$TEST_TMP_DIR" ]]; then
    pkill -f "$TEST_TMP_DIR/" 2>/dev/null || true
    rm -rf -- "$TEST_TMP_DIR" || :
  fi
}

# Test: Basic command execution
test_basic_commands() {
  local -- output
  start_test "vrecord shows help with no arguments"
  output=$("$VRECORD" 2>&1 || true)
  assert_contains "$output" "Usage:"
  
  start_test "vrecord --version shows version"
  output=$("$VRECORD" --version 2>&1 || true)
  assert_contains "$output" "vrecord 1.3.0"
  
  start_test "vrecord --help shows help"
  output=$("$VRECORD" --help 2>&1 || true)
  assert_contains "$output" "Commands:"
}

# Test: Recording start and stop
test_recording_basic() {
  local -- wav_file
  start_test "vrecord start creates recording"
  assert_success "vrecord start should exit cleanly" "$VRECORD" start test_recording
  sleep 1  # let ffmpeg spin up before the status check below
  
  start_test "vrecord status shows active recording"
  assert_equals "recording:0" "$(vstatus)"
  
  start_test "vrecord stop saves recording"
  assert_success "vrecord stop should exit cleanly" "$VRECORD" stop --no-mp3
  
  start_test "Recording file exists after stop"
  wav_file=$(find -- "$TEST_RECORDING_DIR" -name "test_recording_*.wav" -type f -print -quit)
  assert_file_exists "$wav_file"
}

# Test: Pause and resume functionality
test_pause_resume() {
  start_test "vrecord pause works"
  "$VRECORD" start pause_test 2>/dev/null || setup_failed 'vrecord start pause_test'
  sleep 1
  assert_success "vrecord pause should exit cleanly" "$VRECORD" pause
  
  start_test "vrecord status shows paused state"
  assert_equals "paused:0" "$(vstatus)"

  start_test "vrecord resume works"
  assert_success "vrecord resume should exit cleanly" "$VRECORD" resume

  start_test "vrecord status shows recording after resume"
  assert_equals "recording:0" "$(vstatus)"
  
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1 || setup_failed 'vrecord stop --no-mp3'
}

# Test: List command
test_list_command() {
  local -- output
  # Create some test recordings
  touch -- "$TEST_RECORDING_DIR/test1.wav" "$TEST_RECORDING_DIR/test2.wav" \
           "$TEST_RECORDING_DIR/test.mp3" || setup_failed 'create the test recordings'

  start_test "vrecord list shows WAV files"
  output=$("$VRECORD" list 2>&1) || setup_failed 'vrecord list'
  assert_contains "$output" "test1.wav"
  assert_contains "$output" "test2.wav"
  assert_not_contains "$output" "test.mp3"
  
  start_test "vrecord list --all shows all files"
  output=$("$VRECORD" list --all 2>&1) || setup_failed 'vrecord list --all'
  assert_contains "$output" "test1.wav"
  assert_contains "$output" "test2.wav"
  assert_contains "$output" "test.mp3"
}

# Test: Continue last recording
test_continue_recording() {
  local -- wav_files mono probe dur
  # Create initial recording
  "$VRECORD" start continue_test 2>/dev/null || setup_failed 'vrecord start continue_test'
  sleep 1
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1 || setup_failed 'vrecord stop --no-mp3'
  
  start_test "vrecord start -c continues last recording"
  assert_success "vrecord start -c should exit cleanly" "$VRECORD" start -c
  
  sleep 1
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1 || setup_failed 'vrecord stop --no-mp3'
  
  start_test "Continued recording exists"
  wav_files=$(find -- "$TEST_RECORDING_DIR" -name "continue_test_*.wav" -type f | wc -l)
  assert_equals "1" "$wav_files" "Should have exactly one WAV file after continuation"

  # Merging with -c copy keeps the first file's header: new audio recorded at
  # another rate or channel count was silently reinterpreted (here 4x longer)
  mono="$TEST_RECORDING_DIR"/mono22k.wav
  ffmpeg -hide_banner -loglevel error -f lavfi -i sine=f=440:d=2:sample_rate=22050 \
         -ac 1 -c:a pcm_s16le -y file:"$mono" </dev/null || setup_failed 'generate mono22k.wav'
  "$VRECORD" -b start -r mono22k.wav 2>/dev/null || setup_failed 'vrecord -b start -r mono22k.wav'
  sleep 2
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  probe=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels \
          -of csv=p=0 file:"$mono" 2>/dev/null) || probe=''
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 file:"$mono" 2>/dev/null) || dur=0
  start_test "continuing a 22.05 kHz mono WAV keeps its format (got $probe)"
  assert_equals "22050,1" "$probe"
  start_test "continuing a 22.05 kHz mono WAV keeps its length (got ${dur}s, want 3-7s)"
  assert_success "new audio must be recorded in the file's format" \
    awk -v d="$dur" 'BEGIN { exit !(d >= 3 && d <= 7) }'
}

# Test: Error handling
test_error_handling() {
  local -- output cmd
  local -i rc

  for cmd in pause resume stop; do
    start_test "vrecord $cmd without active recording fails"
    rc=0
    "$VRECORD" "$cmd" >/dev/null 2>&1 || rc=$?
    assert_equals 1 "$rc" "$cmd must exit 1 when there is no session"
  done

  start_test "vrecord prevents concurrent recordings"
  "$VRECORD" start test1 2>/dev/null || setup_failed 'vrecord start test1'
  sleep 1
  output=$("$VRECORD" start test2 2>&1) || true
  assert_contains "$output" "already in progress" \
    "A second concurrent start must be rejected with 'already in progress'"
  "$VRECORD" stop --no-mp3 >/dev/null 2>&1 || setup_failed 'vrecord stop --no-mp3'
}

# Test: MP3 conversion
test_mp3_conversion() {
  # Check if ffmpeg has the MP3 encoder vrecord uses. Capture first: piping
  # into 'grep -q' kills ffmpeg with SIGPIPE, and pipefail turned that into
  # a false "lacks MP3 support" that silently skipped this suite.
  local -- encoders mp3_file
  encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null) || encoders=''
  if [[ "$encoders" != *libmp3lame* ]]; then
    echo "  Skipping MP3 tests - ffmpeg lacks libmp3lame"
    return
  fi
  
  start_test "vrecord creates MP3 by default"
  "$VRECORD" start mp3_test 2>/dev/null || setup_failed 'vrecord start mp3_test'
  sleep 1
  "$VRECORD" stop >/dev/null 2>&1 || setup_failed 'vrecord stop'
  
  mp3_file=$(find -- "$TEST_RECORDING_DIR" -name "mp3_test_*.mp3" -type f -print -quit)
  assert_file_exists "$mp3_file" "MP3 file should be created"
  
  start_test "vrecord --no-mp3 skips MP3 creation"
  "$VRECORD" -n start no_mp3_test 2>/dev/null || setup_failed 'vrecord -n start no_mp3_test'
  sleep 1
  "$VRECORD" stop >/dev/null 2>&1 || setup_failed 'vrecord stop'
  
  mp3_file=$(find -- "$TEST_RECORDING_DIR" -name "no_mp3_test_*.mp3" -type f -print -quit)
  assert_file_not_exists "$mp3_file" "MP3 file should not be created with --no-mp3"
}

# Test: play command (resolution + invocation, via a mocked xdg-open)
test_play() {
  # vrecord locks PATH to "$HOME/.local/bin:..." so a mock placed there wins.
  local -- ph xdg_log
  local -i rc
  ph=$(mktemp -d) || { fail 'cannot create a temporary directory'; return 0; }
  mkdir -p -- "$ph/.local/bin" || setup_failed 'create the mock bin directory'
  xdg_log="$ph/xdg.log"
  cat > "$ph/.local/bin/xdg-open" <<MOCK || setup_failed 'write the xdg-open mock'
#!/usr/bin/env bash
printf '%s\n' "\$1" > "$xdg_log"
MOCK
  chmod -- +x "$ph/.local/bin/xdg-open" || setup_failed 'make the xdg-open mock executable'

  start_test "vrecord play <name> resolves to RECORDING_DIR and appends .wav"
  touch -- "$TEST_RECORDING_DIR/playtest.wav" || setup_failed 'create playtest.wav'
  HOME="$ph" "$VRECORD" play playtest 2>/dev/null
  assert_equals "$TEST_RECORDING_DIR/playtest.wav" "$(cat -- "$xdg_log" 2>/dev/null || true)" \
    "play should open the resolved .wav file"

  start_test "vrecord play with no argument plays the most recent recording"
  : > "$xdg_log" || setup_failed 'empty the xdg-open log'
  sleep 1
  touch -- "$TEST_RECORDING_DIR/playnewer.wav" || setup_failed 'create playnewer.wav'
  HOME="$ph" "$VRECORD" play 2>/dev/null
  assert_equals "$TEST_RECORDING_DIR/playnewer.wav" "$(cat -- "$xdg_log" 2>/dev/null || true)" \
    "no-arg play should open the most recent WAV"

  start_test "vrecord play with a missing file fails"
  rc=0
  HOME="$ph" "$VRECORD" play no_such_recording 2>/dev/null || rc=$?
  assert_equals 1 "$rc" "play must exit 1 for a missing recording"

  # xdg-open takes no --: a path that starts with a dash is read as an option
  start_test "vrecord play gives xdg-open an absolute path when RECORDING_DIR is relative"
  mkdir -p -- "$ph/-rel" || setup_failed 'create the -rel directory'
  touch -- "$ph/-rel/reltest.wav" || setup_failed 'create reltest.wav'
  : > "$xdg_log" || setup_failed 'empty the xdg-open log'
  (cd -- "$ph" && HOME="$ph" RECORDING_DIR=-rel "$VRECORD" play reltest 2>/dev/null) || true
  assert_equals "$(realpath -- "$ph")/-rel/reltest.wav" "$(cat -- "$xdg_log" 2>/dev/null || true)" \
    "a relative RECORDING_DIR must be made absolute"

  rm -rf -- "$ph" || setup_failed 'remove the mock home'
}

# Test: a pause must not end up in the recording (real ffmpeg + live audio).
# A SIGSTOP-based pause let the audio server buffer the paused span (~24 s)
# and hand it over on resume, so short pauses were recorded in full.
test_pause_audio() {
  local -- wav dur

  start_test "stop after pause/resume succeeds"
  "$VRECORD" -b start pause_audio 2>/dev/null || setup_failed 'vrecord -b start pause_audio'
  sleep 2
  "$VRECORD" pause 2>/dev/null || setup_failed 'vrecord pause'
  sleep 6
  "$VRECORD" resume 2>/dev/null || setup_failed 'vrecord resume'
  sleep 2
  assert_success "stop should exit cleanly" "$VRECORD" stop --no-mp3

  wav=$(find -- "$TEST_RECORDING_DIR" -name 'pause_audio_*.wav' -type f)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 file:"$wav" 2>/dev/null) || dur=0
  start_test "recording holds only unpaused time (got ${dur}s, want 3-7s)"
  assert_success "paused audio must not be recorded" \
    awk -v d="$dur" 'BEGIN { exit !(d >= 3 && d <= 7) }'

  start_test "resume then immediate pause, stop while paused: WAV and MP3 saved"
  "$VRECORD" -b start pause_quick 2>/dev/null || setup_failed 'vrecord -b start pause_quick'
  sleep 1
  "$VRECORD" pause 2>/dev/null || setup_failed 'vrecord pause'
  "$VRECORD" resume 2>/dev/null || setup_failed 'vrecord resume'
  "$VRECORD" pause 2>/dev/null || setup_failed 'vrecord pause'
  assert_success "stop while paused should exit cleanly" "$VRECORD" stop
  wav=$(find -- "$TEST_RECORDING_DIR" -name 'pause_quick_*.wav' -type f)
  assert_file_exists "${wav%.wav}.mp3" "stop while paused must still create the MP3"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 file:"$wav" 2>/dev/null) || dur=0
  assert_success "merged WAV must be readable with audio (got ${dur}s)" \
    awk -v d="$dur" 'BEGIN { exit !(d >= 1) }'
}

# Test: pause/resume bookkeeping, with stub tools (no audio device)
test_pause_segments() {
  local -- sh wav first second
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "pause/resume records a second segment and stop merges both"
  "$VRECORD" start seg >/dev/null 2>&1 || setup_failed 'vrecord start seg'
  first=$(capture_pid) || setup_failed 'read the capture PID'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  second=$(capture_pid) || setup_failed 'read the capture PID'
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  wav=$(find -- "$RECORDING_DIR" -name 'seg_*.wav' -type f)
  assert_contains "$(cat -- "$wav")" ":$first" "audio before the pause must be kept"
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "audio after resume must be recorded as a new segment and merged"

  start_test "merging keeps the recording's permissions"
  "$VRECORD" start perm >/dev/null 2>&1 || setup_failed 'vrecord start perm'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  wav=$(find -- "$RECORDING_DIR" -name 'perm_*.wav' -type f)
  chmod -- 640 "$wav" || setup_failed 'set the recording to mode 640'
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  assert_equals 640 "$(stat -c %a -- "$wav")" "merge must not change the file mode"

  start_test "start is refused while a recording is paused"
  "$VRECORD" start held >/dev/null 2>&1 || setup_failed 'vrecord start held'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  assert_failure "start must not replace a paused session" "$VRECORD" start other
  start_test "status reports the paused session"
  assert_equals "paused:0" "$(vstatus)"

  start_test "stop while paused converts to MP3 and transcribes"
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" stop -t >/dev/null 2>&1 || setup_failed 'vrecord stop -t'
  wav=$(find -- "$RECORDING_DIR" -name 'held_*.wav' -type f)
  assert_file_exists "${wav%.wav}.mp3" "MP3 must be created when stopping a paused session"
  assert_file_exists "${wav%.wav}.txt" "transcript must be created when stopping a paused session"

  start_test "a failed resume leaves the session paused and intact"
  "$VRECORD" start fr >/dev/null 2>&1 || setup_failed 'vrecord start fr'
  first=$(capture_pid) || setup_failed 'read the capture PID'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  assert_failure "resume must report the failure" env STUB_FAIL=capture "$VRECORD" resume
  assert_equals "paused:0" "$(vstatus)"
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  second=$(capture_pid) || setup_failed 'read the capture PID'
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  wav=$(find -- "$RECORDING_DIR" -name 'fr_*.wav' -type f)
  assert_contains "$(cat -- "$wav")" ":$first" "audio before the pause must be kept"
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "the next successful resume must record segment 1 and be merged"

  drop_stub_home "$sh"
}

# Test: an interrupted session (ffmpeg crashed mid-recording) keeps its audio
# until 'stop' merges it, whatever is run in between (stub tools)
test_session_recovery() {
  local -- sh base crashed how out seg_dir wav
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  "$VRECORD" start base >/dev/null 2>&1 || setup_failed 'vrecord start base'
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  base=$(find -- "$RECORDING_DIR" -name 'base_*.wav' -type f)

  start_test "status leaves an interrupted continuation's audio intact"
  "$VRECORD" start -c >/dev/null 2>&1 || setup_failed 'vrecord start -c'
  crashed=$(capture_pid) || setup_failed 'read the capture PID'
  crash_capture
  "$VRECORD" status >/dev/null 2>&1 || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "stop after status must merge the continuation recorded before the crash"

  start_test "status reports an interrupted session and how to save it"
  "$VRECORD" start -c >/dev/null 2>&1 || setup_failed 'vrecord start -c'
  crashed=$(capture_pid) || setup_failed 'read the capture PID'
  crash_capture
  assert_contains "$("$VRECORD" status 2>&1 || true)" "stop"  # status exits 1: interrupted
  assert_equals "interrupted:1" "$(vstatus)"

  start_test "start refuses to replace an interrupted session"
  assert_failure "a new start must not discard the interrupted session" "$VRECORD" start other
  assert_failure "start -c must not reuse the interrupted session" "$VRECORD" start -c
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "the interrupted continuation must still be merged by stop"

  start_test "stop never deletes segments it could not merge (paused, then interrupted)"
  for how in pause crash; do
    "$VRECORD" start -c >/dev/null 2>&1 || setup_failed 'vrecord start -c'
    if [[ $how == pause ]]; then "$VRECORD" pause >/dev/null 2>&1; else crash_capture; fi
    : > "$STATE_DIR"/session/main_file || setup_failed 'empty main_file'  # simulate a damaged session record
    out=$("$VRECORD" -n stop 2>&1) || true
    seg_dir=$(sed -n 's/.*Segments preserved in: //p' <<<"$out")
    assert_file_exists "$seg_dir/segment_1.wav" \
      "$how: unmerged segments must be preserved (reported: '$seg_dir')"
  done

  start_test "a failed start leaves no session behind"
  assert_failure "start must report the failure" env STUB_FAIL=capture "$VRECORD" start broken
  assert_contains "$("$VRECORD" status 2>&1 || true)" "No active recording"  # exits 3: idle
  assert_equals "idle:3" "$(vstatus)"
  assert_success "the next start must work" "$VRECORD" start fine
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "stop saves an interrupted new recording like a normal stop"
  "$VRECORD" start -t crashnew >/dev/null 2>&1 || setup_failed 'vrecord start -t crashnew'
  crash_capture
  out=$("$VRECORD" stop 2>/dev/null) || true
  wav=$(find -- "$RECORDING_DIR" -name 'crashnew_*.wav' -type f)
  assert_equals "$wav" "$out" "stop must print the saved WAV path"
  assert_file_exists "${wav%.wav}.txt" "the MP3 and transcript must still be made"

  drop_stub_home "$sh"
}

# Test: 'stop' reports the saved recording on stdout, and vrecord-loop shows
# and forwards only that recording's transcript (stub tools; real scripts)
test_loop() {
  local -- sh bin wd out wav tmpl keys
  local -i loop_pid rc
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  # vrecord-loop locks PATH to ~/.local/bin and the system directories. A
  # wrapper there runs this checkout's vrecord, never an installed copy, and
  # logs each call. $bin goes on the caller's PATH, which only CALL_APP sees.
  bin=$sh/bin
  wd=$sh/cwd
  mkdir -p -- "$bin" "$wd" || setup_failed 'create the bin and work directories'
  cat > "$HOME"/.local/bin/vrecord <<WRAPPER || setup_failed 'write the vrecord wrapper'
#!/bin/bash
printf '%s\n' "\$*" >> "\$HOME"/vrecord-calls.log
exec ${VRECORD@Q} "\$@"
WRAPPER
  chmod -- +x "$HOME"/.local/bin/vrecord || setup_failed 'make the vrecord wrapper executable'
  local -x PATH="$bin:$PATH"

  start_test "stop prints only the saved WAV path on stdout"
  "$VRECORD" start -t out >/dev/null 2>&1 || setup_failed 'vrecord start -t out'
  out=$("$VRECORD" -q stop 2>/dev/null) || setup_failed 'vrecord -q stop'
  wav=$(find -- "$RECORDING_DIR" -name 'out_*.wav' -type f)
  assert_equals "$wav" "$out"

  start_test "loop shows this recording's transcript and pipes it to CALL_APP"
  out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C "tee $sh/received" 2>&1) || true
  assert_contains "$out" "TRANSCRIPT of voice_"
  assert_contains "$(cat -- "$sh"/received 2>/dev/null || true)" "TRANSCRIPT of voice_"

  start_test "loop finds vrecord in ~/.local/bin, where a --user install puts it"
  assert_contains "$(cat -- "$HOME"/vrecord-calls.log 2>/dev/null || true)" "start -t" \
    "the loop must run the vrecord in ~/.local/bin"

  start_test "CALL_APP runs with the caller's PATH, not the loop's locked one"
  cat > "$bin"/mytool <<'TOOL' || setup_failed 'write mytool'
#!/bin/bash
cat > "$HOME"/mytool.out
TOOL
  chmod -- +x "$bin"/mytool || setup_failed 'make mytool executable'
  (cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C mytool >/dev/null 2>&1) || true
  assert_contains "$(cat -- "$HOME"/mytool.out 2>/dev/null || true)" "TRANSCRIPT of" \
    "a command on the caller's PATH must be found"

  start_test "loop never runs VERBOSE from the environment as code"
  # shellcheck disable=SC2016 # the attack text: it must reach the loop unexpanded
  (cd -- "$wd" && VERBOSE='HOME[$(touch PWNED)]' "$PROJECT_DIR"/vrecord-loop -V >/dev/null 2>&1) || true
  assert_file_not_exists "$wd"/PWNED "arithmetic would run the command in the subscript"

  start_test "loop does not show an older transcript when transcription fails"
  rm -f -- "$RECORDING_DIR"/*.txt || setup_failed 'remove old transcripts'
  echo 'OLD TRANSCRIPT' > "$RECORDING_DIR"/voice_20200101_000000.txt || setup_failed 'write the old transcript'
  out=$(cd -- "$wd" && printf q | STUB_TRANSCRIBE_FAIL=1 "$PROJECT_DIR"/vrecord-loop 2>&1) || true
  assert_not_contains "$out" "OLD TRANSCRIPT"

  start_test "loop does not show unrelated files from the current directory"
  rm -f -- "$RECORDING_DIR"/*.txt || setup_failed 'remove old transcripts'
  echo 'UNRELATED FILE' > "$wd"/notes.txt || setup_failed 'write the unrelated file'
  out=$(cd -- "$wd" && printf q | STUB_TRANSCRIBE_FAIL=1 "$PROJECT_DIR"/vrecord-loop 2>&1) || true
  assert_not_contains "$out" "UNRELATED FILE"

  start_test "loop records under a prefix given after --"
  out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -- dashprefix 2>&1) || true
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'dashprefix_*.wav' -type f)" \
    "the prefix after -- must be used"
  start_test "loop's default output carries no vrecord debug messages"
  assert_not_contains "$out" "⦿"

  # vrecord would read '-c' as continue-last and append to an old recording
  start_test "loop refuses a prefix that starts with a dash"
  : > "$HOME"/stub-captures.log || setup_failed 'empty the capture log'
  rc=0
  (cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -- -c >/dev/null 2>&1) || rc=$?
  assert_equals "22:0" "$rc:$(wc -l < "$HOME"/stub-captures.log)" \
    "a dash prefix must be refused (exit 22) before anything is recorded"
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "loop refuses a prefix that starts with a dot"
  rc=0
  (cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop .hidden >/dev/null 2>&1) || rc=$?
  assert_equals "22:0" "$rc:$(wc -l < "$HOME"/stub-captures.log)" \
    "a dot prefix (a hidden recording) must be refused before anything is recorded"
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "stdin-mode CALL_APP is run by the shell, so quoting works"
  rm -f -- "$sh"/received || setup_failed 'remove the CALL_APP output'
  out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C "sed 's/^/got: /' >$sh/received" 2>&1) || true
  assert_contains "$(cat -- "$sh"/received 2>/dev/null || true)" "got: TRANSCRIPT of"

  start_test "a multi-byte key (an arrow key) counts as one key press"
  : > "$HOME"/stub-captures.log || setup_failed 'empty the capture log'
  (cd -- "$wd" && printf '\e[A' | "$PROJECT_DIR"/vrecord-loop >/dev/null 2>&1) || true
  assert_equals 1 "$(wc -l < "$HOME"/stub-captures.log)" "one key press must make one recording"
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "loop warns when transcribe is not installed"
  # The loop's PATH is fixed: a transcribe in a system directory cannot be hidden
  if [[ -n $(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin type -P transcribe || true) ]]; then
    echo "  Skipping: a system transcribe is on the loop's locked PATH"
  else
    mv -- "$HOME"/.local/bin/transcribe "$sh"/transcribe.off || setup_failed 'set the transcribe stub aside'
    out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop 2>&1) || true
    mv -- "$sh"/transcribe.off "$HOME"/.local/bin/transcribe || setup_failed 'restore the transcribe stub'
    assert_contains "$out" "transcribe not found"
  fi

  start_test "SIGTERM makes the loop stop and save its recording"
  rm -f -- "$HOME"/stub-capture.pid || setup_failed 'remove the capture PID file'
  mkfifo -- "$sh"/keys || setup_failed 'create the key FIFO'
  "$PROJECT_DIR"/vrecord-loop -- sigterm <"$sh"/keys >/dev/null 2>&1 &
  loop_pid=$!
  exec {keys}>"$sh"/keys   # a writer that never writes: the loop waits for a key
  wait_for_file "$HOME"/stub-capture.pid || true
  kill -TERM "$loop_pid" 2>/dev/null || true
  rc=0
  wait "$loop_pid" || rc=$?
  exec {keys}>&-
  assert_equals "143:idle:3" "$rc:$(vstatus)" "the loop must exit 128+15 and leave no session"
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'sigterm_*.wav' -type f)" \
    "the interrupted recording must be saved"

  start_test "CALL_APP {{FILE}} receives the path as data, never as shell code"
  RECORDING_DIR="$sh/rec \$(touch PWNED)"
  for tmpl in 'wc -c {{FILE}}' 'wc -c "{{FILE}}"'; do
    out=$(cd -- "$wd" && printf q | "$PROJECT_DIR"/vrecord-loop -C "$tmpl" 2>&1) || true
    assert_file_not_exists "$wd"/PWNED "the path must not be executed ($tmpl)"
    assert_not_contains "$out" "CALL_APP command failed" "CALL_APP must get a usable path ($tmpl)"
    rm -f -- "$wd"/PWNED || setup_failed 'remove the PWNED marker'
  done

  drop_stub_home "$sh"
}

# Test: the command line and the status contract (stub tools)
test_cli() {
  local -- sh
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "status prints 'idle' and exits 3 when there is no session"
  assert_equals "idle:3" "$(vstatus)"

  start_test "status prints 'recording' and exits 0 while recording"
  "$VRECORD" start st >/dev/null 2>&1 || setup_failed 'vrecord start st'
  assert_equals "recording:0" "$(vstatus)"
  start_test "status does not end with 'Recording continues in background'"
  assert_not_contains "$("$VRECORD" status 2>&1)" "continues in background"

  start_test "status prints 'paused' and exits 0 while paused"
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  assert_equals "paused:0" "$(vstatus)"

  start_test "status prints 'interrupted' and exits 1 once the recorder died"
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  crash_capture
  assert_equals "interrupted:1" "$(vstatus)"
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "bundled start options (-tn) are accepted"
  assert_success "start -tn must be accepted" "$VRECORD" start -tn bundle
  assert_contains "$("$VRECORD" stop 2>&1 || true)" 'Transcription skipped' \
    "both -t and -n must take effect"

  start_test "-v shows debug messages"
  assert_contains "$("$VRECORD" -v pause 2>&1 || true)" "Lock acquired"
  start_test "debug messages are hidden by default"
  assert_not_contains "$("$VRECORD" pause 2>&1 || true)" "Lock acquired"

  start_test "an unsafe DEFAULT_PREFIX is rejected"
  assert_failure "start must refuse a default prefix holding a path" \
    env VRECORD_DEFAULT_PREFIX=../escape "$VRECORD" start
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals "" "$(find -- "$sh" -maxdepth 1 -name 'escape_*')" \
    "nothing may be written outside the recordings directory"

  # list, start -c and play (no name) never see a hidden file
  start_test "a prefix that starts with a dot is refused: it would make a hidden recording"
  assert_failure "start must refuse a dot prefix" "$VRECORD" start .hidden
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_failure "start must refuse a dot DEFAULT_PREFIX" \
    env VRECORD_DEFAULT_PREFIX=.hidden "$VRECORD" start
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals "" "$(find -- "$RECORDING_DIR" -name '.hidden*' 2>/dev/null || true)" \
    "no hidden recording may be made"

  start_test "MIN_DISK_SPACE_MB is honoured"
  assert_failure "start must refuse when free space is below MIN_DISK_SPACE_MB" \
    env MIN_DISK_SPACE_MB=999999999 "$VRECORD" start big
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "start leaves a user's .test file in the recordings directory alone"
  echo keep > "$RECORDING_DIR"/.test || setup_failed 'write the .test file'
  "$VRECORD" start probe >/dev/null 2>&1 || setup_failed 'vrecord start probe'
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals keep "$(cat -- "$RECORDING_DIR"/.test 2>/dev/null || true)"

  drop_stub_home "$sh"
}

# Test: config files apply whole, and a broken one never ends vrecord (stubs)
test_config() {
  local -- sh out
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  mkdir -p -- "$STATE_DIR" || setup_failed 'create the state directory'

  start_test "a failing command inside the config does not end vrecord"
  printf '%s\n' 'DEFAULT_PREFIX=midfalse' 'false' 'MP3_BITRATE=192k' > "$STATE_DIR"/config || setup_failed 'write the config'
  assert_success "start must survive the config" "$VRECORD" start
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'midfalse_*.wav' -type f)" \
    "the config's settings must apply"

  start_test "a config whose last test is false still applies"
  # shellcheck disable=SC2016 # config text: expanded by vrecord, not here
  printf '%s\n' 'DEFAULT_PREFIX=lastfalse' '[[ -n ${VRECORD_UNSET_TEST:-} ]] && MP3_BITRATE=320k' \
    > "$STATE_DIR"/config
  "$VRECORD" start >/dev/null 2>&1 || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'lastfalse_*.wav' -type f)" \
    "the config's settings must apply"

  start_test "a config with a syntax error is ignored with a warning"
  printf '%s\n' 'DEFAULT_PREFIX=broken' 'if then' > "$STATE_DIR"/config || setup_failed 'write the config'
  out=$("$VRECORD" start 2>&1) || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$out" "Invalid config file"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name 'broken_*.wav' -type f)" \
    "a config with a syntax error must not be applied in part"

  start_test "a config value that would end vrecord is ignored with a warning"
  printf '%s\n' 'SAMPLE_RATE=abc' > "$STATE_DIR"/config || setup_failed 'write the config'
  assert_success "start must survive the config" "$VRECORD" start
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  rm -f -- "$STATE_DIR"/config || setup_failed 'remove the config'

  # declare -i evaluates what it is given as arithmetic: 'stereo' reads as an
  # unset variable, which ends vrecord under set -u, and '08' as bad octal
  start_test "an environment value that is not a whole number is ignored with a warning"
  out=$(CHANNELS=stereo SAMPLE_RATE=08 "$VRECORD" start envbad 2>&1) || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$out" "Ignoring CHANNELS='stereo'"
  assert_contains "$(head -n 1 -- "$(find -- "$RECORDING_DIR" -name 'envbad_*.wav' -type f -print -quit)" 2>/dev/null || true)" \
    "fmt=pcm_s16le/44100/2" "the defaults must apply"

  start_test "an environment value is never run as code"
  # shellcheck disable=SC2016 # the attack text: it must reach vrecord unexpanded
  (cd -- "$sh" && SAMPLE_RATE='HOME[$(touch PWNED)]' "$VRECORD" status >/dev/null 2>&1) || true
  assert_file_not_exists "$sh"/PWNED "arithmetic would run the command in the subscript"

  drop_stub_home "$sh"
}

# Test: the lock waits, and stop releases it before slow post-processing (stubs)
test_locking() {
  local -- sh out first
  local -i holder stop_pid rc
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  mkdir -p -- "$STATE_DIR" || setup_failed 'create the state directory'

  start_test "a command waits for a briefly held lock instead of giving up"
  flock -- "$STATE_DIR"/vrecord.lock sleep 1 &
  holder=$!
  sleep 0.3
  out=$("$VRECORD" pause 2>&1) || true
  rc=0
  wait "$holder" || rc=$?
  assert_equals 0 "$rc" "the test's lock holder must exit cleanly"
  assert_not_contains "$out" "Another instance" "pause must wait for the lock"
  assert_contains "$out" "No active recording"

  start_test "a new recording can start while the last stop converts to MP3"
  "$VRECORD" start first >/dev/null 2>&1 || setup_failed 'vrecord start first'
  rm -f -- "$HOME"/stub-converting || setup_failed 'remove the conversion marker'
  # Longer than the 5 s lock wait: a stop holding the lock would refuse start
  STUB_MP3_DELAY=7 "$VRECORD" stop >"$sh"/stop.out 2>/dev/null &
  stop_pid=$!
  wait_for_file "$HOME"/stub-converting || true
  assert_file_exists "$HOME"/stub-converting "the conversion must be under way"
  assert_success "start must not wait for the previous stop's conversion" \
    "$VRECORD" start second
  rc=0
  wait "$stop_pid" || rc=$?
  first=$(find -- "$RECORDING_DIR" -name 'first_*.wav' -type f)
  assert_equals "0:$first" "$rc:$(cat -- "$sh"/stop.out)" \
    "the first stop must still succeed and report its recording"
  start_test "the new session survives the previous stop's post-processing"
  assert_equals "recording:0" "$(vstatus)"
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  drop_stub_home "$sh"
}

# Test: the beep loop holds no descriptor of vrecord's, and leaves no child
# process behind when stopped (stub tools)
test_beep() {
  local -- sh beep fds out
  local -i i
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=1 \
           BEEP_INTERVAL=4321 BEEP_FILE=$sh/beep.mp3
  : > "$BEEP_FILE" || setup_failed 'create the beep file'

  start_test "the beep loop and recorder hold none of vrecord's stdout, stderr or lock"
  "$VRECORD" start beep >"$sh"/start.out 2>&1 || setup_failed 'vrecord start beep'
  beep=$(cat -- "$STATE_DIR"/session/beep.pid 2>/dev/null || true)
  fds="$(readlink -- "/proc/$beep/fd/1" || echo none):$(readlink -- "/proc/$beep/fd/2" || echo none)"
  fds+=":$(readlink -- "/proc/$beep/fd/9" || echo no-lock)"
  fds+=":$(readlink -- "/proc/$(capture_pid)/fd/9" || echo no-lock)"
  assert_equals "/dev/null:/dev/null:no-lock:no-lock" "$fds" \
    "\$(vrecord start) would hang, and a killed start would leave the lock held"

  start_test "stop leaves no beep interval sleep behind"
  for ((i = 0; i < 50; i+=1)); do pgrep -fx 'sleep 4321' >/dev/null && break; sleep 0.1; done
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  sleep 0.3
  assert_equals "" "$(pgrep -fx 'sleep 4321' || true)" "the beep loop's sleep must end with it"
  pkill -fx 'sleep 4321' 2>/dev/null || true

  start_test "stop leaves no beep player behind"
  rm -f -- "$HOME"/stub-ffplay.pid || setup_failed 'remove the ffplay PID file'
  STUB_BEEP_SECONDS=30 "$VRECORD" start beep2 >/dev/null 2>&1
  wait_for_file "$HOME"/stub-ffplay.pid || true
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  sleep 0.3
  assert_failure "the beep loop's player must end with it" \
    kill -0 "$(cat -- "$HOME"/stub-ffplay.pid 2>/dev/null || echo 0)"
  pkill -fx 'sleep 30' 2>/dev/null || true

  # 'sleep 0' returns at once, so a zero interval played the beep nonstop
  start_test "BEEP_INTERVAL=0 turns beeps off instead of beeping nonstop"
  rm -f -- "$HOME"/stub-ffplay.log || setup_failed 'remove the ffplay log'
  out=$(BEEP_INTERVAL=0 "$VRECORD" start beep3 2>&1) || true
  sleep 1
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals 0 "$( (cat -- "$HOME"/stub-ffplay.log 2>/dev/null || true) | wc -l)" \
    "no beep may play with a zero interval"
  assert_contains "$out" "BEEP_INTERVAL"

  # A player that fails (no output device, a bad beep file) fails every time
  start_test "the beep loop gives up when the player fails"
  rm -f -- "$HOME"/stub-ffplay.log || setup_failed 'remove the ffplay log'
  BEEP_INTERVAL=1 STUB_FAIL=ffplay "$VRECORD" start beep4 >/dev/null 2>&1
  sleep 2.5
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals 1 "$( (cat -- "$HOME"/stub-ffplay.log 2>/dev/null || true) | wc -l)" \
    "a failing player must not be retried every interval"

  drop_stub_home "$sh"
}

# Test: new audio is recorded in the format of the recording it joins, and
# merge lists survive unusual paths (stub tools)
test_format() {
  local -- sh wav second
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  mkdir -p -- "$RECORDING_DIR" || setup_failed 'create the recording directory'

  start_test "continuing a recording records new audio in its format"
  printf 'AUDIO:mono.wav:1 fmt=pcm_s16le/22050/1\n' > "$RECORDING_DIR"/mono.wav || setup_failed 'write mono.wav'
  "$VRECORD" start -r mono.wav >/dev/null 2>&1 || setup_failed 'vrecord start -r mono.wav'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_equals 3 "$(grep -c -- 'fmt=pcm_s16le/22050/1$' "$RECORDING_DIR"/mono.wav)" \
    "both new segments must be recorded at 22050 Hz mono"

  start_test "a recording keeps its format when the config changes before resume"
  "$VRECORD" start keep >/dev/null 2>&1 || setup_failed 'vrecord start keep'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  SAMPLE_RATE=48000 CHANNELS=1 "$VRECORD" resume >/dev/null 2>&1
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  wav=$(find -- "$RECORDING_DIR" -name 'keep_*.wav' -type f)
  assert_equals 2 "$(grep -c -- 'fmt=pcm_s16le/44100/2$' "$wav")" \
    "the resumed segment must match the recording"

  start_test "only a PCM WAV recording can be continued"
  printf 'MP3 of x\n' > "$RECORDING_DIR"/song.mp3 || setup_failed 'write song.mp3'
  assert_failure "start -r must refuse an MP3" "$VRECORD" start -r song.mp3
  assert_equals "MP3 of x:idle:3" "$(cat -- "$RECORDING_DIR"/song.mp3):$(vstatus)" \
    "the MP3 must be untouched and no session left behind"

  start_test "a recording directory with a quote in its name still merges"
  "$VRECORD" -n stop >/dev/null 2>&1 || true   # in case the refusal above failed
  RECORDING_DIR="$sh/rec'q"
  "$VRECORD" start quoted >/dev/null 2>&1 || setup_failed 'vrecord start quoted'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  second=$(capture_pid) || setup_failed 'read the capture PID'
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  wav=$(find -- "$RECORDING_DIR" -name 'quoted_*.wav' -type f 2>/dev/null) || wav=''
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "the segment must be merged"

  drop_stub_home "$sh"
}

# Test: an error that points at a log points at one that still exists (stubs)
test_logs() {
  local -- sh out log
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "a failed start names a log that still exists"
  out=$(STUB_FAIL=capture "$VRECORD" start broken 2>&1) || true
  log=$(sed -n 's/.*Check \(.*\) for details.*/\1/p' <<<"$out")
  assert_file_exists "$log" "the log named in the error must exist (named: '$log')"

  start_test "a failed MP3 conversion names a log that still exists"
  "$VRECORD" start mp3fail >/dev/null 2>&1 || setup_failed 'vrecord start mp3fail'
  out=$(STUB_FAIL=mp3 "$VRECORD" stop 2>&1) || true
  log=$(sed -n 's/.*Check \(.*\) for details.*/\1/p' <<<"$out")
  assert_file_exists "$log" "the log named in the error must exist (named: '$log')"

  drop_stub_home "$sh"
}

# Test: the newest recording is found in a large directory. Under pipefail,
# 'find | sort | head -n1' died with SIGPIPE (exit 141) once the listing
# outgrew a pipe write, so play and start -c exited silently (stub tools).
# Stub tools: -n given at start must survive until stop. Stubs also keep the
# -t check away from the real transcribe (an API call) if the fix regresses.
test_no_mp3() {
  local -- sh out
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0

  start_test "-n given at start is honoured by a plain stop (paused session)"
  "$VRECORD" -n start wavonly >/dev/null 2>&1 || setup_failed 'vrecord -n start wavonly'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" stop >/dev/null 2>&1 || setup_failed 'vrecord stop'
  assert_file_exists "$(find -- "$RECORDING_DIR" -name 'wavonly_*.wav' -type f)" \
    "the WAV must be saved"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name 'wavonly_*.mp3' -type f)" \
    "no MP3 may be made when start had -n"

  start_test "-n with -t warns that the transcript is skipped"
  "$VRECORD" -n start -t wavtx >/dev/null 2>&1 || setup_failed 'vrecord -n start -t wavtx'
  out=$("$VRECORD" stop 2>&1) || true
  assert_contains "$out" 'Transcription skipped' "stop must say why there is no transcript"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name 'wavtx_*.mp3' -type f)" \
    "no MP3 may be made when start had -n"

  drop_stub_home "$sh"
}

test_many_recordings() {
  local -- sh newest base_pid
  local -i i rc
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  mkdir -p -- "$RECORDING_DIR" || setup_failed 'create the recording directory'
  for ((i = 0; i < 500; i+=1)); do
    : > "$RECORDING_DIR/voice_recording_20260101_$(printf '%06d' "$i").wav" || setup_failed 'create a recording'
  done
  touch -d '2026-01-01 00:00' -- "$RECORDING_DIR"/*.wav || setup_failed 'date the recordings'
  newest="$RECORDING_DIR"/voice_recording_20991231_235959.wav
  : > "$newest" || setup_failed 'create the newest recording'

  start_test "play opens the newest of 501 recordings (5 runs)"
  for ((i = 1; i <= 5; i+=1)); do
    : > "$HOME"/xdg-open.log || setup_failed 'empty the xdg-open log'
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
  sh=$(make_stub_home) || setup_failed 'make_stub_home'
  local -x HOME=$sh RECORDING_DIR=$sh/rec STATE_DIR=$sh/state BEEP_ENABLED=0
  "$VRECORD" start base >/dev/null 2>&1 || setup_failed 'vrecord start base'
  "$VRECORD" -n stop >/dev/null 2>&1 || setup_failed 'vrecord -n stop'
  base=$(find -- "$RECORDING_DIR" -name 'base_*.wav' -type f)

  start_test "an interrupted continuation survives a /tmp wipe (reboot)"
  "$VRECORD" start -c >/dev/null 2>&1 || setup_failed 'vrecord start -c'
  crashed=$(capture_pid) || setup_failed 'read the capture PID'
  crash_capture
  # Simulate the boot-time clean-up of /tmp, touching only this test's session
  for d in /tmp/vrecord.*/; do
    if [[ $(cat -- "$d"main_file 2>/dev/null) == "$base" ]]; then rm -rf -- "$d"; fi
  done
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$base")" "AUDIO:segment_1.wav:$crashed" \
    "the continuation must survive the wipe and be merged by stop"

  start_test "segments kept after a failed merge outlive the 7-day reaper"
  "$VRECORD" start -c >/dev/null 2>&1 || setup_failed 'vrecord start -c'
  out=$(STUB_FAIL=merge "$VRECORD" -n stop 2>&1) || true
  seg_dir=$(sed -n 's/.*Segments preserved in: //p' <<<"$out")
  [[ -z "$seg_dir" ]] || touch -d '10 days ago' -- "${seg_dir%/segments}" "$seg_dir"
  "$VRECORD" list >/dev/null 2>&1 || setup_failed 'vrecord list'
  assert_file_exists "$seg_dir/segment_1.wav" \
    "preserved segments must not be deleted (reported: '$seg_dir')"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name '.*' -type f)" \
    "a failed merge must not leave a temporary file beside the recordings"
  assert_success "a new recording must start after a failed merge" "$VRECORD" start next
  "$VRECORD" -n stop >/dev/null 2>&1 || true

  start_test "a stop killed mid-merge leaves no temp file, and a retry merges"
  "$VRECORD" start intr >/dev/null 2>&1 || setup_failed 'vrecord start intr'
  "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
  "$VRECORD" resume >/dev/null 2>&1 || setup_failed 'vrecord resume'
  second=$(capture_pid) || setup_failed 'read the capture PID'
  rm -f -- "$HOME"/stub-merging || setup_failed 'remove the merge marker'
  STUB_MERGE_DELAY=2 "$VRECORD" -n stop >/dev/null 2>&1 &
  stop_pid=$!
  for ((i = 0; i < 50; i+=1)); do [[ ! -f "$HOME"/stub-merging ]] || break; sleep 0.1; done
  # The kill must land mid-merge, or the assertions below prove nothing
  assert_file_exists "$HOME"/stub-merging "the merge must be under way when stop is killed"
  kill -TERM "$stop_pid" 2>/dev/null || true
  rc=0
  wait "$stop_pid" || rc=$?
  assert_equals 143 "$rc" "a stop killed by SIGTERM must exit 128+15"
  wav=$(find -- "$RECORDING_DIR" -name 'intr_*.wav' -type f)
  assert_not_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav" \
    "the kill must have stopped the merge before the rename (exit $rc)"
  assert_equals "" "$(find -- "$RECORDING_DIR" -name '.vrecord-merge.*' -type f)" \
    "an interrupted merge must remove its temporary file"
  "$VRECORD" -n stop >/dev/null 2>&1 || true
  assert_contains "$(cat -- "$wav")" "AUDIO:segment_1.wav:$second" \
    "a retried stop must merge the audio recorded after the pause"

  # A segment the count leaves out is not merged, and the merge then deletes it
  start_test "a resume that cannot save its segment count stays paused"
  if ((EUID == 0)); then
    echo "  Skipping: root ignores the read-only file this test relies on"
  else
    "$VRECORD" start ro >/dev/null 2>&1 || setup_failed 'vrecord start ro'
    "$VRECORD" pause >/dev/null 2>&1 || setup_failed 'vrecord pause'
    chmod -- a-w "$STATE_DIR"/session/segment_count || setup_failed 'make segment_count read-only'
    rc=0
    out=$("$VRECORD" resume 2>&1) || rc=$?
    second=$(capture_pid) || setup_failed 'read the capture PID'
    chmod -- u+w "$STATE_DIR"/session/segment_count || setup_failed 'make segment_count writable'
    assert_equals "1:paused:0" "$rc:$(vstatus)" "a failed resume must leave the session paused"
    assert_contains "$out" "Cannot write"
    assert_failure "the capture a failed resume started must be stopped" kill -0 "$second"
    "$VRECORD" -n stop >/dev/null 2>&1 || true
  fi

  drop_stub_home "$sh"
}

# Main test runner
main() {
  local -- suite=${1:-all}
  # The suite name becomes a command: only a defined test_* function may run
  [[ $suite == all ]] || declare -F -- "test_$suite" >/dev/null \
    || { >&2 echo "Unknown test suite ${suite@Q}"; exit 2; }

  echo "vrecord Test Suite"
  echo "=================="
  echo "Project dir: $PROJECT_DIR"
  echo "Test dir: $SCRIPT_DIR"
  echo
  
  # Trap to ensure cleanup, armed before anything is created
  trap cleanup_test_env EXIT
  # A step that fails outside an assertion ends the run (set -e): name it,
  # or the run just stops with no failing test and no summary
  set -o errtrace
  trap '>&2 printf "  ABORTED at line %d: %s (exit %d)\n" "$LINENO" "$BASH_COMMAND" "$?"' ERR

  # Set up test environment
  setup_test_env
  
  # Run test suites
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
    run_test_suite "Command Line" test_cli
    run_test_suite "Config" test_config
    run_test_suite "Locking" test_locking
    run_test_suite "Beep" test_beep
    run_test_suite "Format" test_format
    run_test_suite "Logs" test_logs
  else
    # Run specific test suite
    run_test_suite "$suite" "test_$suite"
  fi
  
  # Print summary. Its status is the run's result (1 if a check failed), not
  # an abort, so the ERR trap must not report it as one.
  trap - ERR
  print_test_summary
}

# Run tests
main "$@"
#fin