#!/usr/bin/env bash
# Starts DisplayMac background service
set -euo pipefail

USER_ID="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/com.displaymac.server.plist"
LOG_FILE="$HOME/Library/Logs/DisplayMac/server.log"

echo "Starting DisplayMacServer..."
launchctl bootstrap "gui/$USER_ID" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true

echo "DisplayMacServer started. Logs: tail -f \"$LOG_FILE\""
