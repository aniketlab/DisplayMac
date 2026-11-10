#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Server Stop & Reset Utility
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo "  Stopping DisplayMacServer"
echo "============================================================"

USER_ID="$(id -u)"
PLIST_FILE="$HOME/Library/LaunchAgents/com.displaymac.server.plist"

launchctl bootout "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true
if [ -f "$PLIST_FILE" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
fi

PIDS="$(pgrep -x "DisplayMacServer" || true)"
if [ -n "$PIDS" ]; then
    echo "Stopping DisplayMacServer (PID: $PIDS)..."
    pkill -x "DisplayMacServer" 2>/dev/null || true
    sleep 0.5
    pkill -9 -x "DisplayMacServer" 2>/dev/null || true
    echo "Server stopped; virtual display released."
else
    echo "No active DisplayMacServer process found."
fi

ADB_BIN="adb"
if ! command -v adb &> /dev/null && [ -f "./macos-server/platform-tools/adb" ]; then
    ADB_BIN="./macos-server/platform-tools/adb"
fi
if command -v "$ADB_BIN" &> /dev/null; then
    for port in tcp:7100 tcp:7101 tcp:7102; do
        "$ADB_BIN" reverse --remove "$port" 2>/dev/null || true
    done
    echo "Cleared DisplayMac ADB reverse tunnels (7100, 7101, 7102)."
fi

echo "Done."
