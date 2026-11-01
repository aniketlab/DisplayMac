#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/install.sh"
echo ""
read -p "Press [Enter] to exit..."
