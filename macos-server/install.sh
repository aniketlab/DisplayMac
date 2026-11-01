#!/usr/bin/env bash
# ==============================================================================
# DisplayMac Server - Installer Forwarder
# ==============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/../install.sh" ]; then
    exec "$DIR/../install.sh"
else
    echo "❌ Error: Root install.sh not found."
    exit 1
fi
