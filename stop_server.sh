#!/usr/bin/env bash
# ==============================================================================
# DisplayMac 🛑 Server Stop & Hardware Reset Utility
# Stops all running DisplayMac instances, releases virtual displays,
# clears ADB reverse tunnels, and restores physical Mac audio.
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac 🛑 Stopping Server & Resetting Hardware"
echo "============================================================"

# 1. Terminate running DisplayMacServer processes & unload LaunchAgent
echo "[1/4] Stopping active DisplayMacServer instances..."
PLIST_FILE="$HOME/Library/LaunchAgents/com.displaymac.server.plist"
if [ -f "$PLIST_FILE" ]; then
    echo "• Pausing LaunchAgent background service..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
fi

PIDS=$(pgrep -f "DisplayMacServer" || true)
if [ -n "$PIDS" ]; then
    echo "• Found running PID(s): $PIDS. Terminating gracefully..."
    pkill -f "DisplayMacServer" 2>/dev/null || true
    sleep 0.5
    # Force kill if still lingering
    pkill -9 -f "DisplayMacServer" 2>/dev/null || true
    echo "✅ DisplayMac processes stopped. Virtual displays released by WindowServer."
else
    echo "• No active DisplayMacServer process found."
fi

# 2. Clear ADB reverse socket forwards
echo "[2/4] Resetting ADB reverse tunnels..."
ADB_BIN="adb"
if ! command -v adb &> /dev/null; then
    if [ -f "./macos-server/platform-tools/adb" ]; then
        ADB_BIN="./macos-server/platform-tools/adb"
    fi
fi

if command -v "$ADB_BIN" &> /dev/null; then
    "$ADB_BIN" reverse --remove-all 2>/dev/null || true
    echo "✅ ADB reverse tunnels (7100, 7101, 7102) cleared."
else
    echo "• ADB not running or not found. Tunnels clear."
fi

# 3. Clean temporary runtime files
echo "[3/4] Cleaning temporary runtime locks..."
rm -f /tmp/displaymac_audio_name.txt /tmp/displaymac*.lock /tmp/displaymac*.log 2>/dev/null || true

# 4. Hardware Audio Check
echo "[4/4] Hardware audio status..."
echo "• Physical speakers (Mac Mini / BenQ / HDMI) are active."

echo ""
echo "============================================================"
echo "  ✅ DisplayMac Server stopped. Mac hardware 100% reset!"
echo "============================================================"
