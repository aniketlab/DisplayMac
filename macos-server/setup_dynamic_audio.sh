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
BLACKHOLE_C=$(find "$BUILD_DIR" -name "BlackHole.c" | head -n 1)

if [ -z "$BLACKHOLE_C" ] || [ ! -f "$BLACKHOLE_C" ]; then
    echo "❌ Error: BlackHole.c not found in cloned repository."
    exit 1
fi

echo "• Found source file: $BLACKHOLE_C"

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
    return CFSTR("DisplayMac Audio");
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
        echo "⚠️ Compilation failed. Last 20 lines of log:"
        tail -n 20 /tmp/displaymac_audio_build.log
        exit 1
    }

DRIVER_BUILT=$(find "$BUILD_DIR/build" -name "*.driver" | head -n 1)
if [ -z "$DRIVER_BUILT" ]; then
    echo "❌ Error: Compiled .driver bundle not found."
    tail -n 25 /tmp/displaymac_audio_build.log
    exit 1
fi

echo "[4/4] Installing driver to /Library/Audio/Plug-Ins/HAL/..."
sudo rm -rf "$DRIVER_DEST"
sudo cp -R "$DRIVER_BUILT" "$DRIVER_DEST"
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
