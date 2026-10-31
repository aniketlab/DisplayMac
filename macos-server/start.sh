#!/usr/bin/env bash
# Starts DisplayMac background service
set -e

PLIST="$HOME/Library/LaunchAgents/com.displaymac.server.plist"

echo "⚡ Starting DisplayMac Server..."
launchctl load -w "$PLIST" 2>/dev/null || true

echo "✅ DisplayMac Server started in background. Logs: tail -f /tmp/displaymac.log"
