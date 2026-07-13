#!/system/bin/sh
# Fetch the keybox status (e.g. "🟢🟢🟢") and write to
# /data/adb/tricky_store/indicator.txt (read by WebUI + action.sh).
# No longer touches module.prop — avoids KSU tamper-detection false positives.

URL="https://botkey.netlify.app/status"
CONFIG_DIR=/data/adb/tricky_store
INDICATOR="$CONFIG_DIR/indicator.txt"
TIMEOUT=8

BB=""
for p in /data/adb/modules/busybox-ndk/system/*/busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    [ -f "$p" ] && BB="$p" && break
done

SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"
[ -z "$SELF_DIR" ] && SELF_DIR="$MODPATH"

case "$(uname -m)" in
    aarch64)       SF_ABI=arm64-v8a ;;
    armv7*|armv8l) SF_ABI=armeabi-v7a ;;
    *)             SF_ABI="" ;;
esac
ASFETCH="$SELF_DIR/bin/$SF_ABI/asfetch"

if [ -n "$SF_ABI" ] && [ -x "$ASFETCH" ]; then
    fetch="$ASFETCH -T $TIMEOUT"
elif command -v curl >/dev/null 2>&1; then
    fetch="curl -fsSL --max-time $TIMEOUT"
elif [ -n "$BB" ]; then
    fetch="$BB wget -q -T $TIMEOUT -O -"
elif command -v wget >/dev/null 2>&1; then
    fetch="wget -q -T $TIMEOUT -O -"
else
    exit 2
fi

new=$($fetch "$URL" 2>/dev/null | tr -d '\r\n' | head -c 64)
[ -z "$new" ] && exit 3

# Only write if changed (avoid unnecessary disk writes)
old=$(cat "$INDICATOR" 2>/dev/null)
[ "$old" = "$new" ] && exit 0

mkdir -p "$CONFIG_DIR"
echo "$new" > "$INDICATOR"
