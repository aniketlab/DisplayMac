#!/usr/bin/env bash
# ==============================================================================
# DisplayMac 🛡️ macOS Privacy & Permissions Reset Utility
# Resets Accessibility, Screen Recording, and Input Monitoring permissions
# for Terminal, iTerm2, and DisplayMac in macOS System Settings > Privacy & Security.
# ==============================================================================

set -e

echo "============================================================"
echo "  DisplayMac 🛡️ Resetting Privacy & Security Permissions"
echo "============================================================"
echo "Revoking permissions granted to Terminal and DisplayMac..."

# 1. Reset Accessibility permissions
echo "• Revoking Accessibility permissions..."
tccutil reset Accessibility com.apple.Terminal 2>/dev/null || true
tccutil reset Accessibility com.googlecode.iterm2 2>/dev/null || true
tccutil reset Accessibility com.microsoft.VSCode 2>/dev/null || true
tccutil reset Accessibility com.displaymac.server 2>/dev/null || true
sudo tccutil reset Accessibility com.apple.Terminal 2>/dev/null || true
sudo tccutil reset Accessibility com.googlecode.iterm2 2>/dev/null || true

# 2. Reset Screen Recording permissions (ScreenCapture)
echo "• Revoking Screen Recording permissions..."
tccutil reset ScreenCapture com.apple.Terminal 2>/dev/null || true
tccutil reset ScreenCapture com.googlecode.iterm2 2>/dev/null || true
tccutil reset ScreenCapture com.microsoft.VSCode 2>/dev/null || true
tccutil reset ScreenCapture com.displaymac.server 2>/dev/null || true
sudo tccutil reset ScreenCapture com.apple.Terminal 2>/dev/null || true
sudo tccutil reset ScreenCapture com.googlecode.iterm2 2>/dev/null || true

# 3. Reset Input Monitoring permissions (ListenEvent)
echo "• Revoking Input Monitoring permissions..."
tccutil reset ListenEvent com.apple.Terminal 2>/dev/null || true
tccutil reset ListenEvent com.googlecode.iterm2 2>/dev/null || true
sudo tccutil reset ListenEvent com.apple.Terminal 2>/dev/null || true

# Optional system-wide wipe if requested via --all or -a
if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    echo "• Performing system-wide global reset for Accessibility and ScreenCapture..."
    tccutil reset Accessibility 2>/dev/null || true
    tccutil reset ScreenCapture 2>/dev/null || true
    echo "✅ Global system permissions reset."
fi

echo ""
echo "============================================================"
echo "  ✅ Permissions successfully reset!"
echo "  • Terminal removed from Accessibility"
echo "  • Terminal removed from Screen Recording"
echo "  Next time DisplayMac runs, macOS will show fresh permission"
echo "  authorization prompts in System Settings."
echo "============================================================"
