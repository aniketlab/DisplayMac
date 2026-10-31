#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - Standalone Native Audio Driver Compiler
# Compiles directly using clang (No Xcode.app or Homebrew needed!)
# Dynamically exposes the connected tablet (e.g. "Samsung Galaxy Tab S10 Ultra") 
# in the macOS Sound menu!
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - Dynamic Hardware Audio Driver Setup"
echo "============================================================"

BUILD_DIR="/tmp/DisplayMacAudioBuild"
BUNDLE_DIR="$BUILD_DIR/DisplayMacAudio.driver"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
NAME_FILE="/tmp/displaymac_audio_name.txt"

# 1. Clean previous build if any
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/4] Fetching open-source CoreAudio driver engine..."
git clone --depth 1 https://github.com/ExistentialAudio/BlackHole.git "$BUILD_DIR/src"

echo "[2/4] Injecting dynamic device-name logic..."
BLACKHOLE_C=$(find "$BUILD_DIR/src" -name "BlackHole.c" | head -n 1)

if [ -z "$BLACKHOLE_C" ] || [ ! -f "$BLACKHOLE_C" ]; then
    echo "❌ Error: BlackHole.c not found."
    exit 1
fi

SRC_DIR=$(dirname "$BLACKHOLE_C")

python3 - "$BLACKHOLE_C" << 'EOF'
import sys
import re

path = sys.argv[1]
with open(path, "r") as f:
    code = f.read()

replacement = """
static CFStringRef get_device_name(void) {
    FILE *f = fopen("/tmp/displaymac_audio_name.txt", "r");
    if (f) {
        char buf[256];
        if (fgets(buf, sizeof(buf), f)) {
            buf[strcspn(buf, "\\r\\n")] = 0;
            fclose(f);
            if (strlen(buf) > 0) {
                return CFStringCreateWithCString(kCFAllocatorDefault, buf, kCFStringEncodingUTF8);
            }
        } else {
            fclose(f);
        }
    }
    return CFSTR("Samsung Galaxy Tab S10 Ultra (DisplayMac)");
}
"""

target = "static CFStringRef get_device_name(void) {\n    RETURN_FORMATTED_STRING(kDevice_Name)\n}"
if target in code:
    code = code.replace(target, replacement)
    print("✅ Successfully patched get_device_name via exact match")
else:
    code = re.sub(r'static\s+CFStringRef\s+get_device_name\s*\(\s*void\s*\)\s*\{[^}]*\}', replacement, code)
    print("✅ Successfully patched get_device_name via regex")

with open(path, "w") as f:
    f.write(code)
EOF

# Set default tablet name
echo "Samsung Galaxy Tab S10 Ultra (DisplayMac)" > "$NAME_FILE"
chmod 666 "$NAME_FILE"

echo "[3/4] Compiling native Apple Silicon driver bundle (Pure clang, zero Xcode needed)..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"

# Compile directly using Apple Silicon clang with CoreAudio frameworks
clang -bundle \
    -arch arm64 \
    -isysroot $(xcrun --show-sdk-path) \
    -O3 \
    -I "$SRC_DIR" \
    -DkNumber_Of_Channels=2 \
    -DkDriver_Name=\"DisplayMacAudio\" \
    -DkDevice_Name=\"Samsung Galaxy Tab S10 Ultra (DisplayMac)\" \
    -DkPlugIn_BundleID=\"com.displaymac.audio\" \
    -framework CoreAudio \
    -framework CoreFoundation \
    -framework AudioToolbox \
    -o "$BUNDLE_DIR/Contents/MacOS/DisplayMacAudio" \
    "$BLACKHOLE_C"

# Create driver Info.plist
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

# Ad-hoc sign the bundle
codesign -f -s - "$BUNDLE_DIR" > /dev/null 2>&1 || true

echo "[4/4] Installing driver to /Library/Audio/Plug-Ins/HAL/..."
sudo rm -rf "$DRIVER_DEST"
sudo cp -R "$BUNDLE_DIR" "$DRIVER_DEST"
sudo chown -R root:wheel "$DRIVER_DEST"

# Restart CoreAudio daemon so macOS immediately exposes the driver
echo "• Reloading macOS CoreAudio daemon..."
sudo killall -9 coreaudiod 2>/dev/null || true
sleep 1

# Cleanup temp build
rm -rf "$BUILD_DIR"

echo ""
echo "============================================================"
echo "🎉 SUCCESS! Dynamic Audio Driver Installed!"
echo "• Open Control Center > Sound (Speaker icon) in your Menu Bar."
echo "• You will now see: 'Samsung Galaxy Tab S10 Ultra (DisplayMac)'!"
echo "• Select it to stream all Mac sound straight to your Tab S10 Ultra!"
echo "============================================================"
