#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Server - Uninstaller Forwarder
# ==============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/../uninstall.sh" ]; then
    exec "$DIR/../uninstall.sh"
else
    # Fallback direct execution
    pkill -9 -f "DisplayMacServer" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.displaymac.server.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.displaymac.server.plist"
    sudo rm -f "/usr/local/bin/DisplayMacServer"
    sudo rm -rf "/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
    sudo killall -9 coreaudiod 2>/dev/null || true
    echo "✅ DisplayMac Server uninstalled successfully."
fi
