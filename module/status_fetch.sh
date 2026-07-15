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

# resolve busybox / curl for fetch
BB=""
for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox; do
    [ -x "$bb" ] && BB="$bb" && break
done
if [ -n "$BB" ]; then
    new=$("$BB" wget -T "$TIMEOUT" -qO - "$URL" 2>/dev/null | tr -d '\r\n' | dd bs=64 count=1 2>/dev/null)
elif command -v curl >/dev/null 2>&1; then
    new=$(curl -fsSL --max-time "$TIMEOUT" "$URL" 2>/dev/null | tr -d '\r\n' | dd bs=64 count=1 2>/dev/null)
elif command -v wget >/dev/null 2>&1; then
    new=$(wget -q -T "$TIMEOUT" -O - "$URL" 2>/dev/null | tr -d '\r\n' | dd bs=64 count=1 2>/dev/null)
else
    exit 2
fi
[ -z "$new" ] && exit 2

# indicator.txt for action.sh summary
old=$(cat "$INDICATOR" 2>/dev/null)
[ "$old" != "$new" ] && { mkdir -p "$CONFIG_DIR"; echo "$new" > "$INDICATOR"; }
