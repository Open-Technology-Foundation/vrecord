# vrecord - Voice Recorder with Resume Capability

Command-line voice recorder for Linux with pause/resume via signals, continue/append to existing recordings, automatic MP3 conversion, and optional transcription.

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

- **Pause/resume** via SIGSTOP/SIGCONT signals
- **Continue recordings** - append to existing WAV files
- **Automatic MP3** conversion (libmp3lame)
- **Transcription** integration (optional)
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

# Your recording is saved in ~/Recordings/
```

## Installation

### Automatic Installation (Recommended)

Use the install script for automatic setup with bash completion:

```bash
# System-wide installation (will prompt for sudo password)
./install.sh

# User-only installation (no sudo needed)
./install.sh --user

# Development installation (creates symlinks for testing)
./install.sh --dev

# See all options
./install.sh --help
```

The installer will:
- Check for required dependencies
- Install vrecord and bash completion
- Create configuration directory
- Generate an uninstall script

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
   sudo cp vrecord /usr/local/bin/
   
   # Or user-only
   mkdir -p ~/.local/bin
   cp vrecord ~/.local/bin/
   ```

4. Enable bash completion:
   ```bash
   # System-wide
   sudo cp .bash_completion /etc/bash_completion.d/vrecord

   # Or user-only
   mkdir -p ~/.local/share/bash-completion/completions
   cp .bash_completion ~/.local/share/bash-completion/completions/vrecord
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

Or manually remove:
```bash
sudo rm -f /usr/local/bin/vrecord
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

### Continue Previous Recordings

```bash
# Continue the most recent recording
vrecord start -c

# Resume a specific recording file
vrecord start -r voice_recording_20240115_143022.wav

# Start recording with transcription enabled
vrecord start -t podcast
```

**Note**: Filename prefixes must contain only alphanumeric characters, dots, underscores, and hyphens for security reasons.

### Other Commands

```bash
# Check recording status
vrecord status

# List all recordings
vrecord list

# List all files (not just WAV)
vrecord list --all

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
vrecord -n start -t # No MP3 conversion but transcribe enabled (won't transcribe without MP3. So don't do that.)

# Show version
vrecord -V
```

## Command Reference

### Commands

| Command | Description |
|---------|-------------|
| `start [PREFIX]` | Start new recording (default prefix: voice_recording) |
| `start -c` | Continue the most recent recording |
| `start -r FILE` | Resume a specific WAV file |
| `pause` | Pause active recording (SIGSTOP) |
| `resume` | Resume paused recording (SIGCONT) |
| `stop` | Stop recording, create MP3 |
| `status` | Show recording state and file info |
| `list [--all]` | List WAV files (or all files with --all) |

### Start Options

| Option | Description |
|--------|-------------|
| `-c, --continue-last` | Append to the most recent WAV file |
| `-r, --resume FILE` | Append to a specific WAV file |
| `-t, --transcribe` | Transcribe after MP3 conversion |

### Stop Options

| Option | Description |
|--------|-------------|
| `-t, --transcribe` | Transcribe the MP3 file |

### Global Options

| Option | Description |
|--------|-------------|
| `-n, --no-mp3` | Skip MP3 conversion |
| `-b, --no-beep` | Disable periodic beep reminders |
| `-v, --verbose` | Increase output verbosity |
| `-q, --quiet` | Suppress non-error output |
| `-h, --help` | Show help |
| `-V, --version` | Show version |

## Default File Locations

- **Recordings**: `~/Recordings/`
- **State files**: `~/.vrecord/`
- **Temporary files**: `/tmp/vrecord.XXXXXX/`
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

Config files are bash scripts that set variables directly (without the `VRECORD_` prefix).

### Beep Notifications

Configure beep notifications in your config file:
```bash
BEEP_ENABLED=1        # Enable beeps (0 to disable)
BEEP_INTERVAL=60      # Seconds between beeps
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

See `config.sample` for a complete example.

## How It Works

1. **Recording**: FFmpeg captures audio from PulseAudio default input
2. **Pause/Resume**: SIGSTOP suspends ffmpeg; SIGCONT resumes it
3. **Continue/Resume**: New audio records to segment files, merged on stop using ffmpeg concat demuxer
4. **State**: Session data stored in `/tmp/vrecord.XXXXXX/` (ffmpeg.pid, state, segments/)
5. **Locking**: flock(1) prevents concurrent instances; falls back to atomic rename
6. **Stop sequence**: SIGCONT (if paused) → SIGTERM → wait → SIGKILL (timeout)
7. **Conversion**: WAV → MP3 via libmp3lame at configured bitrate

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
- Check FFmpeg logs in `/tmp/vrecord.*/ffmpeg.log`

### Permission errors
- Ensure `~/Recordings/` directory is writable
- Check disk space: `df -h ~/Recordings`

### "Another instance is running" error
- Only one recording can be active at a time
- Check status: `vrecord status`
- If no recording is active but error persists, a stale lock may exist
- The script will automatically clean stale locks on next run

## Security

vrecord implements several security measures:

- **Input Validation**: All filenames and paths are validated to prevent command injection
- **Path Restrictions**: Recording files are restricted to the configured recording directory
- **Safe Characters**: Only alphanumeric characters, dots, underscores, and hyphens allowed in filenames
- **Atomic Locking**: Uses kernel-level file locking to prevent race conditions
- **No Shell Expansion**: User inputs are never passed directly to shell commands

## Requirements

- **Bash 5.2+** (uses `inherit_errexit`, `extglob`, `nullglob`)
- **FFmpeg** with PulseAudio support (`ffmpeg -devices | grep pulse`)
- **PulseAudio** (`pactl`)
- **Optional**: mediainfo (file info), gzip (log compression), transcribe (transcription)

## Development

### Testing

```bash
./run_tests.sh                           # Full test suite
./tests/test_vrecord.sh basic_commands   # Specific suite
./tests/test_vrecord.sh recording_basic
./tests/test_vrecord.sh pause_resume
```

### Code Standards

- `set -euo pipefail` with `inherit_errexit`
- 2-space indentation, ShellCheck compliant
- Follows [BCS (Bash Coding Standard)](https://github.com/Open-Technology-Foundation/bash-coding-standard)

## License

GPL-3.0-or-later - Copyright (C) 2024-2025 Open Technology Foundation

## Links

- **Repository**: [github.com/Open-Technology-Foundation/vrecord](https://github.com/Open-Technology-Foundation/vrecord)
- **Issues**: [github.com/Open-Technology-Foundation/vrecord/issues](https://github.com/Open-Technology-Foundation/vrecord/issues)
