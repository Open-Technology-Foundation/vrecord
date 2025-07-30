# vrecord - Voice Recorder with Resume Capability

A robust command-line voice recording tool for Linux that supports pause/resume functionality and automatic MP3 conversion.

## Quick Install

```bash
# One-liner installation (will prompt for sudo password)
curl -fsSL https://raw.githubusercontent.com/Open-Technology-Foundation/vrecord/main/install.sh | bash

# Or for user-only installation (no sudo required)
curl -fsSL https://raw.githubusercontent.com/Open-Technology-Foundation/vrecord/main/install.sh | bash -s -- --user

# Local installation from downloaded/cloned directory
./install.sh --dev
```

## Features

- **Record audio** from your default microphone
- **Pause and resume** recordings without losing data
- **Continue previous recordings** - append new audio to existing files
- **Automatic MP3 conversion** after recording stops
- **Beep notifications** - optional audio feedback every N seconds while recording
- **Simple command-line interface** with intuitive commands
- **Background recording** - continues even if you close the terminal
- **No data loss** - recordings are preserved even if interrupted

## Quick Start

```bash
# Start a new recording
./vrecord start

# Stop recording and save
./vrecord stop

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

# Stop recording (automatically converts to MP3)
vrecord stop
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
```

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

# Show version
vrecord -V
```

## Command Reference

### Global Options
- `-n, --no-mp3` - Skip MP3 conversion when stopping
- `-b, --no-beep` - Disable beep notifications for this session
- `-q, --quiet` - Suppress output except errors
- `-v, --verbose` - Increase verbosity
- `-h, --help` - Show help message
- `-V, --version` - Display version information

### Commands

| Command | Description |
|---------|-------------|
| `start [prefix]` | Start new recording with optional filename prefix |
| `start -c` | Continue the most recent recording |
| `start -r FILE` | Resume specific recording file |
| `pause` | Pause current recording |
| `resume` | Resume paused recording |
| `stop` | Stop recording and save file |
| `status` | Show current recording status |
| `list` | List WAV recordings |
| `list --all` | List all files in recordings directory |

## File Locations

- **Recordings**: `~/Recordings/`
- **State files**: `~/.vrecord/`
- **Temporary files**: `/tmp/vrecord.XXXXXX/`

## Configuration

vrecord supports configuration through multiple methods (in order of precedence):

1. **Environment variables** (highest priority)
   - `VRECORD_RECORDING_DIR` - Where to save recordings
   - `VRECORD_STATE_DIR` - State and config directory
   - `VRECORD_DEFAULT_PREFIX` - Default filename prefix
   - `VRECORD_MP3_BITRATE` - MP3 encoding bitrate

2. **User config file**: `~/.vrecord/config`
3. **System config file**: `/etc/vrecord/config`
4. **Built-in defaults** (lowest priority)

### Beep Notifications

Configure beep notifications in your config file:
```bash
BEEP_ENABLED=1        # Enable beeps (0 to disable)
BEEP_INTERVAL=60      # Seconds between beeps
BEEP_FILE="$STATE_DIR/beep.mp3"  # Custom beep sound
```

The installer includes a default beep sound. You can replace it with any MP3 file.

### Transcription

If you have a `transcribe` command available in your PATH, you can enable automatic transcription:
```bash
# Enable transcription when starting
vrecord start -t

# Or enable when stopping
vrecord stop -t
```

The transcription will run after the MP3 file is created. The `transcribe` command will be called with the MP3 filename as its argument.

**Note**: To use the transcription feature, install the transcribe tool from:
[https://github.com/Open-Technology-Foundation/transcribe](https://github.com/Open-Technology-Foundation/transcribe)

See `config.sample` for all available options.

## How It Works

1. **Recording**: Uses FFmpeg to capture audio from PulseAudio
2. **Pause/Resume**: Sends SIGSTOP/SIGCONT signals to FFmpeg process
3. **Continue**: Records new segments and merges them with the original file
4. **State Persistence**: Maintains recording state across script invocations
5. **Log Management**: Automatically rotates logs to prevent disk space issues
6. **Beep Notifications**: Background process plays audio feedback during active recording

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

## Requirements

- Linux with PulseAudio
- FFmpeg (with PulseAudio support)
- Bash 4.0+
- Optional: mediainfo (for detailed file information)

## License

GPL-3.0-or-later - see LICENSE file for details

## Author

Generated with Claude Code

## Repository

GitHub: [https://github.com/Open-Technology-Foundation/vrecord](https://github.com/Open-Technology-Foundation/vrecord)

---

For bug reports and feature requests, please use the GitHub issue tracker.