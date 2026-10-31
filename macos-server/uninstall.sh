#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Server - Uninstaller
# Stops and removes the background service from macOS
# ==============================================================================

set -e

PLIST_FILE="$HOME/Library/LaunchAgents/com.displaymac.server.plist"
INSTALL_PATH="/usr/local/bin/DisplayMacServer"

echo "Stopping DisplayMac background service..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true

echo "Removing service configuration and binary..."
rm -f "$PLIST_FILE"
sudo rm -f "$INSTALL_PATH"

echo "✅ DisplayMac Server uninstalled successfully."
