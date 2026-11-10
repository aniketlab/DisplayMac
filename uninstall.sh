#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Uninstaller (macOS)
# Stops DisplayMacServer, removes LaunchAgent, removes DisplayMacAudio.driver,
# cleans DisplayMac logs/forwards, and resets ONLY DisplayMac TCC entries.
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  DisplayMac Uninstaller"
echo "============================================================"
echo ""
echo "This will remove:"
echo " 1. Running DisplayMacServer processes and LaunchAgent plist"
echo " 2. /usr/local/bin/DisplayMacServer binary"
echo " 3. /Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
echo " 4. DisplayMac ADB port forwards (7100, 7101, 7102) and logs"
echo " 5. DisplayMac TCC privacy permissions (com.displaymac.server)"
echo ""

FORCE=false
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" || "${1:-}" == "--force" ]]; then
    FORCE=true
fi

if [ "$FORCE" = false ]; then
    read -p "Uninstall DisplayMac? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

echo ""
echo "[1/5] Stopping DisplayMacServer..."
USER_ID="$(id -u)"
launchctl bootout "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true
PLIST_USER="$HOME/Library/LaunchAgents/com.displaymac.server.plist"
if [ -f "$PLIST_USER" ]; then
    launchctl unload "$PLIST_USER" 2>/dev/null || true
    rm -f "$PLIST_USER"
    echo "Removed $PLIST_USER"
fi

pkill -x "DisplayMacServer" 2>/dev/null || true
sleep 0.5
pkill -9 -x "DisplayMacServer" 2>/dev/null || true

echo "[2/5] Removing installed binary..."
if [ -f "/usr/local/bin/DisplayMacServer" ]; then
    sudo rm -f "/usr/local/bin/DisplayMacServer"
    echo "Removed /usr/local/bin/DisplayMacServer"
fi

echo "[3/5] Removing DisplayMacAudio.driver..."
AUDIO_DRIVER="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
if [ -d "$AUDIO_DRIVER" ]; then
    sudo rm -rf "$AUDIO_DRIVER"
    echo "Removed $AUDIO_DRIVER; restarting coreaudiod..."
    sudo killall -9 coreaudiod 2>/dev/null || true
    sleep 1
else
    echo "CoreAudio driver not found; skipping."
fi

echo "[4/5] Cleaning DisplayMac ADB tunnels and logs..."
ADB_BIN="adb"
if ! command -v adb &> /dev/null && [ -f "$DIR/macos-server/platform-tools/adb" ]; then
    ADB_BIN="$DIR/macos-server/platform-tools/adb"
fi
if command -v "$ADB_BIN" &> /dev/null; then
    for port in tcp:7100 tcp:7101 tcp:7102; do
        "$ADB_BIN" reverse --remove "$port" 2>/dev/null || true
    done
fi
rm -rf "$HOME/Library/Logs/DisplayMac" 2>/dev/null || true
rm -f /tmp/displaymac_audio_name.txt /tmp/displaymac*.log 2>/dev/null || true

echo "[5/5] Resetting DisplayMac TCC privacy permissions..."
tccutil reset Accessibility com.displaymac.server 2>/dev/null || true
tccutil reset ScreenCapture com.displaymac.server 2>/dev/null || true
tccutil reset ListenEvent com.displaymac.server 2>/dev/null || true

echo ""
echo "DisplayMac uninstalled cleanly."
