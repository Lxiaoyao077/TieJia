#!/system/bin/sh
# Determine local keybox health and write to indicator.txt.
# No network — reads on-disk keybox.xml validity directly.
# Usage: status_fetch.sh [strip]
#   strip: remove indicator.txt.
#   (no arg): inspect local keybox and update indicator.txt.

CONFIG_DIR=/data/adb/tricky_store
INDICATOR="$CONFIG_DIR/indicator.txt"

if [ "$1" = "strip" ]; then
    rm -f "$INDICATOR" 2>/dev/null
    exit 0
fi

KB="$CONFIG_DIR/keybox.xml"

if [ ! -s "$KB" ]; then
    echo "" > "$INDICATOR"
    exit 0
fi

# valid keybox: non-empty, XML with Keybox/AndroidAttestation tag
if head -c 4096 "$KB" 2>/dev/null | grep -qi -e Keybox -e AndroidAttestation; then
    echo "🟢" > "$INDICATOR"
else
    echo "🔴" > "$INDICATOR"
fi
