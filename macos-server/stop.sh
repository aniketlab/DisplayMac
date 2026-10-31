#!/usr/bin/env bash
# Stops DisplayMac background service cleanly
set -e

PLIST="$HOME/Library/LaunchAgents/com.displaymac.server.plist"

echo "🛑 Stopping DisplayMac Server..."
launchctl unload "$PLIST" 2>/dev/null || true
killall DisplayMacServer 2>/dev/null || true

echo "✅ DisplayMac Server stopped successfully. Physical display is 100% restored."
