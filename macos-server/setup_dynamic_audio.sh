#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - Native Dynamic Audio Driver Setup
# Compiles directly using clang (Zero Xcode.app, Homebrew, or external clones needed!)
# Dynamically exposes the connected tablet (e.g. "Samsung Galaxy Tab S10 Ultra") 
# in the macOS Sound menu!
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - Dynamic Hardware Audio Driver Setup"
echo "============================================================"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_SRC="$DIR/Driver/DisplayMacAudio.c"
BUNDLE_DIR="/tmp/DisplayMacAudio.driver"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
NAME_FILE="/tmp/displaymac_audio_name.txt"

if [ ! -f "$DRIVER_SRC" ]; then
    echo "❌ Error: $DRIVER_SRC not found."
    exit 1
fi

# 1. Set initial dynamic audio device name (Neutral default)
echo "DisplayMac Audio" > "$NAME_FILE"
chmod 666 "$NAME_FILE"

# 2. Compile driver bundle directly using clang
echo "[1/3] Compiling native Apple Silicon driver bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"

SDK_PATH=$(xcrun --show-sdk-path)

clang -bundle \
    -arch arm64 \
    -isysroot "$SDK_PATH" \
    -O3 \
    -DkNumber_Of_Channels=2 \
    -DkDriver_Name=\"DisplayMacAudio\" \
    -DkDevice_Name=\"DisplayMacAudio\" \
    -DkPlugIn_BundleID=\"com.displaymac.audio\" \
    -framework CoreAudio \
    -framework CoreFoundation \
    -framework AudioToolbox \
    -framework Accelerate \
    -o "$BUNDLE_DIR/Contents/MacOS/DisplayMacAudio" \
    "$DRIVER_SRC"

# 3. Create driver Info.plist
cat << 'EOF' > "$BUNDLE_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DisplayMacAudio</string>
    <key>CFBundleIdentifier</key>
    <string>com.displaymac.audio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DisplayMacAudio</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFPlugInDynamicRegistration</key>
    <string>NO</string>
    <key>CFPlugInFactories</key>
    <dict>
        <key>D1350F65-A1F3-4FA4-887F-70190B9FB3D7</key>
        <string>BlackHole_Create</string>
    </dict>
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array>
            <string>D1350F65-A1F3-4FA4-887F-70190B9FB3D7</string>
        </array>
    </dict>
</dict>
</plist>
EOF

# 4. Install driver to /Library/Audio/Plug-Ins/HAL/
echo "[2/3] Installing driver to /Library/Audio/Plug-Ins/HAL/..."
sudo rm -rf "$DRIVER_DEST"
sudo cp -R "$BUNDLE_DIR" "$DRIVER_DEST"
sudo chown -R root:wheel "$DRIVER_DEST"
rm -rf "$BUNDLE_DIR"

# 5. Reload CoreAudio daemon
echo "[3/3] Reloading macOS CoreAudio daemon..."
sudo killall -9 coreaudiod 2>/dev/null || true
sleep 1

echo ""
echo "============================================================"
echo "🎉 SUCCESS! DisplayMac Audio Driver Ready!"
echo "• Open Control Center > Sound (Speaker icon) in your Menu Bar."
echo "• You will see: 'DisplayMac Audio' (idle/neutral state)."
echo "• When your tablet connects: it dynamically switches to your tablet name!"
echo "• Your Mac's built-in speakers & BenQ audio remain 100% original."
echo "============================================================"
