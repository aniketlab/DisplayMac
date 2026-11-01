#!/usr/bin/env bash
# ==============================================================================
# DisplayMac ⚡ Permanent Background Service & Headless Auto-Start Installer
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  DisplayMac ⚡ Background Service & Headless Auto-Start Setup"
echo "============================================================"
echo ""
echo "This installer will:"
echo " 1. Compile DisplayMacServer in optimized Release mode."
echo " 2. Install the binary to /usr/local/bin/DisplayMacServer."
echo " 3. Install ADB to /usr/local/bin/adb for instant zero-lag USB-C link."
echo " 4. Register a macOS LaunchAgent (com.displaymac.server.plist)."
echo " 5. Start the background service immediately with 24/7 KeepAlive."
echo ""
echo "After installation:"
echo " • DisplayMac will auto-start whenever you power on or restart your Mac."
echo " • You will NEVER need to open Terminal or run 'swift run' again."
echo " • Just plug the USB-C cable into your Galaxy Tab, and the display appears!"
echo ""

# 1. Compile Release Binary
echo "[1/5] Building DisplayMacServer in Release mode..."
cd "$DIR/macos-server"
swift build -c release

BINARY_SRC="$DIR/macos-server/.build/release/DisplayMacServer"
INSTALL_BIN="/usr/local/bin/DisplayMacServer"

# 2. Install binary to /usr/local/bin
echo "[2/5] Installing binary to $INSTALL_BIN..."
sudo mkdir -p /usr/local/bin
sudo cp "$BINARY_SRC" "$INSTALL_BIN"
sudo chmod +x "$INSTALL_BIN"
sudo codesign --force --sign - --identifier "com.displaymac.server" "$INSTALL_BIN" 2>/dev/null || true

# 3. Ensure ADB is in /usr/local/bin
echo "[3/5] Verifying ADB portable bridge..."
if [ -f "$DIR/macos-server/platform-tools/adb" ]; then
    sudo cp "$DIR/macos-server/platform-tools/adb" "/usr/local/bin/adb"
    sudo chmod +x "/usr/local/bin/adb"
elif [ ! -f "/usr/local/bin/adb" ]; then
    echo "• Downloading standalone Google ADB platform-tools..."
    cd /tmp
    curl -s -L -o platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
    unzip -q platform-tools.zip
    sudo cp platform-tools/adb /usr/local/bin/adb
    sudo chmod +x /usr/local/bin/adb
    rm -rf platform-tools platform-tools.zip
fi

# 4. Create LaunchAgent plist
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.displaymac.server.plist"

mkdir -p "$PLIST_DIR"

echo "[4/5] Configuring macOS LaunchAgent daemon..."
cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.displaymac.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/displaymac.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/displaymac.err.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

# 5. Load & Activate Service
echo "[5/5] Activating background daemon..."
# Stop any terminal-based running server first
pkill -f "DisplayMacServer" 2>/dev/null || true
sleep 0.5
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load -w "$PLIST_FILE"

echo ""
echo "============================================================"
echo "  🎉 DisplayMac Server is now PERMANENTLY INSTALLED!"
echo "============================================================"
echo "• The server is already running in the background right now."
echo "• It will AUTO-START every time you boot or restart your Mac mini."
echo "• Even after sleep, reboot, or cable unplug, it re-connects automatically."
echo "• You NEVER need to open Terminal again!"
echo ""
echo "Log file: tail -f /tmp/displaymac.log"
echo "To stop:  ./stop_server.sh"
echo "============================================================"
