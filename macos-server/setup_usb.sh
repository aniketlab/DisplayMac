#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - Portable Zero-Brew USB Link Setup for macOS
# Automatically downloads official standalone ADB (no Homebrew required)
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - Direct USB-C Zero-Latency Link Setup"
echo "============================================================"

# Check if adb exists, if not download standalone portable adb from Google
ADB_BIN="adb"
if ! command -v adb &> /dev/null; then
    if [ ! -f "./platform-tools/adb" ]; then
        echo "[1/2] Downloading official standalone Google ADB (No Homebrew needed)..."
        curl -s -L -o platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
        unzip -q platform-tools.zip
        rm -f platform-tools.zip
    fi
    ADB_BIN="./platform-tools/adb"
fi

echo "[2/2] Checking connected Samsung Tablet via USB..."
$ADB_BIN start-server > /dev/null 2>&1

DEVICES=$($ADB_BIN devices | grep -v "List" | grep "device" | wc -l | tr -d ' ')

if [ "$DEVICES" -eq 0 ]; then
    echo ""
    echo "⚠️ Tablet not detected over USB. Please verify the following requirements:"
    echo "1. Samsung Settings > Security and privacy: Turn 'Auto Blocker' OFF (Samsung blocks USB data when enabled)."
    echo "2. Settings > Developer Options: Ensure 'USB Debugging' is enabled."
    echo "3. Tablet Display: Tap 'Always Allow' when the USB Debugging authorization prompt appears."
    echo ""
    exit 1
fi

echo "✅ Tablet detected over USB-C!"
echo "⚡ Forwarding ports (7100, 7101, 7102) over 5 Gbps wire..."
$ADB_BIN reverse tcp:7100 tcp:7100
$ADB_BIN reverse tcp:7101 tcp:7101
$ADB_BIN reverse tcp:7102 tcp:7102

echo ""
echo "============================================================"
echo "🎉 USB-C Link Ready! (0.5ms wire latency engaged)"
echo "• Open DisplayMac on your Tablet."
echo "• It will connect to 127.0.0.1 over direct USB wire!"
echo "============================================================"
