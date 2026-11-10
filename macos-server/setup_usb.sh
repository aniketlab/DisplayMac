#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - USB-C ADB Reverse Tunnel Setup (macOS)
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo "  DisplayMac - USB-C Link Setup"
echo "============================================================"

ADB_BIN="adb"
if ! command -v adb &> /dev/null; then
    if [ ! -f "./platform-tools/adb" ]; then
        echo "[1/2] Downloading Google Android platform-tools..."
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf "$TMP_DIR"' EXIT
        curl -fsSL -o "$TMP_DIR/platform-tools.zip" \
            https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
        unzip -q "$TMP_DIR/platform-tools.zip" -d .
    fi
    ADB_BIN="./platform-tools/adb"
fi

echo "[2/2] Checking connected Android device via USB..."
"$ADB_BIN" start-server > /dev/null 2>&1

DEVICES="$("$ADB_BIN" devices | grep -v "List" | grep -c $'\tdevice' || true)"

if [ "$DEVICES" -eq 0 ]; then
    echo ""
    echo "No authorized Android device detected over USB. Check:"
    echo "1. Developer Options: Enable USB Debugging."
    echo "2. Accept the 'Allow USB debugging' prompt on the tablet."
    echo "3. On Samsung One UI, verify Auto Blocker does not block USB data."
    echo ""
    exit 1
fi

echo "Device detected. Forwarding ports (7100, 7101, 7102)..."
"$ADB_BIN" reverse tcp:7100 tcp:7100
"$ADB_BIN" reverse tcp:7101 tcp:7101
"$ADB_BIN" reverse tcp:7102 tcp:7102

echo "USB-C ADB reverse tunnel active. Tap 'Connect with USB-C' on your tablet."
