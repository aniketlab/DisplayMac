#!/usr/bin/env bash
# Stops DisplayMac background service
set -euo pipefail

USER_ID="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/com.displaymac.server.plist"

echo "Stopping DisplayMacServer..."
launchctl bootout "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
pkill -x "DisplayMacServer" 2>/dev/null || true

echo "DisplayMacServer stopped."
