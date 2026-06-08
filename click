#!/usr/bin/env bash
# ==============================================================================
# MechClick - Mechanical Keyboard Sound Simulator
# Bash • evtest • Low Latency • Hotplug Support
# ==============================================================================
set -euo pipefail

# === ANSI COLORS ===
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_BLUE=$'\033[1;34m'
readonly C_CYAN=$'\033[1;36m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_DIM=$'\033[2m'
readonly C_RESET=$'\033[0m'

# === CONFIGURATION ===
readonly APP_NAME="mechclick"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PID_FILE="/tmp/$APP_NAME.pid"
readonly LOCK_DIR="/tmp/$APP_NAME.lock"

# Default config paths
readonly DEFAULT_CONFIG_DIR="$HOME/.config/$APP_NAME"
readonly LOCAL_CONFIG_DIR="$SCRIPT_DIR/keys_sounds"

# Sound player - try in order of preference
readonly PLAYERS=("aplay" "paplay" "play" "ffplay" "afplay")
PLAYER=""

# === UTILITY FUNCTIONS ===
print_status() {
    local level="$1"
    local msg="$2"
    local color=""

    case "$level" in
    INFO) color="$C_BLUE" ;;
    SUCCESS) color="$C_GREEN" ;;
    WARN) color="$C_YELLOW" ;;
    ERROR) color="$C_RED" ;;
    TOGGLE) color="$C_YELLOW" ;;
    VERBOSE) color="$C_DIM" ;;
    *) color="$C_RESET" ;;
    esac

    printf "%b[%s]%b %s\n" "$color" "$level" "$C_RESET" "$msg"
}

notify_user() {
    local title="$1"
    local msg="$2"
    if command -v notify-send &>/dev/null; then
        notify-send --app-name="MechClick" "$title" "$msg" 2>/dev/null || true
    fi
}

cleanup() {
    if [[ "$NOTIFY_ON_EXIT" == "true" ]]; then
        print_status "INFO" "Cleaning up..."
        jobs -p | xargs -r kill 2>/dev/null || true
        rm -f "$PID_FILE" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
        notify_user "MechClick" "Disabled"
    fi
}

trap cleanup EXIT INT TERM

# === BANNER ===
print_banner() {
    printf "%b╔══════════════════════════════════════════════════╗\n" "$C_CYAN"
    printf "║  %bMECHCLICK%b                                    ║\n" "$C_GREEN" "$C_CYAN"
    printf "║  %bBash • Hotplug • evtest • Cross-Platform%b     ║\n" "$C_DIM" "$C_CYAN"
    printf "╚══════════════════════════════════════════════════╝%b\n" "$C_RESET"
}

print_help() {
    cat <<EOF
MechClick - Mechanical Keyboard Sound Simulator

Usage: click [OPTIONS]

Options:
  -m, --mode <global|terminal>  Set operation mode (default: auto-detect)
  -s, --stop                    Stop any running background instance
  -c, --config <path>           Override JSON configuration path
  -v, --verbose                 Enable verbose output
  -h, --help                    Print this help message and exit
EOF
}

# === ARGUMENT PARSING ===
parse_args() {
    MODE=""
    CONFIG_PATH=""
    VERBOSE=false
    STOP=false
    NOTIFY_ON_EXIT=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -m | --mode) MODE="$2"; shift 2 ;;
        -s | --stop) STOP=true; shift ;;
        -c | --config) CONFIG_PATH="$2"; shift 2 ;;
        -v | --verbose) VERBOSE=true; shift ;;
        -h | --help) print_help; exit 0 ;;
        *) print_status "ERROR" "Unknown option: $1"; print_help; exit 1 ;;
        esac
    done

    # Auto-detect mode if empty
    if [[ -z "$MODE" ]]; then
        if [[ "$(uname)" == "Linux" ]] && command -v evtest &>/dev/null; then
            MODE="global"
        else
            MODE="terminal"
        fi
    fi
}

# === STEP 1: CHECK IF ALREADY RUNNING (TOGGLE) ===
check_already_running() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(<"$PID_FILE")

        if kill -0 "$old_pid" 2>/dev/null; then
            print_status "TOGGLE" "Stopping existing instance (PID $old_pid)..."
            kill -TERM "$old_pid" 2>/dev/null || true

            local count=0
            while kill -0 "$old_pid" 2>/dev/null && [[ $count -lt 50 ]]; do
                sleep 0.1
                ((count++))
            done

            rm -f "$PID_FILE"
            notify_user "MechClick" "Disabled"
            exit 0
        else
            rm -f "$PID_FILE"
        fi
    fi
}

# === STEP 2: ACQUIRE LOCK (PREVENT RACE CONDITIONS) ===
acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        print_status "ERROR" "Another instance is starting. Please wait."
        exit 1
    fi
}

# === STEP 3: CHECK ROOT (SAFETY) ===
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_status "ERROR" "Do NOT run as root! Run as your user."
        exit 1
    fi
}

# === STEP 4: CHECK DEPENDENCIES ===
check_dependencies() {
    local missing_deps=()

    if [[ "$MODE" == "global" ]]; then
        if ! command -v evtest &>/dev/null; then
            missing_deps+=("evtest")
        fi
    fi

    if ! command -v jq &>/dev/null; then
        missing_deps+=("jq")
    fi

    if ! command -v notify-send &>/dev/null; then
        print_status "WARN" "notify-send not found. Install 'libnotify' for notifications."
    fi

    for player in "${PLAYERS[@]}"; do
        if command -v "$player" &>/dev/null; then
            PLAYER="$player"
            break
        fi
    done

    if [[ -z "$PLAYER" ]]; then
        missing_deps+=("aplay (or paplay/sox/ffmpeg)")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        printf "\n%bInstall with:%b\n" "$C_CYAN" "$C_RESET"

        if command -v pacman &>/dev/null; then
            printf "  sudo pacman -S evtest jq alsa-utils libnotify\n"
        elif command -v apt &>/dev/null; then
            printf "  sudo apt install evtest jq alsa-utils libnotify-bin\n"
        elif command -v dnf &>/dev/null; then
            printf "  sudo dnf install evtest jq alsa-utils libnotify\n"
        elif command -v brew &>/dev/null; then
            printf "  brew install evtest jq alsa-utils libnotify\n"
        else
            printf "  Install: evtest jq alsa-utils libnotify\n"
        fi

        exit 1
    fi

    print_status "SUCCESS" "Dependencies OK (using $PLAYER for audio)"
}

# === STEP 5: CHECK PERMISSIONS (INPUT GROUP) ===
check_permissions() {
    if [[ "$MODE" == "global" ]]; then
        if ! groups "$USER" | grep -q "\binput\b"; then
            print_status "ERROR" "User '$USER' not in 'input' group"
            printf "       Run: %bsudo usermod -aG input $USER%b\n" "$C_CYAN" "$C_RESET"
            printf "       Then %bLOGOUT%b and log back in\n" "$C_RED" "$C_RESET"
            exit 1
        fi
    fi
}

# === STEP 6: LOAD CONFIGURATION ===
load_config() {
    # Determine CONFIG_DIR based on CONFIG_PATH or default locations
    local config_dir_to_use=""

    if [[ -n "$CONFIG_PATH" ]]; then
        if [[ -d "$CONFIG_PATH" ]]; then
            config_dir_to_use="$CONFIG_PATH"
        else
            config_dir_to_use="$(dirname "$CONFIG_PATH")"
        fi
    elif [[ -d "$DEFAULT_CONFIG_DIR" ]]; then
        config_dir_to_use="$DEFAULT_CONFIG_DIR"
    elif [[ -d "$LOCAL_CONFIG_DIR" ]]; then
        config_dir_to_use="$LOCAL_CONFIG_DIR"
    else
        print_status "ERROR" "Configuration directory not found."
        print_status "INFO" "Run 'install.sh' or ensure keys_sounds/ exists."
        exit 1
    fi

    # Resolve CONFIG_FILE path (defaults to config.json in the directory)
    if [[ -z "$CONFIG_PATH" ]]; then
        CONFIG_FILE="$config_dir_to_use/config.json"
    else
        if [[ -f "$CONFIG_PATH" ]]; then
            CONFIG_FILE="$CONFIG_PATH"
        else
            CONFIG_FILE="$config_dir_to_use/config.json"
        fi
    fi

    SOUND_DIR="$config_dir_to_use"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_status "ERROR" "Config not found: $CONFIG_FILE"
        exit 1
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        print_status "ERROR" "Invalid JSON in config file"
        exit 1
    fi

    print_status "SUCCESS" "Config loaded from $CONFIG_FILE"
}

# === STEP 7: CHECK SOUND FILES ===
check_sounds() {
    if [[ ! -d "$SOUND_DIR" ]]; then
        print_status "ERROR" "Sound directory not found: $SOUND_DIR"
        exit 1
    fi

    local sound_count
    sound_count=$(find "$SOUND_DIR" -type f \( -name "*.wav" -o -name "*.ogg" \) | wc -l)

    if [[ $sound_count -eq 0 ]]; then
        print_status "ERROR" "No sound files (.wav/.ogg) found in: $SOUND_DIR"
        exit 1
    fi

    print_status "SUCCESS" "Found $sound_count sound files"
}

# === STEP 8: PLAY SOUND FUNCTION ===
play_sound() {
    local sound_file="$1"

    case "$PLAYER" in
    aplay)
        aplay -q "$sound_file" 2>/dev/null &
        ;;
    paplay)
        paplay "$sound_file" 2>/dev/null &
        ;;
    play)
        play -q "$sound_file" 2>/dev/null &
        ;;
    ffplay)
        ffplay -nodisp -autoexit -loglevel quiet "$sound_file" 2>/dev/null &
        ;;
    afplay)
        afplay "$sound_file" 2>/dev/null &
        ;;
    esac
}

# === STEP 9: GET RANDOM DEFAULT SOUND ===
get_random_default() {
    local defaults
    mapfile -t defaults < <(jq -r '.defaults[]' "$CONFIG_FILE" 2>/dev/null)

    if [[ ${#defaults[@]} -eq 0 ]]; then
        local all_sounds=("$SOUND_DIR"/*.wav)
        if [[ -f "${all_sounds[0]}" ]]; then
            echo "${all_sounds[RANDOM % ${#all_sounds[@]}]}"
        fi
        return
    fi

    local random_default="${defaults[RANDOM % ${#defaults[@]}]}"
    echo "$SOUND_DIR/$random_default"
}

# === STEP 10: GET MAPPED SOUND FOR KEYCODE ===
get_mapped_sound() {
    local keycode="$1"
    local mapped
    mapped=$(jq -r ".mappings[\"$keycode\"] // empty" "$CONFIG_FILE" 2>/dev/null)

    if [[ -n "$mapped" ]]; then
        echo "$SOUND_DIR/$mapped"
    else
        get_random_default
    fi
}

# === STEP 11: MONITOR SINGLE DEVICE ===
monitor_device() {
    local device="$1"
    local device_name="$2"

    print_status "SUCCESS" "Monitoring: $device_name ($device)"

    evtest "$device" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ type\ 1\ \(EV_KEY\).*code\ ([0-9]+).*value\ 1 ]]; then
            local keycode="${BASH_REMATCH[1]}"
            local sound_file
            sound_file=$(get_mapped_sound "$keycode")

            if [[ "$VERBOSE" == "true" ]]; then
                print_status "VERBOSE" "Key Pressed: $keycode -> $(basename "$sound_file")"
            fi

            if [[ -f "$sound_file" ]]; then
                play_sound "$sound_file"
            fi
        fi
    done &

    echo $! >>"$PID_FILE.children"
}

# === STEP 12: DISCOVER AND MONITOR DEVICES ===
discover_devices() {
    local monitored_devices=()

    print_status "INFO" "Discovering input devices..."

    while IFS= read -r device; do
        if evtest --query "$device" EV_KEY &>/dev/null; then
            local device_name
            device_name=$(cat "/sys/class/input/$(basename "$device")/device/name" 2>/dev/null || echo "Unknown")

            if [[ ! " ${monitored_devices[*]} " =~ " ${device} " ]]; then
                monitored_devices+=("$device")
                monitor_device "$device" "$device_name"
            fi
        fi
    done < <(find /dev/input -name 'event*' 2>/dev/null)

    if [[ ${#monitored_devices[@]} -eq 0 ]]; then
        print_status "ERROR" "No keyboard devices found!"
        exit 1
    fi

    print_status "SUCCESS" "Monitoring ${#monitored_devices[@]} device(s)"
}

# === STEP 13: HOTPLUG MONITORING ===
hotplug_monitor() {
    print_status "INFO" "Hotplug monitoring enabled (3s interval)"

    while true; do
        sleep 3
        while IFS= read -r device; do
            if evtest --query "$device" EV_KEY &>/dev/null; then
                if ! pgrep -f "evtest $device" >/dev/null; then
                    local device_name
                    device_name=$(cat "/sys/class/input/$(basename "$device")/device/name" 2>/dev/null || echo "Unknown")
                    print_status "INFO" "New device detected!"
                    monitor_device "$device" "$device_name"
                fi
            fi
        done < <(find /dev/input -name 'event*' 2>/dev/null)
    done
}

# === TERMINAL MODE ===
terminal_mode() {
    print_status "INFO" "Engine started in Terminal Mode"
    print_status "INFO" "Press any key to play a sound (Ctrl+C to exit)"

    stty -echo -icanon time 0 min 1
    trap 'stty sane; exit 0' INT TERM

    while IFS= read -rsn1 _; do
        local sound_file
        sound_file=$(get_random_default)
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_status "VERBOSE" "Key Pressed -> $(basename "$sound_file")"
        fi

        play_sound "$sound_file"
    done
}

# === GLOBAL MODE ===
global_mode() {
    if [[ $EUID -eq 0 ]]; then
        print_status "ERROR" "Do not run global mode as root."
        exit 1
    fi

    check_permissions
    echo $$ >"$PID_FILE"
    touch "$PID_FILE.children"

    NOTIFY_ON_EXIT=true

    print_status "INFO" "Engine started in Global Mode"
    notify_user "MechClick" "Enabled"

    discover_devices
    hotplug_monitor
}

# === MAIN ===
main() {
    print_banner
    parse_args "$@"

    if [[ "$STOP" == "true" ]]; then
        check_already_running
        print_status "INFO" "No active instance found."
        exit 0
    fi

    check_already_running
    acquire_lock
    check_root

    # Dependencies and permissions are handled differently based on mode
    if [[ "$MODE" == "global" ]]; then
        check_dependencies
        global_mode
    else
        # Terminal mode only needs audio player
        for player in "${PLAYERS[@]}"; do
            if command -v "$player" &>/dev/null; then
                PLAYER="$player"
                break
            fi
        done
        if [[ -z "$PLAYER" ]]; then
            print_status "ERROR" "No audio player found (aplay, paplay, play, ffplay, afplay)."
            exit 1
        fi
        load_config
        check_sounds
        terminal_mode
    fi
}

main "$@"
