#!/system/bin/sh
# TieJia v2.0.0 — primary fingerprint fetch.
#
# Unified fingerprint fetcher: replaces autopif.sh and pif_native_fetch.sh.
# Crawls Google's Pixel build servers (developer.android.com → flash.android.com
# → content-flashstation-pa.googleapis.com → source.android.com), driven by
# our statically-linked rustls fetcher (asfetch) with curl / busybox wget
# fallback. asfetch speaks TLS 1.2/1.3 correctly everywhere, avoiding the
# busybox-wget TLS stall that silently breaks autopif.sh on some devices/CDNs.
#
# Supports autopif.sh-compatible flags (-s -m -a -l) for drop-in replacement.
# On success writes a minimal Pixel Canary pif.prop to $CONFIG_DIR/pif.prop
# and exits 0. Any failure exits non-zero and leaves the existing pif untouched.
#
# Exit codes:
#   0  fresh fingerprint written
#   1  crawl/parse failed (nothing written)

SELF_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
. "$SELF_DIR/common_func.sh"
init_config

# ---- Parse flags (compatible with autopif.sh / autopif4.sh callers) ----
FORCE_STRONG=1 FORCE_MATCH=1
while [ $# -gt 0 ]; do
    case "$1" in
        -s|--strong)   shift ;;
        -m|--match)    shift ;;
        -a|--advanced) shift ;;
        -l|--list)     LIST_ONLY=1; shift ;;
        -h|--help)     echo "pif_native_fetch.sh [-s] [-m] [-a] [-l]"; exit 0 ;;
        *) break ;;
    esac
done

TARGET="$CONFIG_DIR/pif.prop"
TIMEOUT=10

log() { echo "pif_native_fetch: $*"; }

# ---- Resolve ABI + fetcher binaries (via common_func) ----
MODDIR="${SELF_DIR}"
detect_abi || true
load_proxy

# asfetch path (pif-specific: we need it even if fetch_url is used elsewhere)
ASFETCH="${ABI_BIN_DIR:-$SELF_DIR/bin/$ABI_DIR}/asfetch"

# ---- Busybox finder (via common_func) ----
find_busybox || true

# fetch OUTFILE URL [REFERER] — REFERER required by flashstation API, guarded
# by a referrer-restricted browser key. Uses common_func's fetch_url with
# asfetch first (IPv4-first, works on IPv6-only-DNS networks), then curl/wget.
fetch() {
    _o="$1"; _u="$2"; _ref="$3"
    # Minimum valid PIF JSON size is ~50 bytes; 16 bytes rejects 1-byte garbage
    _ok() { [ -s "$_o" ] && [ "$(wc -c < "$_o" 2>/dev/null)" -ge 16 ] && return 0; return 1; }
    # asfetch: skip if proxy env is set
    if [ -z "${http_proxy:-}${ALL_PROXY:-}" ] && [ -n "${ABI_DIR:-}" ] \
       && [ -x "${ABI_BIN_DIR:-}/asfetch" ]; then
        rm -f "$_o"
        if [ -n "$_ref" ]; then "${ABI_BIN_DIR}/asfetch" -T "$TIMEOUT" -H "Referer: $_ref" -o "$_o" "$_u" 2>/dev/null
        else "${ABI_BIN_DIR}/asfetch" -T "$TIMEOUT" -o "$_o" "$_u" 2>/dev/null; fi
        _ok && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        rm -f "$_o"
        if [ -n "$_ref" ]; then curl -fsSL --max-time "$TIMEOUT" -e "$_ref" -o "$_o" "$_u" 2>/dev/null
        else curl -fsSL --max-time "$TIMEOUT" -o "$_o" "$_u" 2>/dev/null; fi
        _ok && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        rm -f "$_o"
        if [ -n "$_ref" ]; then wget -q -T "$TIMEOUT" --header "Referer: $_ref" -O "$_o" "$_u" 2>/dev/null
        else wget -q -T "$TIMEOUT" -O "$_o" "$_u" 2>/dev/null; fi
        _ok && return 0
    fi
    if [ -n "${BB:-}" ]; then
        rm -f "$_o"
        if [ -n "$_ref" ]; then "$BB" wget -q -T "$TIMEOUT" --header "Referer: $_ref" --no-check-certificate -O "$_o" "$_u" 2>/dev/null
        else "$BB" wget -q -T "$TIMEOUT" --no-check-certificate -O "$_o" "$_u" 2>/dev/null; fi
        _ok && return 0
    fi
    return 1
}

# Prefer busybox grep/tac: toybox's `grep -A` is unreliable
if [ -n "${BB:-}" ]; then GREP="$BB grep"; else GREP=grep; fi
reverse() { # portable `tac`
    if [ -n "${BB:-}" ]; then "$BB" tac
    elif command -v tac >/dev/null 2>&1; then tac
    else sed '1!G;h;$!d'; fi
}

W="$CONFIG_DIR/.pif_native.$$"
mkdir -p "$W" || { log "cannot create work dir."; exit 1; }
trap 'rm -rf "$W"' EXIT INT TERM

# ---- 1. latest Pixel Beta device list (Android Developers) ----
fetch "$W/versions.html" "https://developer.android.com/about/versions" || {
    log "developer.android.com unreachable."; exit 1; }
LATEST_URL=$($GREP -o 'https://developer.android.com/about/versions/.*[0-9]"' "$W/versions.html" \
    | sort -ru | cut -d'"' -f1 | head -n1)
[ -z "$LATEST_URL" ] && { log "no latest version page found."; exit 1; }
fetch "$W/latest.html" "$LATEST_URL" || { log "version page fetch failed."; exit 1; }

FI_HREF=$($GREP -o 'href=".*download.*"' "$W/latest.html" | $GREP 'qpr' | cut -d'"' -f2 | head -n1)
OTA_HREF=$($GREP -o 'href=".*download-ota.*"' "$W/latest.html" | $GREP 'qpr' | cut -d'"' -f2 | head -n1)
[ -n "$FI_HREF" ]  && fetch "$W/fi.html"  "https://developer.android.com$FI_HREF"
[ -n "$OTA_HREF" ] && fetch "$W/ota.html" "https://developer.android.com$OTA_HREF"

# Pick whichever table (Factory Image vs OTA) lists more devices.
SRC=fi
[ -s "$W/fi.html" ] || SRC=ota
if [ -s "$W/fi.html" ] && [ -s "$W/ota.html" ]; then
    nfi=$($GREP -c 'tr id=' "$W/fi.html" 2>/dev/null)
    nota=$($GREP -c 'tr id=' "$W/ota.html" 2>/dev/null)
    [ "${nota:-0}" -gt "${nfi:-0}" ] && SRC=ota
fi
[ -s "$W/$SRC.html" ] || { log "no device table."; exit 1; }

MODEL_LIST=$($GREP -A1 'tr id=' "$W/$SRC.html" | $GREP 'td' | sed 's;.*<td>\(.*\)</td>.*;\1;')
PRODUCT_LIST=$($GREP 'tr id=' "$W/$SRC.html" | sed 's;.*<tr id="\(.*\)".*;\1_beta;')
[ -z "$PRODUCT_LIST" ] && { log "device list parse failed."; exit 1; }

# --list mode: output JSON device catalogue and exit immediately
if [ "${LIST_ONLY:-0}" = 1 ]; then
    printf '{"model":['
    first=1
    echo "$MODEL_LIST" | while read -r m; do
        [ "$first" = 0 ] && printf ','
        printf '"%s"' "$m"
        first=0
    done
    printf '],"product":['
    first=1
    echo "$PRODUCT_LIST" | while read -r p; do
        [ "$first" = 0 ] && printf ','
        printf '"%s"' "$p"
        first=0
    done
    printf ']}\n'
    exit 0
fi

# ---- 2. select device: prefer an exact match for THIS device, else random ----
MODEL=""; PRODUCT=""; DEVICE=""
THISDEV=$(getprop ro.product.device 2>/dev/null)
case " $(echo $PRODUCT_LIST) " in
    *" ${THISDEV}_beta "*)
        MODEL=$(getprop ro.product.model 2>/dev/null)
        PRODUCT="${THISDEV}_beta"
        DEVICE="$THISDEV"
        ;;
esac
if [ -z "$PRODUCT" ]; then
    N=$(echo "$PRODUCT_LIST" | grep -c .)
    [ "${N:-0}" -lt 1 ] && { log "empty device list."; exit 1; }
    R="${RANDOM:-$$}"
    IDX=$(( (R % N) + 1 ))
    MODEL=$(echo "$MODEL_LIST"   | sed -n "${IDX}p")
    PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "${IDX}p")
    DEVICE=$(echo "$PRODUCT" | sed 's/_beta//')
fi
[ -z "$PRODUCT" ] || [ -z "$DEVICE" ] && { log "device selection failed."; exit 1; }
log "device: ${MODEL:-?} ($PRODUCT)"

# ---- 3. Android Flash Tool client key, then the Canary build JSON ----
fetch "$W/flash.html" "https://flash.android.com/" || { log "flash.android.com unreachable."; exit 1; }
KEY=$($GREP -o '<meta property="flashstation:client_id" content="[^"]*"' "$W/flash.html" | cut -d'"' -f4)
[ -z "$KEY" ] && { log "flashstation client key not found."; exit 1; }
fetch "$W/canary.json" "https://content-flashstation-pa.googleapis.com/v1/config/$DEVICE?key=$KEY" "https://flash.android.com" || { log "canary JSON fetch failed."; exit 1; }
ID=$($GREP 'releaseCandidateName' "$W/canary.json" | cut -d'"' -f4)
INCREMENTAL=$($GREP 'buildId' "$W/canary.json" | cut -d'"' -f4)
[ -z "$ID" ] || [ -z "$INCREMENTAL" ] && { log "canary build info missing from JSON."; exit 1; }

# ---- 4. security patch level from the Pixel Update Bulletins ----
CANARY_ID=$($GREP '"id"' "$W/canary.json" | sed -e 's;.*canary-\(.*\)".*;\1;' -e 's;^\(.\{4\}\);\1-;')
SECURITY_PATCH=""
if [ -n "$CANARY_ID" ]; then
    if fetch "$W/secbull.html" "https://source.android.com/docs/security/bulletin/pixel"; then
        SECURITY_PATCH=$($GREP "$CANARY_ID" "$W/secbull.html" | sed 's;.*>\([0-9-]*\)<.*;\1;' | head -n1)
    fi
    # autopif4's own fallback: assume the -05 patch for the canary month.
    [ -z "$SECURITY_PATCH" ] && SECURITY_PATCH="${CANARY_ID}-05"
fi
[ -z "$SECURITY_PATCH" ] && SECURITY_PATCH="$(date '+%Y-%m')-05"

# ---- 5. emit the pif.prop ----
FP="google/$PRODUCT/$DEVICE:CANARY/$ID/$INCREMENTAL:user/release-keys"
TMP="$W/pif.prop"
cat > "$TMP" <<EOF
MANUFACTURER=Google
MODEL=$MODEL
PRODUCT=$PRODUCT
DEVICE=$DEVICE
FINGERPRINT=$FP
SECURITY_PATCH=$SECURITY_PATCH
DEVICE_INITIAL_SDK_INT=32
EOF
cp -f "$TMP" "$TARGET" || { log "cannot write $TARGET."; exit 1; }
log "wrote $TARGET ($FP)"
exit 0
