# Changelog

All notable changes to vrecord will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-07-30

### Added
- Configuration file support (system-wide and user-specific)
- Environment variable overrides for all configuration options
- Log rotation to prevent disk space issues
- Bash completion script for improved command-line experience
- Comprehensive test suite with assertion library
- Sample configuration file documenting all options
- One-liner install script with automatic setup
- Uninstall script for clean removal
- Beep notifications during active recording (configurable interval)
- `--no-beep` option to disable beep for specific sessions
- Optional `-t|--transcribe` flag for automatic transcription after MP3 creation
- Transcription support with external `transcribe` command

### Changed
- Fixed shellcheck warning by replacing `ls -t` with `find` command
- Improved disk space management with configurable thresholds
- Enhanced logging with automatic rotation and compression
- System installations now place beep.mp3 in /usr/local/share/vrecord/
- Beep file search now checks multiple standard locations

### Configuration Options
- `RECORDING_DIR` - Directory for saved recordings
- `STATE_DIR` - Directory for state and config files
- `DEFAULT_PREFIX` - Default filename prefix
- `MP3_BITRATE` - MP3 encoding bitrate
- `AUDIO_FORMAT` - Audio codec for recording
- `SAMPLE_RATE` - Audio sample rate
- `CHANNELS` - Number of audio channels
- `MIN_DISK_SPACE_MB` - Minimum required disk space
- `LOG_MAX_SIZE_MB` - Maximum log file size before rotation
- `LOG_MAX_FILES` - Number of rotated log files to keep

## [1.0.0] - 2024-12-01

### Initial Release
- Core recording functionality with FFmpeg and PulseAudio
- Pause and resume recordings using process signals
- Continue/append to existing recordings
- Automatic MP3 conversion with optional bypass
- Persistent state across script invocations
- Lock file mechanism to prevent concurrent instances
- Comprehensive error handling and validation
- List recordings with optional --all flag
- Status monitoring for active recordings
- GPL-3.0-or-later license