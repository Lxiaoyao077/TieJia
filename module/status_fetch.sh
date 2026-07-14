#!/system/bin/sh
# Fetch keybox status and write to /data/adb/tricky_store/indicator.txt.
# Usage: status_fetch.sh [strip]
#   strip: remove indicator.txt.
#   (no arg): fetch and update indicator.txt only.

CONFIG_DIR=/data/adb/tricky_store

if [ "$1" = "strip" ]; then
    rm -f "$CONFIG_DIR/indicator.txt" 2>/dev/null
    exit 0
fi

URL="https://botkey.netlify.app/status"
INDICATOR="$CONFIG_DIR/indicator.txt"
TIMEOUT=8

new=$(busybox wget -T "$TIMEOUT" -qO - "$URL" 2>/dev/null | tr -d '\r\n' | head -c 64)
[ -z "$new" ] && exit 2

# indicator.txt for action.sh summary
old=$(cat "$INDICATOR" 2>/dev/null)
[ "$old" != "$new" ] && { mkdir -p "$CONFIG_DIR"; echo "$new" > "$INDICATOR"; }
