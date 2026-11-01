#!/usr/bin/env bash
# ==============================================================================
# DisplayMac 🗑️ Complete Uninstaller
# Completely removes DisplayMac, audio drivers, background services,
# privacy permissions, and restores macOS to a clean, factory-stock state.
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  DisplayMac 🗑️ Complete Uninstallation Wizard"
echo "============================================================"
echo ""
echo "This script will completely remove DisplayMac from your Mac:"
echo " 1. Stop all active DisplayMac server processes."
echo " 2. Remove background LaunchAgent / daemon autostart plists."
echo " 3. Remove installed binaries from /usr/local/bin."
echo " 4. Remove the CoreAudio driver (/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver)."
echo " 5. Restart macOS coreaudiod to restore 100% stock audio."
echo " 6. Clear ADB socket port forwards and temporary files."
echo " 7. Reset macOS Privacy & Security permissions (Accessibility & Screen Recording)."
echo ""

FORCE=false
if [[ "$1" == "-y" || "$1" == "--yes" || "$1" == "--force" ]]; then
    FORCE=true
fi

if [ "$FORCE" = false ]; then
    read -p "Are you sure you want to completely uninstall DisplayMac? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

echo ""
echo "[1/7] Stopping active DisplayMac processes..."
pkill -f "DisplayMacServer" 2>/dev/null || true
sleep 0.5
pkill -9 -f "DisplayMacServer" 2>/dev/null || true

echo "[2/7] Removing LaunchAgent autostart configurations..."
PLIST_USER="$HOME/Library/LaunchAgents/com.displaymac.server.plist"
if [ -f "$PLIST_USER" ]; then
    launchctl unload "$PLIST_USER" 2>/dev/null || true
    rm -f "$PLIST_USER"
    echo "• Removed $PLIST_USER"
fi

PLIST_BRIDGE="$HOME/Library/LaunchAgents/com.displaymac.autobridge.plist"
if [ -f "$PLIST_BRIDGE" ]; then
    launchctl unload "$PLIST_BRIDGE" 2>/dev/null || true
    rm -f "$PLIST_BRIDGE"
    echo "• Removed $PLIST_BRIDGE"
fi

echo "[3/7] Removing installed command-line binaries..."
if [ -f "/usr/local/bin/DisplayMacServer" ]; then
    sudo rm -f "/usr/local/bin/DisplayMacServer"
    echo "• Removed /usr/local/bin/DisplayMacServer"
fi

echo "[4/7] Removing DisplayMac CoreAudio HAL driver..."
AUDIO_DRIVER="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
if [ -d "$AUDIO_DRIVER" ]; then
    sudo rm -rf "$AUDIO_DRIVER"
    echo "• Removed $AUDIO_DRIVER"
    echo "• Reloading macOS coreaudiod to flush virtual audio..."
    sudo killall -9 coreaudiod 2>/dev/null || true
    sleep 1
    echo "✅ Stock macOS audio restored."
else
    echo "• CoreAudio driver was not installed or already removed."
fi

echo "[5/7] Resetting ADB reverse tunnels..."
ADB_BIN="adb"
if ! command -v adb &> /dev/null; then
    if [ -f "$DIR/macos-server/platform-tools/adb" ]; then
        ADB_BIN="$DIR/macos-server/platform-tools/adb"
    fi
fi
if command -v "$ADB_BIN" &> /dev/null; then
    "$ADB_BIN" reverse --remove-all 2>/dev/null || true
fi

echo "[6/7] Cleaning temporary files & caches..."
rm -f /tmp/displaymac* /tmp/DisplayMac* 2>/dev/null || true

echo "[7/7] Resetting macOS Privacy & Security permissions..."
if [ -f "$DIR/reset_permissions.sh" ]; then
    bash "$DIR/reset_permissions.sh"
else
    echo "• Resetting Accessibility permissions..."
    tccutil reset Accessibility com.apple.Terminal 2>/dev/null || true
    tccutil reset Accessibility com.googlecode.iterm2 2>/dev/null || true
    tccutil reset Accessibility com.microsoft.VSCode 2>/dev/null || true
    tccutil reset Accessibility com.displaymac.server 2>/dev/null || true
    sudo tccutil reset Accessibility com.apple.Terminal 2>/dev/null || true
    sudo tccutil reset Accessibility com.googlecode.iterm2 2>/dev/null || true

    echo "• Resetting Screen Recording permissions..."
    tccutil reset ScreenCapture com.apple.Terminal 2>/dev/null || true
    tccutil reset ScreenCapture com.googlecode.iterm2 2>/dev/null || true
    tccutil reset ScreenCapture com.microsoft.VSCode 2>/dev/null || true
    tccutil reset ScreenCapture com.displaymac.server 2>/dev/null || true
    sudo tccutil reset ScreenCapture com.apple.Terminal 2>/dev/null || true
    sudo tccutil reset ScreenCapture com.googlecode.iterm2 2>/dev/null || true

    echo "• Resetting Input Monitoring permissions..."
    tccutil reset ListenEvent com.apple.Terminal 2>/dev/null || true
    tccutil reset ListenEvent com.googlecode.iterm2 2>/dev/null || true
    sudo tccutil reset ListenEvent com.apple.Terminal 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo "  🎉 DisplayMac has been 100% completely uninstalled!"
echo "  Your Mac is in clean, factory-stock condition."
echo "============================================================"
