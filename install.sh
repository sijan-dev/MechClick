#!/bin/bash
set -euo pipefail

# Colors
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_BLUE='\033[1;34m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_RESET='\033[0m'
info() { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
success() { printf "${C_GREEN}[SUCCESS]${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1"; exit 1; }

check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "Do not run the installer as root! It uses sudo only when strictly necessary."
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
    else error "Could not detect supported package manager. Install manually: jq, evtest (Linux), libnotify, alsa-utils.";
    fi
    info "Detected Package Manager: $PM"
}

install_dependencies() {
    local missing=()
    
    # Core CLI deps
    command -v jq &>/dev/null || missing+=("jq")
    command -v notify-send &>/dev/null || missing+=("libnotify")
    
    # Audio player
    if ! command -v aplay &>/dev/null && ! command -v paplay &>/dev/null && ! command -v play &>/dev/null && ! command -v afplay &>/dev/null; then
        missing+=("alsa-utils")
    fi

    # Global mode deps (Linux only)
    if [[ "$OS_ID" != "darwin" ]] && ! command -v evtest &>/dev/null; then
        missing+=("evtest")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing[*]}"
        read -r -p "Do you want to install them now using $PM? (y/n) " confirm
        if [[ "$confirm" == "y" ]]; then
            info "Installing missing packages..."
            local sudo_status=0
            case $PM in
                pacman) sudo pacman -S --noconfirm "${missing[@]}" || sudo_status=$? ;;
                apt) sudo apt update && sudo apt install -y "${missing[@]}" || sudo_status=$? ;;
                dnf) sudo dnf install -y "${missing[@]}" || sudo_status=$? ;;
                brew) brew install "${missing[@]}" || sudo_status=$? ;;
            esac
            if [[ $sudo_status -ne 0 ]]; then
                error "Failed to install packages. Please run the command manually and try again."
            else
                success "Dependencies installed!"
            fi
        else
            error "Cannot proceed without dependencies. Exiting."
        fi
    else
        success "All dependencies met."
    fi
}

deploy_config() {
    local target_dir="$HOME/.config/mechclick"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_dir="$script_dir/keys_sounds"

    if [[ ! -d "$source_dir" ]]; then
        error "Source directory '$source_dir' missing!"
    fi

    info "Deploying configuration to $target_dir..."
    mkdir -p "$target_dir"
    cp -r "$source_dir"/* "$target_dir/"
    success "Configuration and sound files deployed!"
}

install_binary() {
    local target_bin="$HOME/.local/bin/click"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_bin="$script_dir/click"

    mkdir -p "$(dirname "$target_bin")"

    if [[ ! -f "$source_bin" ]]; then
        error "Core 'click' script not found in $script_dir!"
    fi

    info "Installing binary to $target_bin..."
    cp "$source_bin" "$target_bin"
    chmod +x "$target_bin"
    
    # Check PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        warn "$HOME/.local/bin is not in your \$PATH."
        warn "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc."
    fi
    
    success "Binary installed. Run 'click' to start."
}

configure_linux_system() {
    # Input Group
    if ! groups "$USER" | grep -q "\binput\b"; then
        info "Adding $USER to the 'input' group..."
        sudo usermod -aG input "$USER"
        warn "Changes require a logout/login to take effect!"
        warn "Please log out and log back in (or reboot) before using 'click' in global mode."
    else
        success "User is already in the 'input' group."
    fi

    # Systemd User Service
    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/mechclick.service"
    mkdir -p "$service_dir"

    if [[ ! -f "$service_file" ]]; then
        info "Installing Systemd user service..."
        cat > "$service_file" <<EOF
[Unit]
Description=MechClick - Mechanical Keyboard Sound Simulator
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/click --mode global
Restart=on-failure

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable mechclick.service
        success "Systemd service installed and enabled!"
    else
        success "Systemd service already exists."
    fi
}

main() {
    local skip_deps=false
    if [[ "${1:-}" == "--skip-deps" ]]; then
        skip_deps=true
    fi

    info "Starting MechClick Installer..."
    check_root
    detect_os
    detect_package_manager
    if [[ "$skip_deps" == "false" ]]; then
        install_dependencies
    else
        warn "Skipping dependency installation..."
    fi
    deploy_config
    install_binary
    if [[ "$OS_ID" != "darwin" ]]; then
        configure_linux_system
    fi
    success "Pre-flight checks complete."
}

main "$@"
