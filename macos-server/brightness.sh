#!/usr/bin/env bash
# ==============================================================================
# DisplayMac - CLI AMOLED Brightness Controller
# Usage:
#   ./brightness.sh 80    -> Set brightness to 80%
#   ./brightness.sh +     -> Increase brightness (+10%)
#   ./brightness.sh -     -> Decrease brightness (-10%)
# ==============================================================================

VAL="$1"
if [ -z "$VAL" ]; then
    echo "============================================================"
    echo "  DisplayMac AMOLED Brightness Controller"
    echo "============================================================"
    echo "Usage: ./brightness.sh <percent (1-100) or + or ->"
    echo ""
    echo "Examples:"
    echo "  ./brightness.sh 100   -> Max 1750 nits peak brightness"
    echo "  ./brightness.sh 50    -> 50% comfortable brightness"
    echo "  ./brightness.sh +     -> Increase by 10%"
    echo "  ./brightness.sh -     -> Decrease by 10%"
    echo "============================================================"
    exit 1
fi

echo "$VAL" > /tmp/displaymac_brightness
echo "☀️ [DisplayMac] AMOLED Brightness command sent: '$VAL'"
