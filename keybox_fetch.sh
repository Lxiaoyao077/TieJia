#!/system/bin/sh
# TieJia — keybox auto-fetch (multi-source).
#
# Sources are tried in priority order until one succeeds:
#   1. Yurikey  (base64)
#   2. Upstream (hex → base64)
#
# Encoding auto-detected per source. XML validated after decode.
# SHA256 dedup against on-disk /data/adb/tricky_store/keybox.xml.
# Atomic replace on update.
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change / skipped (custom keybox active, or bundled up-to-date)
#   1  all sources failed (existing keybox preserved)

CONFIG_DIR=/data/adb/tricky_store
TARGET="$CONFIG_DIR/keybox.xml"

log() { echo "keybox_fetch: $*"; }

# Custom-keybox mode: the user manages keybox.xml themselves via the WebUI.
if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    log "custom keybox active — skipping fetch."
    exit 2
fi

# ---- Resolve tools (via common_func.sh) ----
SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
[ -f "$SELF_DIR/common_func.sh" ] && . "$SELF_DIR/common_func.sh"
resolve_asfetch "$SELF_DIR"
resolve_bb

# run_engine NAME OUTFILE URL — one download attempt with the named engine.
run_engine() {
    rm -f "$2"
    case "$1" in
        asfetch) [ -n "$ABI" ] && [ -x "$ASFETCH" ] && "$ASFETCH" -T 10 -o "$2" "$3" 2>/dev/null ;;
        bb)      [ -n "$BB" ] && "$BB" wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
        curl)    command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --max-time 30 -o "$2" "$3" 2>/dev/null ;;
        wget)    command -v wget >/dev/null 2>&1 && wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
    esac
    [ -s "$2" ]
}

# try_fetch OUTFILE URL — try each engine until one returns a non-empty file.
ENGINE_CACHE="$CONFIG_DIR/.kb_engine"
try_fetch() {
    _o="$1"; _u="$2"
    _first=$(cat "$ENGINE_CACHE" 2>/dev/null)
    for _e in "$_first" asfetch bb curl wget; do
        [ -z "$_e" ] && continue
        if run_engine "$_e" "$_o" "$_u"; then
            [ "$_e" != "$_first" ] && echo "$_e" > "$ENGINE_CACHE" 2>/dev/null
            return 0
        fi
    done
    return 1
}

# resolve_base64 — find a working base64 decoder, echo the command string.
resolve_base64() {
    if echo dGVzdA== | base64 -d >/dev/null 2>&1; then
        echo "base64 -d"; return 0
    fi
    for _bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$_bb" ] && echo dGVzdA== | "$_bb" base64 -d >/dev/null 2>&1; then
            echo "$_bb base64 -d"; return 0
        fi
    done
    return 1
}

# pure_shell_hex_decode HEX_STRING — echo raw bytes (works with toybox/busybox xxd or fallback)
pure_shell_hex_decode() {
    _h="$1"
    # prefer xxd if available (toybox/busybox)
    if command -v xxd >/dev/null 2>&1; then
        echo "$_h" | xxd -r -p 2>/dev/null && return 0
    fi
    # fallback: printf each byte
    _len=${#_h}
    _i=0
    while [ "$_i" -lt "$_len" ]; do
        printf "\\x${_h:$_i:2}"
        _i=$((_i + 2))
    done
    return 0
}

# decode_payload IN OUT ENCODING — decode into OUT based on encoding hint.
decode_payload() {
    _in="$1"; _out="$2"; _enc="$3"
    case "$_enc" in
        xml)
            cp "$_in" "$_out" 2>/dev/null
            ;;
        b64)
            _d=$(resolve_base64) || { return 1; }
            $_d < "$_in" > "$_out" 2>/dev/null
            ;;
        hex+b64)
            _d=$(resolve_base64) || { return 1; }
            _hex=$(tr -cd '0-9A-Fa-f' < "$_in" | tr -d '\n')
            [ -z "$_hex" ] && return 1
            # ensure even length
            [ $(( ${#_hex} % 2 )) -ne 0 ] && _hex="${_hex%?}"
            pure_shell_hex_decode "$_hex" | $_d > "$_out" 2>/dev/null
            ;;
        *) return 1 ;;
    esac
    [ -s "$_out" ]
}

# validate_keybox FILE — check it looks like valid XML with Keybox tag.
validate_keybox() {
    head -c 4096 "$1" 2>/dev/null | grep -qi -e Keybox -e AndroidAttestation
}

# resolve_sha256 — echo sha256sum command string.
resolve_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"; return 0
    fi
    for _bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$_bb" ] && echo x | "$_bb" sha256sum >/dev/null 2>&1; then
            echo "$_bb sha256sum"; return 0
        fi
    done
    return 1
}

# try_one_source NAME URL ENCODING — returns via $? (0=updated, 2=up-to-date, 1=fail)
try_one_source() {
    __src="$1"; __url="$2"; __enc="$3"

    log "  trying $__src ..."

    try_fetch "$TMP/raw" "$__url" || { log "    $__src: download failed."; return 1; }

    decode_payload "$TMP/raw" "$TMP/keybox.xml" "$__enc" || {
        log "    $__src: decode failed."
        return 1
    }

    if ! validate_keybox "$TMP/keybox.xml"; then
        log "    $__src: not a valid keybox — skipping."
        return 1
    fi

    log "    $__src: valid keybox ($(wc -c < "$TMP/keybox.xml") bytes)."

    SHA256=$(resolve_sha256) || { log "    no sha256sum."; return 1; }
    NEW_HASH=$($SHA256 < "$TMP/keybox.xml" | awk '{print tolower($1)}')
    DISK_HASH=""
    [ -s "$TARGET" ] && DISK_HASH=$($SHA256 < "$TARGET" | awk '{print tolower($1)}')

    if [ -n "$DISK_HASH" ] && [ "$DISK_HASH" = "$NEW_HASH" ]; then
        log "    $__src: already up to date."
        return 2
    fi

    # atomic replace
    mv -f "$TMP/keybox.xml" "$TARGET" || { log "    mv to $TARGET failed."; return 1; }
    chmod 600 "$TARGET"
    rm -f "$CONFIG_DIR/.keybox.sha256" 2>/dev/null
    log "  => $TARGET updated from $__src ($(wc -c < "$TARGET") bytes)."
    return 0
}

# ---- Main ----
mkdir -p "$CONFIG_DIR"
TMP="$CONFIG_DIR/.keybox_fetch.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Accept optional source argument for single-source mode.
#   keybox_fetch.sh yurikey   → only try yurikey
#   keybox_fetch.sh upstream  → only try upstream
#   keybox_fetch.sh           → auto (try all)
case "${1:-}" in
    yurikey)
        try_one_source "yurikey" "https://raw.githubusercontent.com/Yurii0307/yurikey/main/key" "b64"
        exit $?
        ;;
    upstream)
        try_one_source "upstream" "https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra" "hex+b64"
        exit $?
        ;;
esac

# Auto mode: try all sources in priority order.
# 1. Yurikey (base64)
try_one_source "yurikey" "https://raw.githubusercontent.com/Yurii0307/yurikey/main/key" "b64"
_rc=$?
if [ $_rc -eq 0 ] || [ $_rc -eq 2 ]; then
    exit $_rc
fi

# 2. Upstream (hex+b64)
try_one_source "upstream" "https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra" "hex+b64"
_rc=$?
if [ $_rc -eq 0 ] || [ $_rc -eq 2 ]; then
    exit $_rc
fi

# All sources exhausted.
log "all sources exhausted — keybox unchanged."
exit 1
