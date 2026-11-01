#!/usr/bin/env bash
# ==============================================================================
# DisplayMac USB Link Helper
# Automatically sets up high-speed USB port forwarding via ADB
# ==============================================================================

set -e

echo "⚡ [DisplayMac] Configuring Direct USB-C Link via ADB..."

# Verify ADB is installed
if ! command -v adb &> /dev/null; then
    echo "❌ ADB not found in PATH. Please install Android Platform Tools."
    exit 1
fi

DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "⚠️ No Android device detected over USB. Make sure USB Debugging is ON."
    exit 1
fi

echo "📱 Android device detected! Reversing network ports..."
# Reverse Control Channel (7100) and Video Channel (7101) so tablet can reach Mac via 127.0.0.1
adb reverse tcp:7100 tcp:7100
adb reverse tcp:7101 tcp:7101

echo "✅ USB-C High-Speed Link Ready! (Port 7100 & 7101 mapped to localhost)"
echo "Launch DisplayMacServer on macOS and open DisplayMac on your Samsung Tab."
