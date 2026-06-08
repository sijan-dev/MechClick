# MechClick

A lightweight, high-performance mechanical keyboard sound simulator for Unix-based systems. 
Built entirely in Bash, MechClick intercepts keyboard events to deliver authentic, low-latency switch sounds globally across your system or locally within your terminal.

## Features

- **Global System-Wide Audio**: Uses Linux `evtest` to capture hardware keycodes and play sounds system-wide in the background.
- **Cross-Platform Terminal Mode**: Falls back to raw `stdin` monitoring on macOS, BSD, and Linux for local terminal typing sounds.
- **Zero-Overhead Architecture**: Pure Bash implementation with asynchronous audio playback via `aplay`, `paplay`, or `sox`.
- **Hotplug Support**: Automatically detects and attaches to newly connected keyboards without restarting the service.
- **Automated Setup**: Includes a fully guided installer script that handles OS detection, dependency resolution, and Systemd integration.

## Dependencies

MechClick relies on standard Unix utilities. The installer will automatically detect and prompt you to install these:

- **Core**: `jq`, `libnotify` (`notify-send`)
- **Linux (Global Mode)**: `evtest`, `alsa-utils` (or `pulseaudio-utils`)
- **Audio Playbackers**: Auto-detected in order of preference: `aplay`, `paplay`, `play` (SoX), `ffplay`, `afplay` (macOS)

## Installation

Clone the repository and run the interactive setup script:

```bash
git clone https://github.com/Sijan-Bhusal/MechClick.git
cd MechClick
chmod +x install.sh
./install.sh
```

The setup script will:
1. Detect your OS and package manager (`pacman`, `apt`, `dnf`, `brew`).
2. Prompt to install missing system dependencies via `sudo`.
3. Deploy the sound assets and configuration to `~/.config/mechclick/`.
4. Install the `click` binary to `~/.local/bin/`.
5. On Linux, add your user to the `input` group and install a Systemd user service for background startup.

> **Note:** If the installer modifies your user group permissions, you **must log out and log back in** (or reboot) for the changes to take effect.

## Usage

MechClick runs in two distinct modes:

### Global Mode (Linux Only)
Runs in the background and plays typing sounds system-wide while you type in any application.

```bash
click --mode global
```

To manage the Systemd background service (installed automatically):
```bash
# Start the background service
systemctl --user start mechclick

# Stop the background service
click --stop

# Enable auto-start on login
systemctl --user enable mechclick
```

### Terminal Mode (All Platforms)
Listens strictly to keystrokes within the active terminal window. Ideal for macOS, BSD, or local testing.

```bash
click --mode terminal
```

### CLI Options

| Option | Description |
|---|---|
| `-m`, `--mode <global\|terminal>` | Explicitly select operation mode (defaults to `global`). |
| `-s`, `--stop` | Stops any active background instances gracefully. |
| `-c`, `--config <path>` | Override the default JSON configuration path. |
| `-v`, `--verbose` | Enable verbose output (prints active devices and keycodes). |
| `-h`, `--help` | Prints the complete usage guide. |

## Configuration

MechClick uses a JSON configuration file to map hardware keycodes to specific `.wav` files.

**Default location:** `~/.config/mechclick/config.json`

```json
{
  "defaults": ["key1.wav", "key3.wav", "key4.wav"],
  "mappings": {
    "28": "ent.wav",
    "57": "space1.wav",
    "42": "shift.wav"
  }
}
```

- **`defaults`**: An array of fallback sound files to play randomly if a specific keycode mapping is not found.
- **`mappings`**: A dictionary mapping Linux input event codes (integers) to specific sound filenames.

## Troubleshooting

### "No keyboard devices found!" in Global Mode

Your user is not in the `input` group. Fix:

```bash
sudo usermod -aG input $USER
```

Then **log out and log back in** (or reboot) for the change to take effect.

### Toggle does not stop sounds

If pressing the toggle keybind shows "Disabled" but sounds keep playing, kill any lingering processes and restart:

```bash
pkill -f "click --mode"
rm -f /tmp/mechclick.pid /tmp/mechclick.pid.children
rmdir /tmp/mechclick.lock 2>/dev/null
```

Then run `click` again.

### Terminal mode gives "stdin is not a tty"

You are running terminal mode from a non-interactive context (script, subprocess, keybind that doesn't preserve the terminal). Run it directly in your terminal:

```bash
click --mode terminal
```

### evtest permission denied

Make sure you are not running as root. Run as your normal user. If you still get permission errors, verify you are in the `input` group:

```bash
groups $USER
```

### No sound plays

Check that an audio player is installed. MechClick tries these in order: `aplay`, `paplay`, `play` (SoX), `ffplay`, `afplay`.

```bash
# Arch
sudo pacman -S alsa-utils

# Debian/Ubuntu
sudo apt install alsa-utils

# Fedora
sudo dnf install alsa-utils
```

### Stale PID file after crash

If MechClick crashed or was killed ungracefully, clean up the PID and lock files:

```bash
rm -f /tmp/mechclick.pid /tmp/mechclick.pid.children
rmdir /tmp/mechclick.lock 2>/dev/null
```

## Contributing

Contributions are welcome! Feel free to open issues and submit pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open source and available under the [MIT License](LICENSE).
