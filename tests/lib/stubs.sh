#!/usr/bin/env bash
# stubs.sh - deterministic stand-ins for ffmpeg, ffplay, transcribe and xdg-open
# Part of vrecord test suite
#
# vrecord locks PATH to "$HOME/.local/bin:..." so executables placed there under
# a throwaway HOME replace the real tools without touching the audio device.
# A library: source it from a script that has already set strict mode.

[[ ${BASH_SOURCE[0]} != "$0" ]] || { >&2 echo "Error: ${0@Q} must be sourced"; exit 1; }

# make_stub_home: create a throwaway HOME holding the stubs and print its path.
#   ffmpeg capture  writes "AUDIO:<file>:<pid>" into its output, records its PID
#                   in $HOME/stub-capture.pid, then runs until SIGTERM
#   ffmpeg concat   concatenates its inputs, so a merged recording shows exactly
#                   which pieces of audio reached it; then touches
#                   $HOME/stub-merging and sleeps STUB_MERGE_DELAY seconds
#   ffmpeg (other)  MP3 conversion: writes a small placeholder
#   transcribe      writes "TRANSCRIPT of <mp3>" to <stem>.txt; also chats on
#                   stdout, as real tools may
# STUB_FAIL=capture|merge|mp3 and STUB_TRANSCRIBE_FAIL=1 simulate failures.
make_stub_home() {
  local -- home bin
  home=$(mktemp -d -- "${TMPDIR:-/tmp}"/vrecord-test.XXXXXX)
  bin="$home"/.local/bin
  mkdir -p -- "$bin"

  # #!/bin/bash, not env: vrecord requires the process comm to be "ffmpeg"
  cat > "$bin"/ffmpeg <<'STUB'
#!/bin/bash
args=" $* "
if [[ $args == *' -devices '* ]]; then echo ' D  pulse  PulseAudio'; exit 0; fi
in='' out='' prev=''
for a in "$@"; do
  [[ $prev != -i ]] || in=$a
  [[ $a == -* ]] || out=$a
  prev=$a
done
out=${out#file:}  # vrecord prefixes output paths with ffmpeg's file: protocol
case $args in
  *' -f pulse '*)
    [[ ${STUB_FAIL:-} != capture ]] || { echo 'stub: capture failed' >&2; exit 1; }
    echo $$ > "$HOME"/stub-capture.pid
    printf 'AUDIO:%s:%s\n' "${out##*/}" $$ > "$out"
    trap 'exit 255' TERM
    while :; do sleep 0.1; done ;;
  *' -f concat '*)
    [[ ${STUB_FAIL:-} != merge ]] || { echo 'stub: merge failed' >&2; exit 1; }
    : > "$out"
    while IFS= read -r line; do
      line=${line#file \'}
      cat "${line%\'}" >> "$out"
    done < "$in"
    : > "$HOME"/stub-merging
    sleep "${STUB_MERGE_DELAY:-0}" ;;
  *)
    [[ ${STUB_FAIL:-} != mp3 ]] || { echo 'stub: mp3 failed' >&2; exit 1; }
    printf 'MP3 of %s\n' "${in##*/}" > "$out" ;;
esac
STUB

  cat > "$bin"/transcribe <<'STUB'
#!/bin/bash
[[ -z ${STUB_TRANSCRIBE_FAIL:-} ]] || { echo 'stub: transcription failed' >&2; exit 1; }
[[ ${1:-} != -- ]] || shift
echo 'stub transcribe: progress chatter on stdout'
printf 'TRANSCRIPT of %s\n' "${1##*/}" > "${1%.*}".txt
STUB

  cat > "$bin"/xdg-open <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >> "$HOME"/xdg-open.log
STUB

  printf '#!/bin/bash\nexit 0\n' > "$bin"/ffplay
  chmod +x -- "$bin"/*
  printf '%s\n' "$home"
}

# crash_capture: SIGKILL the running capture stub, as an OOM kill or crash would
crash_capture() {
  kill -KILL "$(<"$HOME"/stub-capture.pid)" 2>/dev/null || true
  sleep 0.3
}

# capture_pid: PID of the most recently started capture stub
capture_pid() { cat -- "$HOME"/stub-capture.pid; }

# drop_stub_home: stop any capture stub still running from HOME $1, remove it
drop_stub_home() {
  local -- home=$1
  pkill -f "$home/.local/bin/ffmpeg" 2>/dev/null || true
  rm -rf -- "$home"
}

#fin
