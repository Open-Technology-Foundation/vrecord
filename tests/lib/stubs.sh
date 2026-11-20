#!/usr/bin/env bash
# stubs.sh - deterministic stand-ins for ffmpeg, ffprobe, ffplay, transcribe
# and xdg-open. Part of vrecord test suite
#
# vrecord locks PATH to "$HOME/.local/bin:..." so executables placed there under
# a throwaway HOME replace the real tools without touching the audio device.
# A library: source it from a script that has already set strict mode.

[[ ${BASH_SOURCE[0]} != "$0" ]] || { >&2 echo "Error: ${0@Q} must be sourced"; exit 1; }

# make_stub_home: create a throwaway HOME holding the stubs and print its path.
#   ffmpeg capture  writes "AUDIO:<file>:<pid> fmt=<codec>/<rate>/<channels>"
#                   into its output, records its PID in $HOME/stub-capture.pid,
#                   appends the output path to $HOME/stub-captures.log, then
#                   runs until SIGTERM
#   ffmpeg concat   concatenates its inputs, so a merged recording shows exactly
#                   which pieces of audio reached it; parses the list as ffmpeg
#                   does ('...' quoting, backslash escapes); then touches
#                   $HOME/stub-merging and sleeps STUB_MERGE_DELAY seconds
#   ffmpeg (other)  MP3 conversion: touches $HOME/stub-converting, sleeps
#                   STUB_MP3_DELAY seconds, writes a small placeholder
#   ffprobe         reports the fmt= of a capture's first line; "MP3 of" files
#                   as MP3; anything else as 44.1 kHz stereo 16-bit PCM WAV
#   ffplay          records its PID in $HOME/stub-ffplay.pid and appends it to
#                   $HOME/stub-ffplay.log, then runs for STUB_BEEP_SECONDS
#                   seconds (default 0)
#   transcribe      writes "TRANSCRIPT of <mp3>" to <stem>.txt; also chats on
#                   stdout, as real tools may
# STUB_FAIL=capture|merge|mp3|probe|ffplay and STUB_TRANSCRIBE_FAIL=1 simulate
# failures.
make_stub_home() {
  local -- home bin
  home=$(mktemp -d -- "${TMPDIR:-/tmp}"/vrecord-test.XXXXXX) || return 1
  bin="$home"/.local/bin
  mkdir -p -- "$bin" || return 1

  # #!/bin/bash, not env: vrecord requires the process comm to be "ffmpeg"
  cat > "$bin"/ffmpeg <<'STUB' || return 1
#!/bin/bash
args=" $* "
if [[ $args == *' -devices '* ]]; then echo ' D  pulse  PulseAudio'; exit 0; fi
in='' out='' prev='' codec='' rate='' channels=''
for a in "$@"; do
  case $prev in
    -i)      in=$a ;;
    -acodec) codec=$a ;;
    -ar)     rate=$a ;;
    -ac)     channels=$a ;;
  esac
  [[ $a == -* ]] || out=$a
  prev=$a
done
in=${in#file:}
out=${out#file:}  # vrecord prefixes paths with ffmpeg's file: protocol
# concat_path: one "file '...'" line -> the path, tokenised as ffmpeg does
concat_path() {
  local s=${1#file } tok='' c
  local -i k q=0 esc=0
  for ((k = 0; k < ${#s}; k++)); do
    c=${s:k:1}
    if ((esc)); then tok+=$c; esc=0
    elif ((q)); then if [[ $c == "'" ]]; then q=0; else tok+=$c; fi
    elif [[ $c == "'" ]]; then q=1
    elif [[ $c == '\' ]]; then esc=1
    else tok+=$c
    fi
  done
  printf '%s' "$tok"
}
case $args in
  *' -f pulse '*)
    [[ ${STUB_FAIL:-} != capture ]] || { echo 'stub: capture failed' >&2; exit 1; }
    echo $$ > "$HOME"/stub-capture.pid
    printf '%s\n' "$out" >> "$HOME"/stub-captures.log
    printf 'AUDIO:%s:%s fmt=%s/%s/%s\n' "${out##*/}" $$ "$codec" "$rate" "$channels" > "$out"
    trap 'exit 255' TERM
    while :; do sleep 0.1; done ;;
  *' -f concat '*)
    [[ ${STUB_FAIL:-} != merge ]] || { echo 'stub: merge failed' >&2; exit 1; }
    : > "$out"
    while IFS= read -r line; do
      cat -- "$(concat_path "$line")" >> "$out" || exit 1
    done < "$in"
    : > "$HOME"/stub-merging
    sleep "${STUB_MERGE_DELAY:-0}" ;;
  *)
    [[ ${STUB_FAIL:-} != mp3 ]] || { echo 'stub: mp3 failed' >&2; exit 1; }
    : > "$HOME"/stub-converting
    sleep "${STUB_MP3_DELAY:-0}"
    printf 'MP3 of %s\n' "${in##*/}" > "$out" ;;
esac
STUB

  cat > "$bin"/ffprobe <<'STUB' || return 1
#!/bin/bash
[[ ${STUB_FAIL:-} != probe ]] || { echo 'stub: probe failed' >&2; exit 1; }
file=${*: -1}
file=${file#file:}
[[ -f $file ]] || { echo "stub: $file: No such file or directory" >&2; exit 1; }
first=$(head -n 1 -- "$file")
codec=pcm_s16le rate=44100 channels=2 format=wav
if [[ $first =~ \ fmt=([^/]*)/([^/]*)/([^/]*)$ ]]; then
  codec=${BASH_REMATCH[1]} rate=${BASH_REMATCH[2]} channels=${BASH_REMATCH[3]}
elif [[ $first == 'MP3 of '* ]]; then
  codec=mp3 format=mp3
fi
printf 'codec_name=%s\nsample_rate=%s\nchannels=%s\nformat_name=%s\n' \
  "$codec" "$rate" "$channels" "$format"
STUB

  cat > "$bin"/transcribe <<'STUB' || return 1
#!/bin/bash
[[ -z ${STUB_TRANSCRIBE_FAIL:-} ]] || { echo 'stub: transcription failed' >&2; exit 1; }
[[ ${1:-} != -- ]] || shift
echo 'stub transcribe: progress chatter on stdout'
printf 'TRANSCRIPT of %s\n' "${1##*/}" > "${1%.*}".txt
STUB

  cat > "$bin"/xdg-open <<'STUB' || return 1
#!/bin/bash
printf '%s\n' "$1" >> "$HOME"/xdg-open.log
STUB

  # exec: the PID recorded is the process that runs for STUB_BEEP_SECONDS
  cat > "$bin"/ffplay <<'STUB' || return 1
#!/bin/bash
echo $$ > "$HOME"/stub-ffplay.pid
echo $$ >> "$HOME"/stub-ffplay.log
[[ ${STUB_FAIL:-} != ffplay ]] || exit 1
exec sleep "${STUB_BEEP_SECONDS:-0}"
STUB
  chmod +x -- "$bin"/* || return 1
  printf '%s\n' "$home"
}

# crash_capture: SIGKILL the running capture stub, as an OOM kill or crash would
crash_capture() {
  kill -KILL "$(<"$HOME"/stub-capture.pid)" 2>/dev/null || true
  sleep 0.3
}

# capture_pid: PID of the most recently started capture stub
capture_pid() { cat -- "$HOME"/stub-capture.pid; }

# wait_for_file: wait up to 5 s for file $1 to exist; fail if it never does
wait_for_file() {
  local -i i
  for ((i = 0; i < 50; i+=1)); do
    [[ ! -e $1 ]] || return 0
    sleep 0.1
  done
  return 1
}

# drop_stub_home: stop any capture stub still running from HOME $1, remove it
drop_stub_home() {
  local -- home=$1
  pkill -f "$home/.local/bin/ffmpeg" 2>/dev/null || true
  rm -rf -- "$home"
}

#fin
