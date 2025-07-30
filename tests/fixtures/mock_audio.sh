#!/bin/bash
# mock_audio.sh - Mock audio setup for testing
# Creates fake PulseAudio environment for tests

# Mock pactl command
mock_pactl() {
  case "$1" in
    info)
      echo "Server String: /run/user/1000/pulse/native"
      echo "Library Protocol Version: 35"
      echo "Server Protocol Version: 35"
      echo "Is Local: yes"
      echo "Client Index: 266"
      echo "Tile Size: 65472"
      echo "User Name: testuser"
      echo "Host Name: testhost"
      echo "Server Name: pulseaudio"
      echo "Server Version: 15.99.1"
      ;;
    list)
      if [[ "$2" == "sources" ]]; then
        echo "Source #0"
        echo "	State: SUSPENDED"
        echo "	Name: alsa_input.pci-0000_00_1f.3.analog-stereo"
        echo "	Description: Built-in Audio Analog Stereo"
      fi
      ;;
  esac
  return 0
}

# Mock ffmpeg command for testing
mock_ffmpeg() {
  # Parse arguments to find output file
  local -- output_file=""
  local -- next_is_output=0
  
  for arg in "$@"; do
    if ((next_is_output)); then
      output_file="$arg"
      break
    fi
    if [[ ! "$arg" =~ ^- ]]; then
      output_file="$arg"
    fi
  done
  
  if [[ -n "$output_file" ]]; then
    # Create a small valid WAV file
    # WAV header for 1 second of silence at 44.1kHz, 16-bit stereo
    printf "RIFF" > "$output_file"
    printf "\x24\xB8\x02\x00" >> "$output_file"  # File size - 8
    printf "WAVE" >> "$output_file"
    printf "fmt " >> "$output_file"
    printf "\x10\x00\x00\x00" >> "$output_file"  # Subchunk size (16)
    printf "\x01\x00" >> "$output_file"          # Audio format (PCM)
    printf "\x02\x00" >> "$output_file"          # Channels (2)
    printf "\x44\xAC\x00\x00" >> "$output_file"  # Sample rate (44100)
    printf "\x10\xB1\x02\x00" >> "$output_file"  # Byte rate
    printf "\x04\x00" >> "$output_file"          # Block align
    printf "\x10\x00" >> "$output_file"          # Bits per sample
    printf "data" >> "$output_file"
    printf "\x00\xB8\x02\x00" >> "$output_file"  # Data size
    # Add some silence (zeros)
    dd if=/dev/zero bs=1024 count=176 >> "$output_file" 2>/dev/null
  fi
  
  # Simulate ffmpeg running in background
  if [[ "$@" =~ "pulse" ]]; then
    # This is a recording command, simulate background process
    sleep 30 &
    echo $!
  fi
  
  return 0
}

# Export mock functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f mock_pactl
  export -f mock_ffmpeg
fi
#fin