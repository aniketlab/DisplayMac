#!/usr/bin/env bash
# ==============================================================================
# DisplayMac 🗑️ Complete Uninstaller
# Completely removes DisplayMac, audio drivers, background services,
# and restores macOS to a clean, factory-stock state.
# ==============================================================================

set -e

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
echo ""
read -p "Are you sure you want to completely uninstall DisplayMac? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "[1/6] Stopping active DisplayMac processes..."
pkill -f "DisplayMacServer" 2>/dev/null || true
sleep 0.5
pkill -9 -f "DisplayMacServer" 2>/dev/null || true

echo "[2/6] Removing LaunchAgent autostart configurations..."
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

echo "[3/6] Removing installed command-line binaries..."
if [ -f "/usr/local/bin/DisplayMacServer" ]; then
    sudo rm -f "/usr/local/bin/DisplayMacServer"
    echo "• Removed /usr/local/bin/DisplayMacServer"
fi

echo "[4/6] Removing DisplayMac CoreAudio HAL driver..."
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

echo "[5/6] Resetting ADB reverse tunnels..."
ADB_BIN="adb"
if ! command -v adb &> /dev/null; then
    if [ -f "./macos-server/platform-tools/adb" ]; then
        ADB_BIN="./macos-server/platform-tools/adb"
    fi
fi
if command -v "$ADB_BIN" &> /dev/null; then
    "$ADB_BIN" reverse --remove-all 2>/dev/null || true
fi

echo "[6/6] Cleaning temporary files & caches..."
rm -f /tmp/displaymac* /tmp/DisplayMac* 2>/dev/null || true

echo ""
echo "============================================================"
echo "  🎉 DisplayMac has been 100% completely uninstalled!"
echo "  Your Mac is in clean, factory-stock condition."
echo "============================================================"
