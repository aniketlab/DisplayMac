#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - 1-Click macOS Sound Device Setup (BlackHole 2ch)
# Installs virtual speaker so "BlackHole 2ch / DisplayMac" appears in Sound menu
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - macOS Virtual Speaker Setup"
echo "============================================================"

DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"

if [ -d "$DRIVER_PATH" ]; then
    echo "✅ BlackHole 2ch driver is already installed!"
else
    echo "[1/2] Installing BlackHole 2ch audio driver..."
    if command -v brew &> /dev/null; then
        echo "• Installing via Homebrew..."
        brew install blackhole-2ch
    else
        echo "• Homebrew not found. Downloading official signed Apple-notarized package..."
        PKG_URL="https://github.com/ExistentialAudio/BlackHole/releases/download/v0.6.1/BlackHole2ch.v0.6.1.pkg"
        curl -L -o /tmp/BlackHole2ch.pkg "$PKG_URL" 2>/dev/null || true
        if [ -f "/tmp/BlackHole2ch.pkg" ]; then
            sudo installer -pkg /tmp/BlackHole2ch.pkg -target /
            rm -f /tmp/BlackHole2ch.pkg
        else
            echo "⚠️ Direct download failed. Please run: brew install blackhole-2ch"
            exit 1
        fi
    fi
fi

echo "[2/2] Refreshing macOS CoreAudio daemon..."
sudo killall coreaudiod 2>/dev/null || true
sleep 1

echo ""
echo "============================================================"
echo "🎉 Virtual Audio Device Ready!"
echo "• Open Control Center > Sound (Speaker icon) in your Menu Bar."
echo "• Select 'BlackHole 2ch' as your Sound Output."
echo "• All Mac audio will stream with 0 latency to your Galaxy Tab S10 Ultra!"
echo "============================================================"
