#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Master Installer (macOS)
# Sets up the CoreAudio virtual driver, ADB USB bridge, DisplayMacServer
# binary, and background LaunchAgent service.
# Pass --usb-only to bind server listeners strictly to 127.0.0.1.
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_ONLY=false
if [[ "${1:-}" == "--usb-only" ]]; then
    USB_ONLY=true
fi

LOG_DIR="$HOME/Library/Logs/DisplayMac"
mkdir -p "$LOG_DIR"

echo "============================================================"
echo "  DisplayMac Host Installation"
echo "============================================================"
echo ""
echo "Steps:"
echo " 1. Compile and install CoreAudio virtual driver (DisplayMacAudio.driver)"
echo " 2. Verify or install standalone Google ADB (/usr/local/bin/adb)"
echo " 3. Build DisplayMacServer in Release mode"
echo " 4. Register background LaunchAgent (com.displaymac.server)"
echo " 5. Verify Accessibility & Screen Recording permissions"
echo ""

echo "[1/5] Setting up CoreAudio virtual driver..."
if [ -f "$DIR/macos-server/setup_dynamic_audio.sh" ]; then
    bash "$DIR/macos-server/setup_dynamic_audio.sh"
else
    echo "Audio setup script not found; skipping driver compilation."
fi

echo ""
echo "[2/5] Verifying ADB bridge..."
sudo mkdir -p /usr/local/bin
if [ -f "$DIR/macos-server/platform-tools/adb" ]; then
    sudo cp "$DIR/macos-server/platform-tools/adb" "/usr/local/bin/adb"
    sudo chmod +x "/usr/local/bin/adb"
    echo "Installed ADB from local platform-tools."
elif ! command -v adb &> /dev/null && [ ! -f "/usr/local/bin/adb" ]; then
    echo "Downloading Google Android platform-tools..."
    TMP_DIR="$(mktemp -d)"
    curl -fsSL -o "$TMP_DIR/platform-tools.zip" \
        https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
    unzip -q "$TMP_DIR/platform-tools.zip" -d "$TMP_DIR"
    sudo cp "$TMP_DIR/platform-tools/adb" /usr/local/bin/adb
    sudo chmod +x /usr/local/bin/adb
    rm -rf "$TMP_DIR"
    echo "Installed standalone ADB at /usr/local/bin/adb."
else
    echo "ADB is already available."
fi

echo ""
echo "[3/5] Building DisplayMacServer (Release)..."
cd "$DIR/macos-server"
swift build -c release

BINARY_SRC="$DIR/macos-server/.build/release/DisplayMacServer"
INSTALL_BIN="/usr/local/bin/DisplayMacServer"

echo "Installing binary to $INSTALL_BIN..."
sudo cp "$BINARY_SRC" "$INSTALL_BIN"
sudo chmod +x "$INSTALL_BIN"
sudo codesign --force --sign - --identifier "com.displaymac.server" "$INSTALL_BIN" 2>/dev/null || true

echo ""
echo "[4/5] Configuring LaunchAgent service (com.displaymac.server)..."
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.displaymac.server.plist"
mkdir -p "$PLIST_DIR"

PROGRAM_ARGS_XML="        <string>$INSTALL_BIN</string>"
if [ "$USB_ONLY" = true ]; then
    PROGRAM_ARGS_XML="$PROGRAM_ARGS_XML"$'\n'"        <string>--usb-only</string>"
fi

cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.displaymac.server</string>
    <key>ProgramArguments</key>
    <array>
$PROGRAM_ARGS_XML
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
    <string>$LOG_DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/server.err.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

pkill -9 -x "DisplayMacServer" 2>/dev/null || true
sleep 0.5

USER_ID="$(id -u)"
launchctl bootout "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true
sleep 0.5

if launchctl bootstrap "gui/$USER_ID" "$PLIST_FILE" 2>/dev/null; then
    echo "Registered LaunchAgent via bootstrap (gui/$USER_ID)."
else
    launchctl load -w "$PLIST_FILE" 2>/dev/null || true
    echo "Registered LaunchAgent via load."
fi

launchctl kickstart -k "gui/$USER_ID/com.displaymac.server" 2>/dev/null || true
sleep 1

PID="$(pgrep -x "DisplayMacServer" || true)"
if [ -n "$PID" ]; then
    echo "DisplayMacServer is running in the background (PID: $PID)."
else
    echo "DisplayMacServer scheduled with launchd."
fi

echo ""
echo "[5/5] Verifying permissions..."
"$INSTALL_BIN" --check-permissions 2>/dev/null || true

echo ""
echo "============================================================"
echo "  DisplayMac installation complete"
echo "============================================================"
echo "• Service is active in the background (LaunchAgent)."
if [ "$USB_ONLY" = true ]; then
    echo "• USB-only mode enabled (127.0.0.1 binding)."
fi
echo "• Logs: tail -f \"$LOG_DIR/server.log\""
echo "• Stop: ./stop_server.sh | Uninstall: ./uninstall.sh"
echo ""
if command -v fdesetup &>/dev/null; then
    FV_STATUS="$(fdesetup status 2>/dev/null || true)"
    if [[ "$FV_STATUS" =~ "On" ]]; then
        echo "Note (Headless Mac setup): FileVault is currently enabled."
        echo "Headless autostart before login requires FileVault Off and Automatic Login."
    fi
fi
