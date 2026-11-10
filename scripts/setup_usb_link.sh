#!/usr/bin/env bash
# ==============================================================================
# DisplayMac USB-C ADB Port Forwarding Helper
# ==============================================================================

set -euo pipefail

if ! command -v adb &> /dev/null; then
    echo "Error: adb not found in PATH. Install Android platform-tools first."
    exit 1
fi

DEVICE_COUNT="$(adb devices | grep -v "List" | grep -c $'\tdevice' || true)"
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "No authorized Android device detected over USB. Enable USB Debugging."
    exit 1
fi

echo "Forwarding DisplayMac TCP ports (7100, 7101, 7102) over ADB..."
adb reverse tcp:7100 tcp:7100
adb reverse tcp:7101 tcp:7101
adb reverse tcp:7102 tcp:7102

echo "USB-C port forwarding active."
