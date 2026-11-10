#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - Virtual Audio HAL Driver Setup
# Compiles DisplayMacAudio.c (GPL-3.0, derived from BlackHole) directly via clang
# as a Universal macOS binary (arm64 + x86_64).
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo "  DisplayMac - Virtual Audio Driver Setup"
echo "============================================================"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_SRC="$DIR/Driver/DisplayMacAudio.c"
BUNDLE_DIR="$(mktemp -d)/DisplayMacAudio.driver"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"

if [ ! -f "$DRIVER_SRC" ]; then
    echo "Error: $DRIVER_SRC not found."
    exit 1
fi

trap 'rm -rf "$(dirname "$BUNDLE_DIR")"' EXIT

echo "[1/3] Compiling DisplayMacAudio HAL driver bundle..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH_FLAGS=(-arch arm64 -arch x86_64)

if ! clang -bundle \
    "${ARCH_FLAGS[@]}" \
    -isysroot "$SDK_PATH" \
    -O3 \
    -DkNumber_Of_Channels=2 \
    -DkDriver_Name=\"DisplayMacAudio\" \
    -DkDevice_Name=\"DisplayMacAudio\" \
    -DkManufacturer_Name=\"DisplayMac\" \
    -DkPlugIn_BundleID=\"com.displaymac.audio\" \
    -framework CoreAudio \
    -framework CoreFoundation \
    -framework AudioToolbox \
    -framework Accelerate \
    -o "$BUNDLE_DIR/Contents/MacOS/DisplayMacAudio" \
    "$DRIVER_SRC" 2>/dev/null; then
    HOST_ARCH="$(uname -m)"
    echo "Universal build unavailable; building for host architecture ($HOST_ARCH)..."
    clang -bundle \
        -arch "$HOST_ARCH" \
        -isysroot "$SDK_PATH" \
        -O3 \
        -DkNumber_Of_Channels=2 \
        -DkDriver_Name=\"DisplayMacAudio\" \
        -DkDevice_Name=\"DisplayMacAudio\" \
        -DkManufacturer_Name=\"DisplayMac\" \
        -DkPlugIn_BundleID=\"com.displaymac.audio\" \
        -framework CoreAudio \
        -framework CoreFoundation \
        -framework AudioToolbox \
        -framework Accelerate \
        -o "$BUNDLE_DIR/Contents/MacOS/DisplayMacAudio" \
        "$DRIVER_SRC"
fi

cat <<'EOF' > "$BUNDLE_DIR/Contents/Info.plist"
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

echo "[2/3] Installing driver to $DRIVER_DEST..."
sudo rm -rf "$DRIVER_DEST"
sudo cp -R "$BUNDLE_DIR" "$DRIVER_DEST"
sudo chown -R root:wheel "$DRIVER_DEST"

echo "[3/3] Reloading CoreAudio daemon..."
sudo killall -9 coreaudiod 2>/dev/null || true
sleep 1

echo "Done: 'DisplayMac Audio' is now available in System Settings > Sound."
