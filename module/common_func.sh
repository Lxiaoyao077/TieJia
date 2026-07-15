# Shared helper functions for AlwaysStrong module scripts.
# Merged from PlayIntegrityFix v4.7-inject-s (download/download_fail/sleep_pause)
# and AlwaysStrong enhancements (find_tool, delprop_if_exist, resetprop_hexpatch).

# delprop_if_exist <prop name>
delprop_if_exist() {
    local NAME="$1"
    [ -n "$(resetprop "$NAME")" ] && resetprop -n "$NAME" ""
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

    { [ -z "$NEWVALUE" ] || [ -z "$CURVALUE" ]; } && return 1
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

    local NEWHEX="$(printf '%02x' "$NEWLEN")$(printf '%s' "$NEWVALUE" | od -A n -t x1 -v | tr -d ' \n')$(printf "%$((92-NEWLEN))s" | sed 's/ /00/g')"

    printf "Patch '$NAME' to '$NEWVALUE' in '$PROPFILE' @ 0x%08x -> \n[0000??$NEWHEX]\n" $((NAMEOFFSET-96))

    echo -ne "\x00\x00" \
        | dd obs=1 count=2 seek=$((NAMEOFFSET-96)) conv=notrunc of="$PROPFILE"
    echo -ne "$(printf '%s' "$NEWHEX" | sed -e 's/.\{2\}/&\\x/g' -e 's/^/\\x/' -e 's/\\x$//')" \
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

# --- PIF: sleep_pause / download_fail / download (from v4.7-inject-s) ---
sleep_pause() {
    # APatch and KernelSU needs this
    # but not KSU_NEXT, MMRL
    if [ -z "$MMRL" ] && [ -z "$KSU_NEXT" ] && { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; }; then
        sleep 5
    fi
}

download_fail() {
    dl_domain=$(echo "$1" | awk -F[/:] '{print $4}')
    # Clean up on download fail
    rm -rf "$TEMPDIR"
    ping -c 1 -W 20 "$dl_domain" > /dev/null 2>&1 || {
        echo "[!] Unable to connect to $dl_domain, please check your internet connection and try again"
        sleep_pause
        exit 1
    }
    conflict_module=$(ls /data/adb/modules | grep busybox)
    for i in $conflict_module; do
        echo "[!] Please remove $i and try again."
    done
    echo "[!] download failed!"
    echo "[x] bailing out!"
    sleep_pause
    exit 1
}

download() { busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" || download_fail "$1"; }
if command -v curl > /dev/null 2>&1; then
    download() { curl --connect-timeout 10 -s "$1" > "$2" || download_fail "$1"; }
fi

# --- AlwaysStrong: find_tool ---
# find_tool <cmd> <subcmd> <test_expr>
# Searches for a CLI tool (command or busybox subcommand).
#   $1 — command name (e.g. "base64" / "sha256sum")
#   $2 — busybox subcommand (same as $1 when cmd==subcmd)
#   $3 — test expression piped to the tool (e.g. "echo dGVzdA==")
# Prints the full invocation prefix (e.g. "base64 -d" or "/data/adb/magisk/busybox sha256sum")
# Returns 0 on success, 1 if not found.
find_tool() {
    local cmd="$1" sub="$2" test_expr="${3:-}"
    # System tool
    if [ -n "$test_expr" ]; then
        if printf '%s' "$test_expr" | $cmd >/dev/null 2>&1; then
            printf '%s' "$cmd"; return 0
        fi
    elif command -v "$cmd" >/dev/null 2>&1; then
        printf '%s' "$cmd"; return 0
    fi
    # Busybox fallback
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ]; then
            if [ -n "$test_expr" ]; then
                if printf '%s' "$test_expr" | "$bb" $sub >/dev/null 2>&1; then
                    printf '%s %s' "$bb" "$sub"; return 0
                fi
            else
                printf '%s %s' "$bb" "$sub"; return 0
            fi
        fi
    done
    return 1
}

# --- AlwaysStrong: find_sed (portable sed -i) ---
# Resolves a sed binary with reliable -i support.
# toybox sed (AOSP default) lacks -i; busybox sed always supports it.
# Sets global $SED to e.g. "sed -i" or "/data/adb/magisk/busybox sed -i".
find_sed() {
  SED="sed -i"
  for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    if [ -x "$bb" ]; then SED="$bb sed -i"; return 0; fi
  done
  return 1
}

# --- AlwaysStrong: log_save ---
# Private log fallback: persist.log.tag.* may suppress logd output,
# so we tee to $MODDIR/logs/module.log with restricted permissions.
# Usage: log_save <tag> <message...>
log_save() {
  local tag="$1"; shift
  local msg="$*"
  local logf="${MODDIR:-$MODPATH}/logs/module.log"
  local ts

  mkdir -p "${MODDIR:-$MODPATH}/logs" 2>/dev/null

  ts=$(date '+%m-%d %H:%M:%S' 2>/dev/null)
  (
    umask 077
    echo "[$ts] $msg" >> "$logf" 2>/dev/null
    # Rotate only when > 300 lines to avoid per-call overhead
    if [ "$(wc -l < "$logf" 2>/dev/null)" -gt 300 ]; then
      tail -n 200 "$logf" > "$logf.tmp" 2>/dev/null && mv -f "$logf.tmp" "$logf" 2>/dev/null
    fi
  )
  # Also send to logd (may be suppressed)
  echo "$msg" | log -t "$tag" 2>/dev/null
}

# --- Shared downloader tool resolution (dedup from action.sh / keybox_fetch.sh / pif_native_fetch.sh) ---
# Call resolve_asfetch first, then use dl_out / dl_to anywhere.

ASFETCH=""
resolve_asfetch() {
    local sdir="${1:-$(cd "${0%/*}" 2>/dev/null && pwd)}"
    [ -z "$sdir" ] && sdir=/data/adb/modules/tricky_store
    case "$(uname -m)" in
        aarch64)        ABI=arm64-v8a ;;
        armv7*|armv8l)  ABI=armeabi-v7a ;;
        x86_64)         ABI=x86_64 ;;
        i?86)           ABI=x86 ;;
        *)              ABI="" ;;
    esac
    [ -n "$ABI" ] && [ -x "$sdir/bin/$ABI/asfetch" ] && ASFETCH="$sdir/bin/$ABI/asfetch"
}

BB=""
resolve_bb() {
    [ -n "$BB" ] && return 0
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox               /data/adb/modules/busybox-ndk/system/*/busybox; do
        [ -x "$bb" ] && BB="$bb" && return 0
    done
    return 1
}

# dl_out <url> — fetch to stdout via best available tool
dl_out() {
    if [ -n "$ASFETCH" ]; then $ASFETCH -T 20 "$1" 2>/dev/null && return 0; fi
    resolve_bb
    if [ -n "$BB" ]; then $BB wget -q -T 20 -O - "$1" 2>/dev/null && return 0; fi
    if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 20 "$1" 2>/dev/null && return 0; fi
    if command -v wget >/dev/null 2>&1; then wget -q -T 20 -O - "$1" 2>/dev/null && return 0; fi
    return 1
}

# dl_to <dst> <url> — fetch to file via best available tool
dl_to() {
    if [ -n "$ASFETCH" ]; then rm -f "$1"; $ASFETCH -T 60 -o "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    resolve_bb
    if [ -n "$BB" ]; then rm -f "$1"; $BB wget -q -T 60 -O "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    if command -v curl >/dev/null 2>&1; then rm -f "$1"; curl -fsSL --max-time 60 -o "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    if command -v wget >/dev/null 2>&1; then rm -f "$1"; wget -q -T 60 -O "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    return 1
}

# ---- Enforce STRONG spoof settings on a custom.pif.prop ----
# Usage: enforce_spoof <custom.pif.prop path>
enforce_spoof() {
    _pf="$1"
    [ -f "$_pf" ] || return 1
    find_sed
    for _kv in spoofProvider=0 spoofVendingFinger=1 spoofBuild=1 \
              spoofProps=1 spoofSignature=0 spoofVendingSdk=0; do
        _k="${_kv%%=*}"; _v="${_kv##*=}"
        if grep -qE "^${_k}=" "$_pf"; then
            $SED "s|^${_k}=.*|${_k}=${_v}|" "$_pf"
        else
            echo "${_k}=${_v}" >> "$_pf"
        fi
    done
}

