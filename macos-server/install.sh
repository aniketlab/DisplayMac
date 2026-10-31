#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Server - Headless macOS Auto-Start Installer
# Installs DisplayMac as a permanent background service on Apple Silicon
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - Installing Headless Background Service"
echo "============================================================"

# 1. Compile Release Binary
echo "[1/4] Compiling DisplayMacServer in Release mode..."
swift build -c release

BINARY_PATH=".build/release/DisplayMacServer"
INSTALL_PATH="/usr/local/bin/DisplayMacServer"

# 2. Copy binary to /usr/local/bin
echo "[2/4] Installing binary to $INSTALL_PATH..."
sudo mkdir -p /usr/local/bin
sudo cp "$BINARY_PATH" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"
sudo codesign --force --sign - --identifier "com.displaymac.server" "$INSTALL_PATH"

# 3. Create LaunchAgent plist
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.displaymac.server.plist"

mkdir -p "$PLIST_DIR"

echo "[3/4] Creating LaunchAgent service configuration..."
cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.displaymac.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_PATH</string>
    </array>
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

# 4. Load & Activate Service
echo "[4/4] Activating background daemon..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load -w "$PLIST_FILE"

echo ""
echo "============================================================"
echo "✅ DisplayMac Server is now PERMANENTLY INSTALLED!"
echo "• The server is already running in background."
echo "• It will AUTO-START every time you turn on your Mac mini."
echo "• You will NEVER need to run 'swift run' or open Terminal."
echo "• Logs: tail -f /tmp/displaymac.log"
echo "============================================================"
