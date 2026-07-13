#!/system/bin/sh
# Fetch keybox status and write to module.prop description (KSU Manager + WebUI)
# AND /data/adb/tricky_store/indicator.txt (action.sh summary).
# Usage: status_fetch.sh [strip]
#   strip: removes status prefix from module.prop description.
#   (no arg): fetch and update.

CONFIG_DIR=/data/adb/tricky_store
MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"
BASE_DESC_DEFAULT="Always Strong integrity module"

if [ "$1" = "strip" ]; then
    CUR=$(grep -m1 '^description=' "$MODPATH/module.prop" 2>/dev/null)
    if [ -n "$CUR" ]; then
        STRIPPED=$(echo "$CUR" | sed 's/^description=//' | sed 's/^[^ ]* //')
        [ -z "$STRIPPED" ] && STRIPPED="$BASE_DESC_DEFAULT"
        if [ "$CUR" != "description=$STRIPPED" ]; then
            sed -i "s|^description=.*|description=$STRIPPED|" "$MODPATH/module.prop"
        fi
    fi
    rm -f "$CONFIG_DIR/indicator.txt" 2>/dev/null
    exit 0
fi

URL="https://botkey.netlify.app/status"
INDICATOR="$CONFIG_DIR/indicator.txt"
TIMEOUT=8

[ -f "$MODPATH/common_func.sh" ] && . "$MODPATH/common_func.sh"

fetch=$(resolve_fetcher "$TIMEOUT")
[ -z "$fetch" ] && exit 2

new=$($fetch "$URL" 2>/dev/null | tr -d '\r\n' | head -c 64)
[ -z "$new" ] && exit 3

# indicator.txt for action.sh summary
old=$(cat "$INDICATOR" 2>/dev/null)
[ "$old" != "$new" ] && { mkdir -p "$CONFIG_DIR"; echo "$new" > "$INDICATOR"; }

# module.prop description — what KSU Manager and WebUI actually display.
# Format: "<status> description_text"
BASE_DESC=$(grep -m1 '^description=' "$MODPATH/module.prop" 2>/dev/null | sed 's/^description=//' | sed 's/^[^ ]* //')
[ -z "$BASE_DESC" ] && BASE_DESC="$BASE_DESC_DEFAULT"
NEW_DESC="description=${new} ${BASE_DESC}"
CUR=$(grep -m1 '^description=' "$MODPATH/module.prop" 2>/dev/null)
[ "$CUR" != "$NEW_DESC" ] && sed -i "s|^description=.*|${NEW_DESC}|" "$MODPATH/module.prop"

