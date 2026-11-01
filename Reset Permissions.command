#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/reset_permissions.sh"
echo ""
read -p "Press [Enter] to exit..."
