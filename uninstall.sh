#!/usr/bin/env bash
# uninstall.sh - Uninstaller for vrecord
# This is a template - the actual uninstall script is generated during installation

set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob

# Colors (with TTY check)
if [[ -t 1 && -t 2 ]]; then
  readonly -- RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' NOCOLOR=$'\033[0m'
else
  readonly -- RED='' GREEN='' YELLOW='' NOCOLOR=''
fi

error() { echo "${RED}[ERROR]${NOCOLOR} $*" >&2; }
warn() { echo "${YELLOW}[WARN]${NOCOLOR} $*" >&2; }
info() { echo "[INFO] $*"; }
success() { echo "${GREEN}[SUCCESS]${NOCOLOR} $*"; }

# Check common installation locations
check_and_remove() {
    local file="$1"
    local desc="$2"
    local need_sudo="$3"
    
    if [[ -f "$file" ]]; then
        info "Found $desc at: $file"
        
        if [[ "$need_sudo" == "yes" ]] && [[ "$EUID" -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                sudo rm -f "$file" && success "Removed $desc"
            else
                error "Need root privileges to remove $file"
                return 1
            fi
        else
            rm -f "$file" && success "Removed $desc"
        fi
    fi
}

main() {
    echo "vrecord Uninstaller"
    echo "==================="
    echo
    
    # Check system locations
    check_and_remove "/usr/local/bin/vrecord" "system binary" "yes"
    check_and_remove "/usr/bin/vrecord" "system binary" "yes"
    check_and_remove "/usr/local/bin/vrecord-loop" "system binary (vrecord-loop)" "yes"
    check_and_remove "/usr/bin/vrecord-loop" "system binary (vrecord-loop)" "yes"

    # Check user locations
    check_and_remove "$HOME/.local/bin/vrecord" "user binary" "no"
    check_and_remove "$HOME/bin/vrecord" "user binary" "no"
    check_and_remove "$HOME/.local/bin/vrecord-loop" "user binary (vrecord-loop)" "no"
    check_and_remove "$HOME/bin/vrecord-loop" "user binary (vrecord-loop)" "no"
    
    # Check completion files
    local completion_dirs=(
        "/etc/bash_completion.d"
        "/usr/share/bash-completion/completions"
        "/usr/local/share/bash-completion/completions"
        "$HOME/.local/share/bash-completion/completions"
    )
    
    for dir in "${completion_dirs[@]}"; do
        if [[ -f "$dir/vrecord" ]]; then
            local need_sudo="no"
            [[ "$dir" =~ ^/etc|^/usr ]] && need_sudo="yes"
            check_and_remove "$dir/vrecord" "bash completion" "$need_sudo"
        fi
    done
    
    # Ask about config directory
    if [[ -d "$HOME/.vrecord" ]]; then
        echo
        warn "Configuration directory found at: $HOME/.vrecord"
        read -p "Remove configuration and state files? [y/N] " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Show what will be removed
            info "Contents:"
            find "$HOME/.vrecord/" -maxdepth 1 -printf '  %M %u %g %8s %TY-%Tm-%Td %f\n' 2>/dev/null || find "$HOME/.vrecord/" -maxdepth 1 -exec stat --printf='  %A %U %G %8s %y %n\n' {} \;
            
            read -p "Are you sure? This cannot be undone. [y/N] " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$HOME/.vrecord"
                success "Configuration directory removed"
            else
                info "Configuration directory preserved"
            fi
        else
            info "Configuration directory preserved at: $HOME/.vrecord"
        fi
    fi
    
    # Check if any vrecord processes are running
    if pgrep -f "vrecord" >/dev/null 2>&1; then
        warn "vrecord processes are still running"
        info "You may want to stop them with: vrecord stop"
    fi
    
    echo
    success "vrecord uninstallation complete"
    
    # Check if vrecord is still in PATH
    if command -v vrecord >/dev/null 2>&1; then
        warn "vrecord is still in your PATH at: $(command -v vrecord)"
        info "You may have another installation or need to restart your shell"
    fi
}

# Confirm before proceeding
echo "This will uninstall vrecord from your system."
read -p "Continue? [y/N] " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    main
else
    echo "Uninstallation cancelled"
    exit 0
fi
#fin