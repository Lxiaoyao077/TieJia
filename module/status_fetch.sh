#!/system/bin/sh
# Determine local keybox health and write to indicator.txt. — TieJia v2.0.0
# No network — reads on-disk keybox.xml validity directly.
# Usage: status_fetch.sh [strip]
#   strip: remove indicator.txt.
#   (no arg): inspect local keybox and update indicator.txt.

SELF_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
. "$SELF_DIR/common_func.sh"
init_config

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

if is_valid_keybox "$KB"; then
    echo "🟢" > "$INDICATOR"
else
    echo "🔴" > "$INDICATOR"
fi
