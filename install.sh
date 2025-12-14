#!/usr/bin/env bash
# install.sh - Installer for vrecord voice recording tool
# 
# Usage:
#   ./install.sh [OPTIONS]
#   curl -fsSL https://example.com/vrecord/install.sh | bash
#
# Options:
#   --user      Install to user directory (~/.local/bin)
#   --system    Install system-wide (default)
#   --no-deps   Skip dependency check
#   --dev       Install from current directory (for development)
#   --dry-run   Show what would be installed without doing it
#   --help      Show this help message

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Script information
readonly SCRIPT_NAME="vrecord installer"
readonly VERSION="1.0"

# Colors for output (with TTY check)
if [[ -t 1 && -t 2 ]]; then
  readonly -- RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' BLUE=$'\033[0;34m' NOCOLOR=$'\033[0m'
else
  readonly -- RED='' GREEN='' YELLOW='' BLUE='' NOCOLOR=''
fi

# Default values
INSTALL_MODE="system"
CHECK_DEPS=1
DEV_MODE=0
DRY_RUN=0
SCRIPT_DIR=""

# Installation paths
USER_BIN_DIR="$HOME/.local/bin"
USER_COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
USER_DATA_DIR="$HOME/.vrecord"
SYSTEM_BIN_DIR="/usr/local/bin"
SYSTEM_COMPLETION_DIR=""  # Will be detected
SYSTEM_DATA_DIR="/usr/local/share/vrecord"

# URLs for remote installation
GITHUB_RAW_URL="https://raw.githubusercontent.com/Open-Technology-Foundation/vrecord/main"
VRECORD_URL="$GITHUB_RAW_URL/vrecord"
COMPLETION_URL="$GITHUB_RAW_URL/vrecord-completion.bash"
CONFIG_SAMPLE_URL="$GITHUB_RAW_URL/config.sample"
BEEP_URL="$GITHUB_RAW_URL/beep.mp3"

# Functions
info() { echo "${BLUE}[INFO]${NOCOLOR} $*"; }
success() { echo "${GREEN}[SUCCESS]${NOCOLOR} $*"; }
warn() { echo "${YELLOW}[WARN]${NOCOLOR} $*" >&2; }
error() { echo "${RED}[ERROR]${NOCOLOR} $*" >&2; }
die() { error "$@"; exit 1; }

show_help() {
    cat << EOF
$SCRIPT_NAME v$VERSION

Install vrecord voice recording tool with bash completion support.

USAGE:
    ./install.sh [OPTIONS]
    curl -fsSL $GITHUB_RAW_URL/install.sh | bash

OPTIONS:
    --user      Install to user directory (~/.local/bin)
    --system    Install system-wide (default)
    --no-deps   Skip dependency check
    --dev       Install from current directory (for development)
    --dry-run   Show what would be installed without doing it
    --help      Show this help message

EXAMPLES:
    # System-wide installation (default)
    ./install.sh

    # User installation (no sudo required)
    ./install.sh --user

    # Development installation from current directory
    ./install.sh --dev

    # One-liner remote installation
    curl -fsSL $GITHUB_RAW_URL/install.sh | bash

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user)
                INSTALL_MODE="user"
                shift
                ;;
            --system)
                INSTALL_MODE="system"
                shift
                ;;
            --no-deps)
                CHECK_DEPS=0
                shift
                ;;
            --dev)
                DEV_MODE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

# Detect system completion directory
detect_completion_dir() {
    local dirs=(
        "/etc/bash_completion.d"
        "/usr/share/bash-completion/completions"
        "/usr/local/share/bash-completion/completions"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            SYSTEM_COMPLETION_DIR="$dir"
            return 0
        fi
    done
    
    warn "Could not detect system bash completion directory"
    return 1
}

# Check if running with sudo when needed
check_sudo() {
    if [[ "$INSTALL_MODE" == "system" ]] && [[ "${EUID:-0}" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            warn "System installation requires sudo privileges"
            exec sudo "$0" "$@"
        else
            die "System installation requires root privileges"
        fi
    fi
}

# Check for required dependencies
check_dependencies() {
    ((CHECK_DEPS == 0)) && return 0
    
    info "Checking dependencies..."
    
    local missing=()
    
    # Check for required commands
    if ! command -v ffmpeg >/dev/null 2>&1; then
        missing+=("ffmpeg")
    fi
    
    if ! command -v pactl >/dev/null 2>&1; then
        missing+=("pulseaudio-utils")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        
        # Detect package manager and suggest install command
        if command -v apt-get >/dev/null 2>&1; then
            info "Install with: sudo apt-get install ${missing[*]}"
        elif command -v yum >/dev/null 2>&1; then
            info "Install with: sudo yum install ${missing[*]}"
        elif command -v pacman >/dev/null 2>&1; then
            info "Install with: sudo pacman -S ${missing[*]}"
        fi
        
        die "Please install missing dependencies and try again"
    fi
    
    # Check for optional dependencies
    if ! command -v gzip >/dev/null 2>&1; then
        warn "Optional dependency 'gzip' not found (used for log compression)"
    fi
    
    success "All required dependencies found"
}

# Create required directories
create_directories() {
    local bin_dir completion_dir config_dir data_dir
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        bin_dir="$USER_BIN_DIR"
        completion_dir="$USER_COMPLETION_DIR"
        config_dir="$HOME/.vrecord"
        data_dir="$USER_DATA_DIR"
    else
        bin_dir="$SYSTEM_BIN_DIR"
        completion_dir="$SYSTEM_COMPLETION_DIR"
        config_dir="$HOME/.vrecord"  # Config always goes to user home
        data_dir="$SYSTEM_DATA_DIR"
    fi
    
    # Create directories
    for dir in "$bin_dir" "$completion_dir" "$config_dir"; do
        if [[ ! -d "$dir" ]]; then
            if ((DRY_RUN)); then
                info "[DRY RUN] Would create directory: $dir"
            else
                info "Creating directory: $dir"
                mkdir -p "$dir"
            fi
        fi
    done
    
    # Create data directory for system installations
    if [[ "$INSTALL_MODE" == "system" ]] && [[ ! -d "$data_dir" ]]; then
        if ((DRY_RUN)); then
            info "[DRY RUN] Would create directory: $data_dir"
        else
            info "Creating directory: $data_dir"
            mkdir -p "$data_dir"
        fi
    fi
}

# Download file with progress
download_file() {
    local url="$1"
    local dest="$2"
    local desc="$3"
    
    if ((DRY_RUN)); then
        info "[DRY RUN] Would download $desc from $url to $dest"
        return 0
    fi
    
    info "Downloading $desc..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest" || die "Failed to download $desc"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$dest" || die "Failed to download $desc"
    else
        die "Neither curl nor wget found. Please install one of them."
    fi
}

# Install vrecord
install_vrecord() {
    local bin_dir src_file
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        bin_dir="$USER_BIN_DIR"
    else
        bin_dir="$SYSTEM_BIN_DIR"
    fi
    
    # Determine source file
    if ((DEV_MODE)); then
        if [[ -f "$SCRIPT_DIR/vrecord" ]]; then
            src_file="$SCRIPT_DIR/vrecord"
        else
            die "vrecord not found in current directory"
        fi
    else
        src_file="/tmp/vrecord.$$"
        download_file "$VRECORD_URL" "$src_file" "vrecord script"
    fi
    
    # Install the script
    if ((DRY_RUN)); then
        info "[DRY RUN] Would install vrecord to $bin_dir/vrecord"
    else
        info "Installing vrecord to $bin_dir/vrecord"
        if ((DEV_MODE)); then
            cp "$src_file" "$bin_dir/vrecord"
        else
            mv "$src_file" "$bin_dir/vrecord"
        fi
        chmod +x "$bin_dir/vrecord"
    fi
}

# Install bash completion
install_completion() {
    local completion_dir src_file
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        completion_dir="$USER_COMPLETION_DIR"
    else
        completion_dir="$SYSTEM_COMPLETION_DIR"
    fi
    
    # Skip if no completion directory found
    [[ -z "$completion_dir" ]] && return 0
    
    # Determine source file
    if ((DEV_MODE)); then
        if [[ -f "$SCRIPT_DIR/vrecord-completion.bash" ]]; then
            src_file="$SCRIPT_DIR/vrecord-completion.bash"
        else
            warn "vrecord-completion.bash not found in current directory"
            return 0
        fi
    else
        src_file="/tmp/vrecord-completion.$$.bash"
        download_file "$COMPLETION_URL" "$src_file" "bash completion"
    fi
    
    # Install completion
    if ((DRY_RUN)); then
        info "[DRY RUN] Would install bash completion to $completion_dir/vrecord"
    else
        info "Installing bash completion to $completion_dir/vrecord"
        if ((DEV_MODE)); then
            cp "$src_file" "$completion_dir/vrecord"
        else
            mv "$src_file" "$completion_dir/vrecord"
        fi
    fi
}

# Install sample config
install_config() {
    local config_dir="$HOME/.vrecord"
    local config_file="$config_dir/config.sample"
    local src_file
    
    # Skip if config already exists
    if [[ -f "$config_dir/config" ]]; then
        info "Config file already exists, skipping"
        return 0
    fi
    
    # Determine source file
    if ((DEV_MODE)); then
        if [[ -f "$SCRIPT_DIR/config.sample" ]]; then
            src_file="$SCRIPT_DIR/config.sample"
        else
            warn "config.sample not found in current directory"
            return 0
        fi
    else
        src_file="/tmp/vrecord-config.$$.sample"
        download_file "$CONFIG_SAMPLE_URL" "$src_file" "sample config"
    fi
    
    # Install sample config
    if ((DRY_RUN)); then
        info "[DRY RUN] Would install sample config to $config_file"
    else
        info "Installing sample config to $config_file"
        if ((DEV_MODE)); then
            cp "$src_file" "$config_file"
        else
            mv "$src_file" "$config_file"
        fi
    fi
}

# Install beep sound
install_beep() {
    local data_dir beep_file
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        data_dir="$USER_DATA_DIR"
    else
        data_dir="$SYSTEM_DATA_DIR"
    fi
    
    beep_file="$data_dir/beep.mp3"
    local src_file
    
    # Skip if beep already exists
    if [[ -f "$beep_file" ]]; then
        info "Beep sound already exists, skipping"
        return 0
    fi
    
    # Determine source file
    if ((DEV_MODE)); then
        if [[ -f "$SCRIPT_DIR/beep.mp3" ]]; then
            src_file="$SCRIPT_DIR/beep.mp3"
        else
            warn "beep.mp3 not found in current directory"
            return 0
        fi
    else
        src_file="/tmp/vrecord-beep.$$.mp3"
        download_file "$BEEP_URL" "$src_file" "beep sound"
    fi
    
    # Install beep file
    if ((DRY_RUN)); then
        info "[DRY RUN] Would install beep sound to $beep_file"
    else
        info "Installing beep sound to $beep_file"
        if ((DEV_MODE)); then
            cp "$src_file" "$beep_file"
        else
            mv "$src_file" "$beep_file"
        fi
    fi
}

# Create uninstall script
create_uninstall_script() {
    local uninstall_script="$HOME/.vrecord/uninstall.sh"
    local bin_dir completion_dir data_dir
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        bin_dir="$USER_BIN_DIR"
        completion_dir="$USER_COMPLETION_DIR"
        data_dir="$USER_DATA_DIR"
    else
        bin_dir="$SYSTEM_BIN_DIR"
        completion_dir="$SYSTEM_COMPLETION_DIR"
        data_dir="$SYSTEM_DATA_DIR"
    fi
    
    if ((DRY_RUN)); then
        info "[DRY RUN] Would create uninstall script at $uninstall_script"
        return 0
    fi
    
    info "Creating uninstall script"
    
    local sudo_cmd=""
    [[ "$INSTALL_MODE" == "system" ]] && sudo_cmd="sudo "
    
    cat > "$uninstall_script" << EOF
#!/bin/bash
# Uninstall script for vrecord
# Generated by install.sh on $(date)

set -euo pipefail

echo "Uninstalling vrecord..."

# Remove binary
if [[ -f "$bin_dir/vrecord" ]]; then
    echo "Removing $bin_dir/vrecord"
    ${sudo_cmd}rm -f "$bin_dir/vrecord"
fi

# Remove completion
if [[ -f "$completion_dir/vrecord" ]]; then
    echo "Removing $completion_dir/vrecord"
    ${sudo_cmd}rm -f "$completion_dir/vrecord"
fi

# Remove data directory (system installations only)
if [[ "$INSTALL_MODE" == "system" ]] && [[ -d "$data_dir" ]]; then
    echo "Removing $data_dir"
    ${sudo_cmd}rm -rf "$data_dir"
fi

# Ask about config removal
if [[ -d "\$HOME/.vrecord" ]]; then
    read -p "Remove configuration directory ~/.vrecord? [y/N] " -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]\$ ]]; then
        rm -rf "\$HOME/.vrecord"
        echo "Configuration removed"
    else
        echo "Configuration preserved at ~/.vrecord"
    fi
fi

echo "vrecord has been uninstalled"
EOF
    
    chmod +x "$uninstall_script"
}

# Update PATH if needed
check_path() {
    local bin_dir
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        bin_dir="$USER_BIN_DIR"
        
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            echo
            warn "$bin_dir is not in your PATH"
            info "Add this line to your ~/.bashrc or ~/.bash_profile:"
            info "  export PATH=\"\$PATH:$bin_dir\""
        fi
    fi
}

# Main installation function
main() {
    # Get script directory for dev mode
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Parse arguments
    parse_args "$@"
    
    # Check sudo if needed
    check_sudo "$@"
    
    echo "${GREEN}vrecord Installer${NOCOLOR}"
    echo "=================="
    info "Install mode: $INSTALL_MODE"
    ((DEV_MODE)) && info "Development mode: installing from $SCRIPT_DIR"
    ((DRY_RUN)) && warn "DRY RUN MODE - no changes will be made"
    echo
    
    # Run installation steps
    check_dependencies
    detect_completion_dir
    create_directories
    install_vrecord
    install_completion
    install_config
    install_beep
    create_uninstall_script
    check_path
    
    # Success message
    echo
    if ((DRY_RUN)); then
        success "Dry run completed - no changes were made"
    else
        success "vrecord has been installed successfully!"
    fi
    
    if [[ "$INSTALL_MODE" == "user" ]]; then
        info "Install location: $USER_BIN_DIR/vrecord"
    else
        info "Install location: $SYSTEM_BIN_DIR/vrecord"
    fi
    
    if ! ((DRY_RUN)); then
        info "Uninstall with: ~/.vrecord/uninstall.sh"
        
        # Test installation
        if command -v vrecord >/dev/null 2>&1; then
            echo
            info "Test installation with: vrecord --version"
        fi
    fi
}

# Run main function
main "$@"
#fin