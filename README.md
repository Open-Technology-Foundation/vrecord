# vrecord - Voice Recorder with Resume Capability

Command-line voice recorder for Linux with pause/resume, continue/append to existing recordings, automatic MP3 conversion, and optional transcription.

## Quick Install

```bash
# One-liner installation (uses sudo)
curl -fsSL https://raw.githubusercontent.com/Open-Technology-Foundation/vrecord/main/install.sh | bash

# Or for user-only installation (no sudo required)
curl -fsSL https://raw.githubusercontent.com/Open-Technology-Foundation/vrecord/main/install.sh | bash -s -- --user

# Local installation from downloaded/cloned directory
./install.sh --dev
```

## Features

- **Pause/resume** - paused time is never recorded; a paused session survives a reboot
- **Continue recordings** - append to existing WAV files
- **Automatic MP3** conversion (libmp3lame)
- **Transcription** integration (optional)
- **Playback** - play recordings with `xdg-open` (`vrecord play`)
- **Beep notifications** - periodic audio reminder while recording
- **Background operation** - recordings persist after terminal closes
- **Secure** - input validation prevents injection and path traversal
- **Concurrent protection** - flock-based locking prevents conflicts

## Quick Start

```bash
# Start a new recording
vrecord start

# Stop recording and save
vrecord stop

# Stop and transcribe (-t, if transcribe tool is installed)
vrecord stop -t

# Play the most recent recording
vrecord play

# Your recording is saved in ~/Recordings/
```

## vrecord-loop - Quick Recording Loop

`vrecord-loop` is a companion script for rapid voice recordings with automatic transcription. It provides an interactive loop: record → stop → display transcription → repeat.

### Usage

```bash
# Start interactive recording loop
vrecord-loop

# With custom filename prefix
vrecord-loop meeting-notes

# Quiet mode (suppress non-error output)
vrecord-loop -q

# Send each transcript to another program: on stdin, or as a path via {{FILE}}
vrecord-loop -C 'tee -a ~/notes.txt'
vrecord-loop -C 'myapp --input {{FILE}}'
```

### How It Works

1. Recording starts automatically with transcription enabled
2. Press any key to stop recording
3. Recording is converted to MP3 and transcribed
4. Transcription is displayed
5. Press Enter to start next recording, or 'q' to quit

Ctrl-C (or SIGTERM) stops the current recording and saves it as a WAV, without MP3 or transcript.

### Options

| Option | Description |
|--------|-------------|
| `-C, --call CMD` | Send each transcription to CMD (overrides `CALL_APP`) |
| `-v, --verbose` | Enable verbose output (default) |
| `-q, --quiet` | Suppress non-error output |
| `-h, --help` | Show help |
| `-V, --version` | Show version |

`CMD` is a shell command, run by bash, so quotes and pipes work. The transcript goes to its stdin; if `CMD` contains `{{FILE}}`, that placeholder is replaced by the transcript's path instead (passed as data, never as shell code).

The loop runs `vrecord` and `transcribe` from a fixed PATH (`~/.local/bin`, then the system directories), so an inherited PATH cannot substitute them. `CMD` is your own command and runs with your PATH.

**Requires**: vrecord; the `transcribe` command for transcripts (the loop warns if it is missing)

## Installation

### Automatic Installation (Recommended)

Use the install script for automatic setup with bash completion:

```bash
# System-wide installation (will prompt for sudo password)
./install.sh

# User-only installation (no sudo needed)
./install.sh --user

# Development installation (copies from this checkout)
./install.sh --dev

# See all options
./install.sh --help
```

The installer will:
- Check for required dependencies
- Install vrecord and bash completion
- Create configuration directory
- Generate an uninstall script

### Using make

From a cloned directory:

```bash
sudo make install      # vrecord + vrecord-loop to /usr/local/bin, beep and
                       # config.sample to /usr/local/share/vrecord, completion
                       # to /etc/bash_completion.d (if present); then runs 'make check'
make check             # Verify the installed commands are the ones found in PATH
make help              # Targets and variables
```

`PREFIX`, `BINDIR`, `DATADIR`, `COMPDIR` and `DESTDIR` can be overridden, e.g. `make DESTDIR=/tmp/pkg install` for a staged package build. vrecord finds the beep sound under `/usr/local/share/vrecord` or `/usr/share/vrecord`; with any other `PREFIX`, set `BEEP_FILE` in `~/.vrecord/config`. A bare `make` only prints help.

### Manual Installation

1. Ensure you have the required dependencies:
   ```bash
   sudo apt-get install ffmpeg pulseaudio
   # Optional: for compressed logs
   sudo apt-get install gzip
   ```

2. Make the script executable:
   ```bash
   chmod +x vrecord
   ```

3. Copy to your PATH:
   ```bash
   # System-wide
   sudo cp vrecord vrecord-loop /usr/local/bin/

   # Or user-only
   mkdir -p ~/.local/bin
   cp vrecord vrecord-loop ~/.local/bin/
   ```

4. Enable bash completion:
   ```bash
   # System-wide
   sudo cp vrecord-completion.bash /etc/bash_completion.d/vrecord

   # Or user-only
   mkdir -p ~/.local/share/bash-completion/completions
   cp vrecord-completion.bash ~/.local/share/bash-completion/completions/vrecord
   ```

5. (Optional) Configure settings:
   ```bash
   # Copy sample config and customize
   mkdir -p ~/.vrecord
   cp config.sample ~/.vrecord/config
   nano ~/.vrecord/config
   ```

### Uninstallation

If installed with the installer:
```bash
~/.vrecord/uninstall.sh
```

If installed with `make` (use the same variables as for install):
```bash
sudo make uninstall    # Recordings and ~/.vrecord are kept
```

Or manually remove:
```bash
sudo rm -f /usr/local/bin/vrecord /usr/local/bin/vrecord-loop
sudo rm -f /etc/bash_completion.d/vrecord
rm -rf ~/.vrecord  # Optional: remove config
```

## Usage Examples

### Basic Recording

```bash
# Start recording with default name (voice_recording_TIMESTAMP.wav)
vrecord start

# Start recording with custom prefix
vrecord start interview
# Creates: interview_20240115_143022.wav

# Start with transcription enabled
vrecord start -t meeting

# Stop recording (automatically converts to MP3)
vrecord stop

# Stop and transcribe
vrecord stop -t
```

### Pause and Resume

```bash
# Pause the current recording
vrecord pause

# Resume recording
vrecord resume
```

Pause ends the current segment; resume records a new one, and `stop` merges them into a single WAV. While a recording is paused or interrupted (e.g. ffmpeg crashed), `start` refuses to begin another: run `resume` or `stop` first. `stop` saves whatever was recorded.

### Continue Previous Recordings

```bash
# Continue the most recent recording
vrecord start -c

# Resume a specific recording file
vrecord start -r voice_recording_20240115_143022.wav

# Start recording with transcription enabled
vrecord start -t podcast
```

Only PCM WAV files can be continued. The new audio is recorded at the file's own sample rate and channel count, whatever the configuration says, so the merged file plays at the right speed.

**Note**: Filename prefixes, including `DEFAULT_PREFIX`, must contain only alphanumeric characters, dots, underscores, and hyphens for security reasons, and may not start with a dot (a hidden recording) or a hyphen.

### Other Commands

```bash
# Check recording status
vrecord status

# List all recordings
vrecord list

# List all files (not just WAV)
vrecord list --all

# Play a recording (most recent if no name given; .wav optional)
vrecord play
vrecord play voice_recording_20240115_143022

# Skip MP3 conversion
vrecord -n start
vrecord stop  # Won't create MP3

# Disable beep notifications
vrecord -b start
# Or: vrecord --no-beep start

# Enable transcription globally
vrecord start -t    # Start with transcription
vrecord stop        # Will transcribe if started with -t
vrecord stop -t     # Or, you can decide to transcribe when stopping
vrecord -n start -t # Transcription needs the MP3: stop warns and makes no transcript

# Show version
vrecord -V
```

### Status in Scripts

`vrecord status` prints one word on stdout, with details on stderr, and its exit status matches:

| Output | Exit | Meaning |
|--------|-----:|---------|
| `recording` | 0 | Recording now |
| `paused` | 0 | Paused; `resume` or `stop` |
| `interrupted` | 1 | The recorder died (crash, reboot); `stop` saves what was recorded |
| `idle` | 3 | No session |

```bash
state=$(vrecord -q status) || true   # "-q" silences the details, not the word
[[ $state == idle ]] && echo "free to record"
```

## Command Reference

### Commands

| Command | Description |
|---------|-------------|
| `start [PREFIX]` | Start new recording (default prefix: voice_recording) |
| `start -c` | Continue the most recent recording |
| `start -r FILE` | Resume a specific WAV file |
| `pause` | Pause recording (ends the current segment) |
| `resume` | Resume recording into a new segment (merged on stop) |
| `stop` | Stop recording, create MP3; prints the saved WAV path on stdout |
| `status` | Print the state on stdout (exit 0 recording/paused, 1 interrupted, 3 idle); details on stderr |
| `list [--all]` | List WAV files (or all files with --all) |
| `play [FILE]` | Play a recording with `xdg-open` (most recent if FILE omitted; `.wav` optional) |

### Start Options

| Option | Description |
|--------|-------------|
| `-c, --continue-last` | Append to the most recent WAV file |
| `-r, --resume FILE` | Append to a specific WAV file (PCM WAV only, recorded in its format) |
| `-t, --transcribe` | Transcribe after MP3 conversion |

### Stop Options

| Option | Description |
|--------|-------------|
| `-t, --transcribe` | Transcribe the MP3 file |

### Global Options

| Option | Description |
|--------|-------------|
| `-n, --no-mp3` | Skip MP3 conversion (given at `start`, it holds until `stop`); also skips transcription |
| `-b, --no-beep` | Disable periodic beep reminders |
| `-v, --verbose` | Also show debug messages |
| `-q, --quiet` | Suppress non-error output |
| `-h, --help` | Show help |
| `-V, --version` | Show version |

Short options can be bundled: `vrecord start -tn` is `vrecord start -t -n`.

## Default File Locations

- **Recordings**: `~/Recordings/`
- **State files**: `~/.vrecord/`
- **Active session**: `~/.vrecord/session/` (state and segments; removed by a successful `stop`)
- **Recovered sessions**: `~/.vrecord/recovered_*/` (kept after a failed merge; never deleted automatically)
- **Logs**: `~/.vrecord/logs/` (`ffmpeg.log`, `merge.log`, `mp3_convert.log`; rotated at `LOG_MAX_SIZE_MB`, deleted after 30 days)
- **System beep file**: `/usr/local/share/vrecord/beep.mp3` (system installation)
- **User beep file**: `~/.vrecord/beep.mp3` (user installation)

## Configuration

Configuration precedence (highest to lowest):

1. **Environment variables** (`VRECORD_*` prefix)
2. **User config**: `~/.vrecord/config`
3. **System config**: `/etc/vrecord/config`
4. **Built-in defaults**

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VRECORD_RECORDING_DIR` | Where WAV/MP3 files are saved | `~/Recordings` |
| `VRECORD_STATE_DIR` | Persistent state directory | `~/.vrecord` |
| `VRECORD_DEFAULT_PREFIX` | Filename prefix when none specified | `voice_recording` |
| `VRECORD_MP3_BITRATE` | libmp3lame bitrate | `192k` |

Config files are bash scripts that set variables directly (without the `VRECORD_` prefix). A config file with a syntax error, or one that would end vrecord (such as `SAMPLE_RATE=abc`), is ignored as a whole, with a warning.

### Beep Notifications

Configure beep notifications in your config file:
```bash
BEEP_ENABLED=1        # Enable beeps (0 to disable)
BEEP_INTERVAL=60      # Seconds between beeps (at least 1)
BEEP_FILE="$STATE_DIR/beep.mp3"  # Custom beep sound
```

The installer includes a default beep sound. You can replace it with any tiny MP3 file that emits a non-distracting pip while recording is in progress.

### Transcription

If you have a `transcribe` command available in your PATH, you can enable automatic transcription:
```bash
# Enable transcription when starting
vrecord start -t

# Or enable when stopping
vrecord stop -t
```

The transcription will run after the MP3 file is created. The `transcribe` command will be called with the MP3 filename as its argument.

**Note**: If you have OPENAI_API_KEY, you can use the transcription feature.  Install the transcribe tool from:
[https://github.com/Open-Technology-Foundation/transcribe](https://github.com/Open-Technology-Foundation/transcribe).  Use will require OPENAI_API_KEY.

### Audio Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `AUDIO_FORMAT` | WAV codec | `pcm_s16le` (16-bit PCM) |
| `SAMPLE_RATE` | Sample rate (Hz) | `44100` |
| `CHANNELS` | Mono (1) or stereo (2) | `2` |
| `MIN_DISK_SPACE_MB` | Minimum free space to start | `100` |
| `LOG_MAX_SIZE_MB` | Rotate logs when exceeded | `10` |
| `LOG_MAX_FILES` | Rotated log files to keep | `5` |

These settings, and `BEEP_ENABLED`/`BEEP_INTERVAL`, can also come from the environment (`SAMPLE_RATE=48000 vrecord start`), unless a config file sets them. A numeric value from the environment that is not a whole number (`CHANNELS=stereo`) is ignored with a warning, and the default applies.

See `config.sample` for a complete example.

## How It Works

1. **Recording**: FFmpeg captures audio from PulseAudio default input
2. **Pause/Resume**: pause stops ffmpeg cleanly (SIGTERM); resume starts a new ffmpeg into the next segment file. ffmpeg is not suspended with SIGSTOP: the audio server buffers a suspended stream (about 24 s) and delivers it on resume, so short pauses would be recorded.
3. **Continue/Resume**: New audio records to segment files, in the original's format, merged on stop using ffmpeg concat demuxer. The merged file is written beside the original and renamed over it, so the replacement is atomic.
4. **State**: Session data stored in `~/.vrecord/session/` (state, ffmpeg.pid, segments/). Not `/tmp`, which is wiped at boot.
5. **Locking**: flock(1) prevents concurrent instances; a command waits up to 5 s for the lock. `stop` releases it before MP3 conversion and transcription, so a new recording can start meanwhile.
6. **Stop sequence**: SIGTERM → wait → SIGKILL (timeout); a paused session has no recorder to stop
7. **Conversion**: WAV → MP3 via libmp3lame at configured bitrate
8. **Long recordings**: past 4 GB (about 6.7 hours at the defaults) a WAV file switches to the RF64 format, which ffmpeg and most audio tools read

## Tips

- Recordings continue in the background even if you close the terminal
- Use `vrecord status` to check if a recording is active
- The script prevents multiple simultaneous recordings
- Original WAV files are preserved alongside MP3 versions
- Use `Ctrl+C` safely - recordings won't be lost

## Troubleshooting

### No sound recorded
- Check your microphone is connected and working
- Ensure PulseAudio is running: `pactl info`
- Check default input device: `pactl list sources`

### FFmpeg errors
- Verify FFmpeg has PulseAudio support: `ffmpeg -devices 2>&1 | grep pulse`
- Check FFmpeg logs in `~/.vrecord/logs/ffmpeg.log`

### Permission errors
- Ensure `~/Recordings/` directory is writable
- Check disk space: `df -h ~/Recordings`

### "Another instance is running" error
- Another vrecord command held the lock for more than 5 s, e.g. a `stop` merging a long recording
- Run the command again once that one has finished
- The lock is released when the process holding it exits, so a stale lock cannot persist

## Security

vrecord implements several security measures:

- **Input Validation**: All filenames and paths are validated to prevent command injection
- **Path Restrictions**: Recording files are restricted to the configured recording directory
- **Safe Characters**: Only alphanumeric characters, dots, underscores, and hyphens allowed in filenames; a prefix may not start with a dot or hyphen
- **Atomic Locking**: Uses kernel-level file locking to prevent race conditions
- **No Shell Expansion**: User inputs are never passed directly to shell commands

## Requirements

- **Bash 5.2+** (uses `inherit_errexit`, `extglob`, `nullglob`)
- **FFmpeg** with PulseAudio support (`ffmpeg -devices | grep pulse`)
- **PulseAudio** (`pactl`)
- **Optional**: mediainfo (file info), gzip (log compression), transcribe (transcription), xdg-open (playback)

## Development

### Testing

```bash
make test                                # Full test suite (same as ./run_tests.sh)
make test SUITE=loop                     # One suite
make lint                                # shellcheck on all scripts
./tests/test_vrecord.sh basic_commands   # Specific suite, without the audio-server check
./tests/test_vrecord.sh recording_basic
./tests/test_vrecord.sh pause_resume
./tests/test_vrecord.sh play
./tests/test_vrecord.sh session_recovery # Stub-tool suites: no audio device needed
./tests/test_vrecord.sh loop
```

The recording suites need a live PulseAudio/PipeWire server and capture a few seconds from the default input. The `pause_segments`, `session_recovery`, `session_durability`, `loop`, `no_mp3`, `many_recordings`, `cli`, `config`, `locking`, `beep`, `format` and `logs` suites use stub tools from `tests/lib/stubs.sh` instead.

### Code Standards

- `set -euo pipefail` with `inherit_errexit`
- 2-space indentation, ShellCheck compliant
- Follows [BCS (Bash Coding Standard)](https://github.com/Open-Technology-Foundation/bash-coding-standard)

## License

GPL-3.0-or-later - Copyright (C) 2024-2025 Open Technology Foundation

## Links

- **Repository**: [github.com/Open-Technology-Foundation/vrecord](https://github.com/Open-Technology-Foundation/vrecord)
- **Issues**: [github.com/Open-Technology-Foundation/vrecord/issues](https://github.com/Open-Technology-Foundation/vrecord/issues)
