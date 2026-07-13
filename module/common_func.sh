# Shared helper functions for AlwaysStrong module scripts.
# Adapted from PlayIntegrityFork's common_func.sh (osm0sis, chiteroman, Displax).

SKIPDELPROP=false
[ -f "$MODPATH/skipdelprop" ] && SKIPDELPROP=true

# delprop_if_exist <prop name>
delprop_if_exist() {
    local NAME="$1"
    [ -n "$(resetprop "$NAME")" ] && resetprop --delete "$NAME"
}

SKIPPERSISTPROP=false
[ -f "$MODPATH/skippersistprop" ] && SKIPPERSISTPROP=true

# persistprop <prop name> <new value>
persistprop() {
    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE="$(resetprop "$NAME")"

    if ! grep -q "$NAME" "$MODPATH/uninstall.sh" 2>/dev/null; then
        if [ "$CURVALUE" ]; then
            [ "$NEWVALUE" = "$CURVALUE" ] || echo "resetprop -n -p \"$NAME\" \"$CURVALUE\"" >> "$MODPATH/uninstall.sh"
        else
            echo "resetprop -p --delete \"$NAME\"" >> "$MODPATH/uninstall.sh"
        fi
    fi
    resetprop -n -p "$NAME" "$NEWVALUE"
}

RESETPROP="resetprop -n"
[ -f /data/adb/magisk/util_functions.sh ] && [ "$(grep MAGISK_VER_CODE /data/adb/magisk/util_functions.sh | cut -d= -f2)" -lt 27003 ] && RESETPROP=resetprop_hexpatch

# resetprop_hexpatch [-f|--force] <prop name> <new value>
resetprop_hexpatch() {
    case "$1" in
        -f|--force) local FORCE=1; shift;;
    esac

    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE="$(resetprop "$NAME")"

    [ ! "$NEWVALUE" -o ! "$CURVALUE" ] && return 1
    [ "$NEWVALUE" = "$CURVALUE" -a ! "$FORCE" ] && return 2

    local NEWLEN=${#NEWVALUE}
    if [ -f /dev/__properties__ ]; then
        local PROPFILE=/dev/__properties__
    else
        local PROPFILE="/dev/__properties__/$(resetprop -Z "$NAME")"
    fi
    [ ! -f "$PROPFILE" ] && return 3
    local NAMEOFFSET
    NAMEOFFSET=$(echo $(strings -t d "$PROPFILE" | grep "$NAME") | cut -d\  -f1)

    local NEWHEX="$(printf '%02x' "$NEWLEN")$(printf "$NEWVALUE" | od -A n -t x1 -v | tr -d ' \n')$(printf "%$((92-NEWLEN))s" | sed 's/ /00/g')"

    printf "Patch '$NAME' to '$NEWVALUE' in '$PROPFILE' @ 0x%08x -> \n[0000??$NEWHEX]\n" $((NAMEOFFSET-96))

    echo -ne "\x00\x00" \
        | dd obs=1 count=2 seek=$((NAMEOFFSET-96)) conv=notrunc of="$PROPFILE"
    echo -ne "$(printf "$NEWHEX" | sed -e 's/.\{2\}/&\\x/g' -e 's/^/\\x/' -e 's/\\x$//')" \
        | dd obs=1 count=93 seek=$((NAMEOFFSET-93)) conv=notrunc of="$PROPFILE"
}

# resetprop_if_diff <prop name> <expected value>
resetprop_if_diff() {
    local NAME="$1"
    local EXPECTED="$2"
    local CURRENT
    CURRENT="$(resetprop "$NAME")"
    [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
}

# resetprop_if_match <prop name> <value match string> <new value>
resetprop_if_match() {
    local NAME="$1"
    local CONTAINS="$2"
    local VALUE="$3"
    [[ "$(resetprop "$NAME")" = *"$CONTAINS"* ]] && $RESETPROP "$NAME" "$VALUE"
}

# stub for boot-time
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    ui_print() { return; }
fi

# --- Shared ABI detection (ARM-only module) ---
# Usage: get_abi_var VARNAME
# Sets the named variable to "arm64-v8a" / "armeabi-v7a" / "" based on uname.
get_abi() {
    case "$(uname -m)" in
        aarch64)       echo "arm64-v8a" ;;
        armv7*|armv8l) echo "armeabi-v7a" ;;
        *)             echo "" ;;
    esac
}

# --- Shared fetch tool resolver (asfetch > curl > wget > busybox wget) ---
# Usage: resolve_fetcher [-o] [timeout_sec]
#   -o        : download mode (output to file), default is stdout mode
#   timeout   : timeout in seconds (default 20)
# Output on stdout: the command prefix to use (e.g. "/path/asfetch -T 20").
resolve_fetcher() {
    local mode="-" timeout=20
    while [ $# -gt 0 ]; do
        case "$1" in
            -o) mode="-o"; shift ;;
            *)  timeout="$1"; shift ;;
        esac
    done
    local SELF_DIR; SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
    [ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
    local ABI; ABI=$(get_abi)
    if [ -n "$ABI" ] && [ -x "$SELF_DIR/bin/$ABI/asfetch" ]; then
        echo "$SELF_DIR/bin/$ABI/asfetch -T $timeout $mode"
        return
    fi
    if command -v curl >/dev/null 2>&1; then
        if [ "$mode" = "-o" ]; then
            echo "curl -fsSL --connect-timeout 10 --max-time $timeout -o"
        else
            echo "curl -fsSL --max-time $timeout"
        fi
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        echo "wget -q -T $timeout -O -"
        return
    fi
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ]; then echo "$bb wget -q -T $timeout -O -"; return; fi
    done
    return 1
}

