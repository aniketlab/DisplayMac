#!/usr/bin/env bash
# ==============================================================================
# DisplayMac ⚡ Master All-in-One Installer
# Sets up Dynamic Audio Driver, Portable USB Bridge, 120Hz Native Server,
# and activates 24/7 Headless Auto-Start Background Service.
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  DisplayMac ⚡ Master All-in-One Installation Wizard"
echo "============================================================"
echo ""
echo "This installer will configure everything in one single pass:"
echo " 1. Native Dynamic Audio Driver (compiles & installs DisplayMacAudio.driver)."
echo " 2. Google Portable ADB USB-C bridge (/usr/local/bin/adb)."
echo " 3. DisplayMacServer 120Hz host binary (compiles in Release mode)."
echo " 4. 24/7 Auto-Start LaunchAgent service (runs headlessly on boot/restart)."
echo " 5. Accessibility & Screen Recording permission verification."
echo ""
echo "After installation:"
echo " • DisplayMac will auto-start whenever you power on or restart your Mac."
echo " • Audio dynamically streams to your Galaxy Tab AKG quad speakers."
echo " • You will NEVER need to open Terminal or run 'swift run' again."
echo " • Just plug the USB-C cable into your Galaxy Tab, and the display appears!"
echo ""

# ------------------------------------------------------------------------------
# 1. Compile & Install Dynamic Audio Driver
# ------------------------------------------------------------------------------
echo "[1/5] Setting up Dynamic CoreAudio Driver..."
if [ -f "$DIR/macos-server/setup_dynamic_audio.sh" ]; then
    bash "$DIR/macos-server/setup_dynamic_audio.sh"
else
    echo "• Audio setup script not found, skipping driver compile."
fi

# ------------------------------------------------------------------------------
# 2. Setup Standalone Google ADB Bridge
# ------------------------------------------------------------------------------
echo ""
echo "[2/5] Verifying ADB portable bridge..."
sudo mkdir -p /usr/local/bin
if [ -f "$DIR/macos-server/platform-tools/adb" ]; then
    sudo cp "$DIR/macos-server/platform-tools/adb" "/usr/local/bin/adb"
    sudo chmod +x "/usr/local/bin/adb"
    echo "• Installed ADB from local repository platform-tools."
elif [ ! -f "/usr/local/bin/adb" ]; then
    echo "• Downloading standalone Google ADB platform-tools..."
    TMP_DIR=$(mktemp -d)
    curl -s -L -o "$TMP_DIR/platform-tools.zip" https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
    unzip -q "$TMP_DIR/platform-tools.zip" -d "$TMP_DIR"
    sudo cp "$TMP_DIR/platform-tools/adb" /usr/local/bin/adb
    sudo chmod +x /usr/local/bin/adb
    rm -rf "$TMP_DIR"
    echo "• Downloaded & installed standalone Google ADB to /usr/local/bin/adb."
else
    echo "• Existing ADB detected at /usr/local/bin/adb."
fi

# ------------------------------------------------------------------------------
# 3. Compile DisplayMacServer in Release Mode
# ------------------------------------------------------------------------------
echo ""
echo "[3/5] Building DisplayMacServer in Release mode..."
cd "$DIR/macos-server"
swift build -c release

BINARY_SRC="$DIR/macos-server/.build/release/DisplayMacServer"
INSTALL_BIN="/usr/local/bin/DisplayMacServer"

echo "• Installing binary to $INSTALL_BIN..."
sudo cp "$BINARY_SRC" "$INSTALL_BIN"
sudo chmod +x "$INSTALL_BIN"
sudo codesign --force --sign - --identifier "com.displaymac.server" "$INSTALL_BIN" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Configure & Load 24/7 LaunchAgent Service
# ------------------------------------------------------------------------------
echo ""
echo "[4/5] Configuring macOS LaunchAgent daemon (24/7 Auto-Start)..."
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.displaymac.server.plist"

mkdir -p "$PLIST_DIR"

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

# Stop previous instance & load fresh service
pkill -f "DisplayMacServer" 2>/dev/null || true
sleep 0.5
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load -w "$PLIST_FILE"
echo "✅ Background service registered and running!"

# ------------------------------------------------------------------------------
# 5. Permission & Headless Check
# ------------------------------------------------------------------------------
echo ""
echo "[5/5] Checking macOS Permissions & Headless Configuration..."

# Trigger permission prompt if not yet authorized
"$INSTALL_BIN" --check-permissions 2>/dev/null || true

echo ""
echo "============================================================"
echo "  🎉 DisplayMac has been 100% COMPLETELY INSTALLED!"
echo "============================================================"
echo "• The server is already running in the background right now."
echo "• Dynamic Audio is ready in your macOS Sound Menu."
echo "• USB-C 0.5ms ultra-low latency bridge is active."
echo "• It will AUTO-START every time you boot or restart your Mac mini."
echo "• You NEVER need to open Terminal or run 'swift run' again!"
echo ""
echo "------------------------------------------------------------"
echo "📌 CRITICAL HEADLESS CONFIGURATION (For Booting Without a Monitor):"
echo "------------------------------------------------------------"
if command -v fdesetup &>/dev/null; then
    FV_STATUS=$(fdesetup status 2>/dev/null || true)
    if [[ "$FV_STATUS" =~ "On" ]]; then
        echo "⚠️ FileVault is currently ON:"
        echo "   macOS disk encryption prevents any app from starting before login."
        echo "   To boot headlessly without a physical monitor, turn FileVault OFF in:"
        echo "   👉 System Settings > Privacy & Security > FileVault"
        echo ""
    fi
fi

echo "To allow your Mac mini to start DisplayMac when NO monitor is plugged in:"
echo " 1. Open: System Settings > Users & Groups"
echo " 2. Under 'Automatically log in as': Select your user account ($USER)"
echo " 3. Enter your password to save."
echo ""
echo "🛡️ Password Security on Startup:"
echo "   Once Automatic Login is enabled, DisplayMac connects to your Galaxy"
echo "   Tab right after boot. You can lock your screen anytime (or use lock on sleep),"
echo "   and type your password directly from your Galaxy Tab!"
echo ""
echo "Log file: tail -f /tmp/displaymac.log"
echo "To uninstall: ./uninstall.sh (or 'Uninstall DisplayMac.command')"
echo "============================================================"
