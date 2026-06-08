#!/bin/bash
set -euo pipefail

# Colors
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_BLUE='\033[1;34m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_RESET='\033[0m'
info() { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
success() { printf "${C_GREEN}[SUCCESS]${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1"; exit 1; }

FORCE=false

confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    local msg="$1"
    printf "${C_CYAN}%s (y/n) ${C_RESET}" "$msg"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "Do not run the uninstaller as root! It uses sudo only when strictly necessary."
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID=$ID
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="darwin"
    else
        OS_ID="unknown"
    fi
}

detect_package_manager() {
    PM=""
    if command -v pacman &>/dev/null; then PM="pacman";
    elif command -v apt &>/dev/null; then PM="apt";
    elif command -v dnf &>/dev/null; then PM="dnf";
    elif command -v brew &>/dev/null; then PM="brew";
    fi
}

stop_systemd_service() {
    local service_file="$HOME/.config/systemd/user/mechclick.service"

    if [[ ! -f "$service_file" ]]; then
        info "Systemd service not found. Skipping."
        return 0
    fi

    if confirm "Stop and disable mechclick systemd service?"; then
        info "Stopping mechclick.service..."
        systemctl --user stop mechclick.service 2>/dev/null || true

        info "Disabling mechclick.service..."
        systemctl --user disable mechclick.service 2>/dev/null || true

        info "Removing service file..."
        rm -f "$service_file"

        info "Reloading systemd daemon..."
        systemctl --user daemon-reload 2>/dev/null || true

        success "Systemd service removed."
    else
        warn "Skipped systemd service removal."
    fi
}

remove_binary() {
    local target_bin="$HOME/.local/bin/click"

    if [[ ! -f "$target_bin" ]]; then
        info "Binary not found at $target_bin. Skipping."
        return 0
    fi

    if confirm "Remove binary at $target_bin?"; then
        rm -f "$target_bin"
        success "Binary removed."
    else
        warn "Skipped binary removal."
    fi
}

remove_packages() {
    local packages=("evtest" "jq" "alsa-utils" "libnotify")
    local to_remove=()

    for pkg in "${packages[@]}"; do
        case "$PM" in
            pacman) pacman -Qi "$pkg" &>/dev/null && to_remove+=("$pkg") ;;
            apt)    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && to_remove+=("$pkg") ;;
            dnf)    rpm -q "$pkg" &>/dev/null && to_remove+=("$pkg") ;;
            brew)   brew list "$pkg" &>/dev/null && to_remove+=("$pkg") ;;
        esac
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        info "No MechClick packages found to remove."
        return 0
    fi

    if confirm "Remove packages: ${to_remove[*]}?"; then
        info "Removing packages..."
        local sudo_status=0
        case $PM in
            pacman) sudo pacman -Rns --noconfirm "${to_remove[@]}" || sudo_status=$? ;;
            apt)    sudo apt remove -y "${to_remove[@]}" || sudo_status=$? ;;
            dnf)    sudo dnf remove -y "${to_remove[@]}" || sudo_status=$? ;;
            brew)   brew uninstall "${to_remove[@]}" || sudo_status=$? ;;
        esac
        if [[ $sudo_status -ne 0 ]]; then
            warn "Failed to remove some packages. You may need to remove them manually."
        else
            success "Packages removed."
        fi
    else
        warn "Skipped package removal."
    fi
}

remove_input_group() {
    if [[ "$OS_ID" == "darwin" ]]; then
        return 0
    fi

    if ! groups "$USER" | grep -q "\binput\b"; then
        info "User '$USER' is not in the 'input' group. Skipping."
        return 0
    fi

    if confirm "Remove user '$USER' from the 'input' group?"; then
        sudo gpasswd -d "$USER" input
        success "User removed from 'input' group. Logout/login required for changes to take effect."
    else
        warn "Skipped input group removal."
    fi
}

print_usage() {
    cat <<EOF
MechClick Uninstaller

Usage: uninstall.sh [OPTIONS]

Options:
  -f, --force    Skip all confirmation prompts
  -h, --help     Print this help message and exit
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f | --force) FORCE=true; shift ;;
            -h | --help) print_usage; exit 0 ;;
            *) error "Unknown option: $1" ;;
        esac
    done
}

main() {
    parse_args "$@"

    info "Starting MechClick Uninstaller..."
    check_root
    detect_os
    detect_package_manager

    if [[ -z "$PM" ]]; then
        warn "No supported package manager found. Package removal will be skipped."
    fi

    stop_systemd_service
    remove_binary
    remove_packages
    remove_input_group

    success "MechClick uninstalled."
    warn "Config files at ~/.config/mechclick/ were not removed."
}

main "$@"
