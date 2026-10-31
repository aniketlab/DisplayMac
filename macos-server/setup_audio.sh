#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - macOS Virtual Speaker Setup
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac - macOS Virtual Speaker Setup"
echo "============================================================"

DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"

if [ -d "$DRIVER_PATH" ]; then
    echo "✅ BlackHole 2ch driver is already installed!"
else
    if command -v brew &> /dev/null; then
        echo "• Installing BlackHole 2ch via Homebrew..."
        brew install blackhole-2ch
        echo "• Refreshing macOS CoreAudio daemon..."
        sudo killall coreaudiod 2>/dev/null || true
        echo "✅ Installed successfully!"
    else
        echo ""
        echo "💡 Note: DisplayMac automatically captures and streams Mac system audio"
        echo "   over USB wire (Port 7102) WITHOUT needing BlackHole!"
        echo ""
        echo "   If you want 'BlackHole 2ch' to explicitly appear in your Sound menu:"
        echo "   1. Open: https://existential.audio/blackhole/ in Safari"
        echo "   2. Download the free 2ch installer .pkg and run it."
        echo ""
    fi
fi
