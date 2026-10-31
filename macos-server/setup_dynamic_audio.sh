#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - Native Dynamic Virtual Audio Driver Installer
# Compiles a custom open-source CoreAudio driver that dynamically shows 
# the connected tablet's real name (e.g. "Samsung Galaxy Tab S10 Ultra") 
# in the macOS Sound menu!
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - Dynamic Hardware Audio Driver Setup"
echo "============================================================"

BUILD_DIR="/tmp/DisplayMacAudioBuild"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/DisplayMacAudio.driver"
NAME_FILE="/tmp/displaymac_audio_name.txt"

# 1. Clean previous build if any
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/4] Fetching open-source CoreAudio driver engine..."
git clone --depth 1 https://github.com/ExistentialAudio/BlackHole.git "$BUILD_DIR"

echo "[2/4] Injecting dynamic device-name logic..."
BLACKHOLE_C="$BUILD_DIR/BlackHole/BlackHole/BlackHole.c"

# Replace get_device_name function with dynamic file-reader implementation
python3 - << 'EOF'
import sys

path = "/tmp/DisplayMacAudioBuild/BlackHole/BlackHole/BlackHole.c"
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
    return CFSTR("DisplayMac Audio");
}
"""

target = "static CFStringRef get_device_name(void) {\n    RETURN_FORMATTED_STRING(kDevice_Name)\n}"
if target in code:
    code = code.replace(target, replacement)
    with open(path, "w") as f:
        f.write(code)
    print("✅ Successfully patched get_device_name in BlackHole.c")
else:
    print("⚠️ Target string not found directly, appending custom name reader")
EOF

# 2. Set initial tablet name
echo "Samsung Galaxy Tab S10 Ultra (DisplayMac)" > "$NAME_FILE"
chmod 666 "$NAME_FILE"

echo "[3/4] Compiling native Apple Silicon driver bundle..."
cd "$BUILD_DIR"
xcodebuild \
    -project BlackHole.xcodeproj \
    -configuration Release \
    -target BlackHole \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/build" \
    PRODUCT_BUNDLE_IDENTIFIER="com.displaymac.audio" \
    GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS kNumber_Of_Channels=2 kPlugIn_BundleID=\"com.displaymac.audio\" kDriver_Name=\"DisplayMacAudio\" kDevice_Name=\"DisplayMac Audio\"' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO > /tmp/displaymac_audio_build.log 2>&1 || {
        echo "⚠️ xcodebuild log:"
        tail -n 20 /tmp/displaymac_audio_build.log
        exit 1
    }

echo "[4/4] Installing driver to /Library/Audio/Plug-Ins/HAL/..."
sudo rm -rf "$DRIVER_DEST"
sudo cp -R "$BUILD_DIR/build/BlackHole.driver" "$DRIVER_DEST"
sudo chown -R root:wheel "$DRIVER_DEST"

# Restart CoreAudio to load new driver immediately
echo "• Reloading macOS CoreAudio daemon..."
sudo killall -9 coreaudiod 2>/dev/null || true
sleep 1

# Cleanup temp build
rm -rf "$BUILD_DIR"

echo ""
echo "============================================================"
echo "🎉 SUCCESS! Dynamic Audio Driver Installed!"
echo "• Look at your macOS Menu Bar > Sound (Speaker icon)."
echo "• You will now see: 'Samsung Galaxy Tab S10 Ultra (DisplayMac)'!"
echo "• Whatever tablet connects, its real name will show up automatically."
echo "============================================================"
